import Cocoa
import Combine
import IOKit.ps

final class FanMonitor: ObservableObject {
    @Published var fans: [FanInfo] = []
    @Published var sensors: [TemperatureSensor] = []
    @Published var smcError: String?
    @Published var helperReady = false

    /// The hottest sensor temperature from the last poll (used by performance mode UI)
    @Published var peakTemperature: Double = 0
    /// Label of the sensor currently holding `peakTemperature` (e.g. "CPU Die (Peak)")
    @Published var peakTemperatureLabel: String = ""
    /// Peak temperature for the CPU zone (nil if no CPU sensors discovered)
    @Published var peakCpuTemperature: Double = 0
    /// Peak temperature for the GPU zone
    @Published var peakGpuTemperature: Double = 0
    /// Peak temperature for the SSD zone
    @Published var peakSsdTemperature: Double = 0
    /// The target RPM % that Cool is currently requesting while engaged (0–100); 0 when idle
    @Published var performanceCurvePercent: Double = 0
    /// True when battery saver has suppressed Cool
    @Published var batterySaverActive = false
    /// True when Cool is on and hysteresis engagement is active (driving fans)
    @Published var coolingEngaged = false
    /// Live ProcessInfo thermal state for Cool throttle cue (Fair / Serious / Critical).
    @Published var processThermalState: ProcessInfo.ThermalState = .nominal

    /// User overrides that persist across poll cycles
    @Published var manualOverrides: [Int: Bool] = [:]   // fanIndex → manual on/off
    @Published var targetOverrides: [Int: Double] = [:]  // fanIndex → target RPM

    /// Set by AppDelegate after helper is ready
    var helper: HelperConnection?

    /// Set by StatusBarController when the status menu opens/closes — controls adaptive poll interval
    var isMenuVisible = false {
        didSet { updatePollInterval() }
    }

    private var smc: SMCConnection?
    private var timer: Timer?
    private var discoveredSensors: [String: TemperatureSensor] = [:]
    /// After initial discovery, only poll keys that have been found at least once
    private var activeSensorKeys: Set<String>?
    private var discoveryPollCount: Int = 0
    /// Track whether performance mode was active last poll so we can reset fans on toggle-off
    private var wasPerformanceModeActive = false

    // MARK: - Static Fan Property Cache
    private var cachedFanCount: Int?
    private var cachedMinRPM: [Int: Double] = [:]
    private var cachedMaxRPM: [Int: Double] = [:]

    // MARK: - Background Queue
    private let smcQueue = DispatchQueue(label: "com.idevtim.ChillMac.smc")
    /// Guard against overlapping poll cycles
    private var pollInFlight = false
    /// Counter for periodic full fan reads when menu is hidden (for diagnostic accuracy)
    private var backgroundPollCount: UInt = 0

    // MARK: - Thermal Zones

    private enum ThermalZone: String, CaseIterable {
        case cpu, gpu, memory, ssd, dieVRM, battery, ambient
    }

    /// Which SMC sensor keys belong to each thermal zone
    private static let zoneSensorKeys: [ThermalZone: Set<String>] = [
        .cpu:     ["Tp09","Tp0T","Tp01","Tp05","Tp0D","Tp0H","Tp0L","Tp0P","Tp0X","Tp0b",
                   "TCDX","TCMb","TCMz","TCHP","TC0P","TC0D"],
        .gpu:     ["TPDX","TPMP","TPSP","TG0P","TG0D"],
        .memory:  ["TRDX","TRD0","TMVR","Tm0P"],
        .ssd:     ["TH0x","TH0a","TH0b"],
        .dieVRM:  ["TDVx","TDTP","TDBP","TDCR"],
        .battery: ["TB0T","TB1T","TB2T"],
        .ambient: ["TAOL","TDEL","TDER","TDeL","TDeR","Ts0P","TA0P"],
    ]

    /// Fan affinity weights per zone: (Fan 0 / Left, Fan 1 / Right)
    /// Higher weight = this fan is more responsible for cooling this zone
    private static let zoneFanAffinity: [ThermalZone: (left: Double, right: Double)] = [
        .cpu:     (1.0, 1.0),   // SoC is center — both fans equally
        .gpu:     (1.0, 1.0),   // GPU is on-die with CPU on Apple Silicon
        .memory:  (1.0, 1.0),   // On-package DRAM — both fans
        .ssd:     (0.4, 1.0),   // SSD controller typically near right side
        .dieVRM:  (0.8, 0.8),   // Distributed power delivery
        .battery: (0.6, 0.6),   // Batteries span both sides, low priority
        .ambient: (0.5, 0.5),   // General — minimal contribution
    ]

    // MARK: - Fan Speed Smoothing

    /// Per-zone exponential moving average of peak temperature
    private var smoothedZoneTemps: [ThermalZone: Double] = [:]
    /// Track the last RPM we actually sent to each fan for gradual ramping
    private var lastSentRPM: [Int: Double] = [:]

    /// Track whether system is asleep so we skip fan commands
    private var systemAsleep = false
    /// Guard against double-registering system observers
    private var observersInstalled = false
    /// Track whether performance curve is suspended (screen sleep/lock)
    private var performanceSuspended = false
    /// Hysteresis: seconds spent in current engage/release temperature band
    private var engagementBandSeconds: TimeInterval = 0
    private var lastEngagementEval: Date?
    /// Cached ProcessInfo thermal gate
    private var thermalForceEngage = false
    private var thermalObserver: NSObjectProtocol?

    // MARK: - System Event Observers

    /// Call once after helper is ready. Listens for sleep/wake/lid-close to reset fans.
    func setupSystemObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let ws = NSWorkspace.shared.notificationCenter

        ws.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleScreenSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleScreenWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Screen lock/unlock (Ctrl+Cmd+Q, fast user switch, etc.)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleScreenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(handleScreenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        refreshThermalForceEngage()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshThermalForceEngage()
        }
    }

    private func refreshThermalForceEngage() {
        let state = ProcessInfo.processInfo.thermalState
        if processThermalState != state {
            processThermalState = state
        }
        thermalForceEngage = (state == .serious || state == .critical)
    }

    @objc private func handleSleep() {
        let shouldReset = DisplaySleepFanPolicy.shouldResetFansOnSystemWillSleep(
            keepClosedOnPower: AppSettings.shared.keepFansClosedOnPower,
            keepOnScreenSleep: AppSettings.shared.keepFansOnScreenSleep,
            onAC: PowerSource.isOnAC
        )
        if !shouldReset {
            // Lid-close often posts willSleep after screensDidSleep. Do not undo a keep decision
            // by forcing fans back to auto — especially keepClosedOnPower + AC.
            NSLog("FanMonitor: system willSleep — keeping fans active (user preference)")
            return
        }
        NSLog("FanMonitor: system going to sleep — resetting fans to auto")
        systemAsleep = true
        resetAllFansToAuto()
    }

    @objc private func handleWake() {
        NSLog("FanMonitor: system woke up")
        systemAsleep = false
        // Performance curve will reapply on next poll cycle automatically
    }

    @objc private func handleScreenSleep() {
        if DisplaySleepFanPolicy.shouldKeepFansThroughDisplaySleep(
            keepClosedOnPower: AppSettings.shared.keepFansClosedOnPower,
            keepOnScreenSleep: AppSettings.shared.keepFansOnScreenSleep,
            onAC: PowerSource.isOnAC
        ) {
            NSLog("FanMonitor: screen sleep — keeping fans active (user preference)")
            return
        }
        NSLog("FanMonitor: screen sleep (lid closed) — suspending performance, resetting fans")
        performanceSuspended = true
        resetAllFansToAuto()
    }

    @objc private func handleScreenWake() {
        NSLog("FanMonitor: screen woke (lid opened)")
        performanceSuspended = false
        resumePerformanceImmediately()
    }

    @objc private func handleScreenLocked() {
        if DisplaySleepFanPolicy.shouldKeepFansThroughDisplaySleep(
            keepClosedOnPower: AppSettings.shared.keepFansClosedOnPower,
            keepOnScreenSleep: AppSettings.shared.keepFansOnScreenSleep,
            onAC: PowerSource.isOnAC
        ) {
            NSLog("FanMonitor: screen locked — keeping fans active (user preference)")
            return
        }
        NSLog("FanMonitor: screen locked — suspending performance, resetting fans")
        performanceSuspended = true
        resetAllFansToAuto()
    }

    @objc private func handleScreenUnlocked() {
        NSLog("FanMonitor: screen unlocked")
        performanceSuspended = false
        resumePerformanceImmediately()
    }

    /// Reset all fans back to auto mode.
    /// Uses SMC fan count directly so this works even if `fans` array is empty or stale.
    func resetAllFansToAuto() {
        guard let helper = helper else { return }

        // Read fan count from SMC directly — fans array may be empty on sleep
        let fanCount: Int
        if let smc = try? SMCConnection() {
            fanCount = max((try? smc.readFanCount()) ?? 0, fans.count)
            smc.close()
        } else {
            fanCount = fans.count
        }

        for i in 0..<fanCount {
            helper.setFanMode(fanIndex: i, isAuto: true) { _, _ in }
        }

        wasPerformanceModeActive = false
        smoothedZoneTemps.removeAll()
        lastSentRPM.removeAll()
        DispatchQueue.main.async {
            self.manualOverrides.removeAll()
            self.targetOverrides.removeAll()
            self.performanceCurvePercent = 0
        }
    }

    /// After screen wake/unlock, trigger an immediate poll so fans don't wait up to 2s.
    /// Runs on main thread to avoid "Publishing changes from within view updates" warnings.
    private func resumePerformanceImmediately() {
        guard AppSettings.shared.performanceMode, helperReady, smc != nil else { return }
        // Small delay to let the auto-reset XPC calls complete first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.poll()
        }
    }

    // MARK: - Battery State (lightweight check for battery saver)

    private struct BatterySaverPolicy {
        let enabled: Bool
        let forcePerformanceOnBattery: Bool
        let threshold: Int
    }

    private func checkBatterySaver(policy: BatterySaverPolicy) -> Bool {
        guard policy.enabled, !policy.forcePerformanceOnBattery else { return false }

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, firstSource)?.takeUnretainedValue() as? [String: Any]
        else { return false }

        let isOnAC = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if isOnAC { return false }

        let charge = info[kIOPSCurrentCapacityKey] as? Int ?? 100
        return charge <= policy.threshold
    }

    func startMonitoring() {
        do {
            smc = try SMCConnection()
            smcError = nil
        } catch {
            smcError = error.localizedDescription
            return
        }

        poll()
        schedulePollTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        smc?.close()
        smc = nil
        cachedFanCount = nil
        cachedMinRPM.removeAll()
        cachedMaxRPM.removeAll()
        removeSystemObservers()
    }

    /// Current poll interval: 2s when menu visible or performance mode active, 10s idle
    private var currentPollInterval: TimeInterval {
        if isMenuVisible || AppSettings.shared.performanceMode { return 2.0 }
        return 10.0
    }

    private func schedulePollTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentPollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Re-evaluate poll interval when conditions change
    func updatePollInterval() {
        guard timer != nil else { return }
        schedulePollTimer()
    }

    private func removeSystemObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func poll() {
        guard let smc = smc, !pollInFlight else { return }
        pollInFlight = true
        let menuVisible = isMenuVisible
        let performanceMode = AppSettings.shared.performanceMode
        let helperReadySnapshot = helperReady
        let manualOverridesSnapshot = manualOverrides
        let targetOverridesSnapshot = targetOverrides
        let batterySaverPolicy = BatterySaverPolicy(
            enabled: AppSettings.shared.batterySaverEnabled,
            forcePerformanceOnBattery: AppSettings.shared.forcePerformanceOnBattery,
            threshold: AppSettings.shared.batterySaverThreshold
        )

        smcQueue.async { [weak self] in
            guard let self else { return }
            var updatedFans: [FanInfo]?
            var pollError: String?

            // Read fans
            do {
                let fanCount = try self.cachedFanCount ?? smc.readFanCount()
                if self.cachedFanCount == nil { self.cachedFanCount = fanCount }

                var fanSnapshot: [FanInfo] = []

                // Full read every cycle when visible; every 15th cycle (~30s) when hidden
                // to keep diagnostic samples accurate without constant IOKit overhead
                self.backgroundPollCount += 1
                let needsFullRead = menuVisible || (!menuVisible && self.backgroundPollCount % 15 == 0)

                for i in 0..<fanCount {
                    let current = self.clampRPM((try? smc.readFanSpeed(index: i)) ?? 0)

                    // Use cached min/max — they're hardware constants
                    let minRPM: Double
                    if let cached = self.cachedMinRPM[i] {
                        minRPM = cached
                    } else {
                        var raw = self.clampRPM((try? smc.readFanMinSpeed(index: i)) ?? 0)
                        if raw < 100 { raw = 1000 }
                        self.cachedMinRPM[i] = raw
                        minRPM = raw
                    }

                    let maxRPM: Double
                    if let cached = self.cachedMaxRPM[i] {
                        maxRPM = cached
                    } else {
                        var raw = self.clampRPM((try? smc.readFanMaxSpeed(index: i)) ?? 6500)
                        if raw < 1000 || raw <= minRPM { raw = 15000 }
                        self.cachedMaxRPM[i] = raw
                        maxRPM = raw
                    }

                    // Skip target/mode reads when menu is hidden — saves 2 IOKit calls per fan
                    let target: Double
                    let isManual: Bool
                    if needsFullRead {
                        target = self.clampRPM((try? smc.readFanTargetSpeed(index: i)) ?? 0)
                        isManual = (try? smc.readFanMode(index: i)) ?? false
                    } else {
                        target = targetOverridesSnapshot[i] ?? 0
                        isManual = manualOverridesSnapshot[i] ?? false
                    }

                    let name: String
                    if fanCount == 1 {
                        name = "Fan"
                    } else if i == 0 {
                        name = "Left Fan"
                    } else if i == 1 {
                        name = "Right Fan"
                    } else {
                        name = "Fan \(i + 1)"
                    }

                    fanSnapshot.append(FanInfo(
                        id: i,
                        name: name,
                        currentRPM: current,
                        minRPM: minRPM,
                        maxRPM: maxRPM,
                        targetRPM: target,
                        isManualMode: isManual
                    ))
                }

                updatedFans = fanSnapshot
            } catch {
                pollError = error.localizedDescription
            }

            // Read temperature sensors — after 5 full discovery passes, only poll active keys
            self.discoveryPollCount += 1
            let keysToProbe: [(key: String, label: String)]
            if let activeKeys = self.activeSensorKeys {
                keysToProbe = SMCKey.temperatureKeys.filter { activeKeys.contains($0.key) }
            } else {
                keysToProbe = SMCKey.temperatureKeys
            }

            for (key, label) in keysToProbe {
                if let temp = try? smc.readTemperature(key: key), temp > 0, temp < 150 {
                    self.discoveredSensors[key] = TemperatureSensor(id: key, label: label, temperature: temp)
                }
            }

            // After 5 discovery passes, lock to only discovered keys
            if self.activeSensorKeys == nil && self.discoveryPollCount >= 5 && !self.discoveredSensors.isEmpty {
                self.activeSensorKeys = Set(self.discoveredSensors.keys)
            }

            let stableSensors = SMCKey.temperatureKeys.compactMap { key, _ in
                self.discoveredSensors[key]
            }
            let hottest = stableSensors.max { $0.temperature < $1.temperature }
            let peak = hottest?.temperature ?? 0
            let peakLabel = hottest?.label ?? ""

            // Categorical peaks by thermal zone (used by DiagnosticLogger)
            func zonePeak(_ zone: ThermalZone) -> Double {
                guard let keys = Self.zoneSensorKeys[zone] else { return 0 }
                return keys.compactMap { self.discoveredSensors[$0]?.temperature }.max() ?? 0
            }
            let cpuPeak = zonePeak(.cpu)
            let gpuPeak = zonePeak(.gpu)
            let ssdPeak = zonePeak(.ssd)
            let sensorsByKey = self.discoveredSensors
            let batterySaverShouldSuppress = performanceMode && helperReadySnapshot
                ? self.checkBatterySaver(policy: batterySaverPolicy)
                : false

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.pollInFlight = false }

                if let pollError {
                    self.smcError = pollError
                } else if self.smcError != nil {
                    self.smcError = nil
                }

                // Only publish when menu is visible or performance mode needs fan data,
                // to avoid unnecessary SwiftUI view diffs while the menu is closed.
                if let updatedFans,
                   (self.isMenuVisible || performanceMode),
                   self.fans != updatedFans {
                    self.fans = updatedFans
                }

                // Threshold @Published updates — EMA produces hundredths-of-a-degree noise that
                // would otherwise fire SwiftUI invalidations every 2s for the entire 24/7 lifetime
                // of the app, even with the menu closed.
                let tempEpsilon = 0.1
                if abs(self.peakTemperature - peak) >= tempEpsilon {
                    self.peakTemperature = peak
                }
                if self.peakTemperatureLabel != peakLabel {
                    self.peakTemperatureLabel = peakLabel
                }
                if abs(self.peakCpuTemperature - cpuPeak) >= tempEpsilon {
                    self.peakCpuTemperature = cpuPeak
                }
                if abs(self.peakGpuTemperature - gpuPeak) >= tempEpsilon {
                    self.peakGpuTemperature = gpuPeak
                }
                if abs(self.peakSsdTemperature - ssdPeak) >= tempEpsilon {
                    self.peakSsdTemperature = ssdPeak
                }
                // Only publish sensor array UI data when the menu is visible
                if self.isMenuVisible {
                    if self.sensors != stableSensors {
                        self.sensors = stableSensors
                    }
                }
                // Defer curve/UI publishes to the next turn so they don't land mid-body
                // while SwiftUI is still applying the fan/sensor updates above.
                DispatchQueue.main.async {
                    self.applyPerformanceCurve(sensors: sensorsByKey, batterySaverShouldSuppress: batterySaverShouldSuppress)
                }
            }
        }
    }

    // MARK: - Performance Mode Fan Curve

    private func applyPerformanceCurve(sensors: [String: TemperatureSensor], batterySaverShouldSuppress: Bool) {
        // Skip fan commands while system is asleep or performance is suspended (screen lock/sleep)
        guard !systemAsleep, !performanceSuspended else { return }

        let performanceEnabled = AppSettings.shared.performanceMode && helperReady

        // Re-evaluate poll interval when performance mode changes
        if performanceEnabled != wasPerformanceModeActive || (performanceEnabled && !wasPerformanceModeActive) {
            updatePollInterval()
        }

        // Battery saver: suppress Cool when on battery below threshold
        let batterySaving = performanceEnabled && batterySaverShouldSuppress
        let coolOn = performanceEnabled && !batterySaving
        if batterySaverActive != batterySaving {
            batterySaverActive = batterySaving
        }

        guard let helper = helper else { return }

        // Cool turned off (or battery saver) → hand fans back to macOS auto
        if wasPerformanceModeActive && !coolOn {
            wasPerformanceModeActive = false
            coolingEngaged = false
            engagementBandSeconds = 0
            lastEngagementEval = nil
            handFansToAuto(helper: helper)
            return
        }

        guard coolOn else {
            if coolingEngaged { coolingEngaged = false }
            return
        }
        wasPerformanceModeActive = true

        let intent = AppSettings.shared.coolIntent
        let peak = sensors.values.map(\.temperature).max() ?? peakTemperature

        // Track time in engage/release band for hysteresis
        let now = Date()
        let dt: TimeInterval
        if let last = lastEngagementEval {
            dt = min(now.timeIntervalSince(last), 5)
        } else {
            dt = 2
        }
        lastEngagementEval = now

        let engageAt = CoolingEngagement.engageCelsius(intent: intent)
        let releaseAt = CoolingEngagement.releaseCelsius(intent: intent)
        if coolingEngaged {
            if peak <= releaseAt {
                engagementBandSeconds += dt
            } else {
                engagementBandSeconds = 0
            }
        } else {
            if peak >= engageAt {
                engagementBandSeconds += dt
            } else {
                engagementBandSeconds = 0
            }
        }

        let next = CoolingEngagement.nextState(
            currentlyEngaged: coolingEngaged,
            peakCelsius: peak,
            intent: intent,
            thermalForceEngage: thermalForceEngage,
            secondsInBand: engagementBandSeconds
        )

        if next == .idle {
            if coolingEngaged {
                coolingEngaged = false
                engagementBandSeconds = 0
                handFansToAuto(helper: helper)
            }
            if performanceCurvePercent != 0 {
                performanceCurvePercent = 0
            }
            return
        }

        if !coolingEngaged {
            coolingEngaged = true
            engagementBandSeconds = 0
        }

        let floor = PerformanceCurve.minFloor(intent: intent, engaged: true)
        let smoothFactor = PerformanceCurve.smoothingFactor(intent: intent)
        let upRate = PerformanceCurve.rampUpRate(intent: intent)
        let downRate = PerformanceCurve.rampDownRate(intent: intent)

        // Per-zone smoothed temp → curve % contribution
        var zonePcts: [ThermalZone: Double] = [:]
        for zone in ThermalZone.allCases {
            guard let zoneKeys = Self.zoneSensorKeys[zone] else { continue }
            let zonePeak = zoneKeys.compactMap { sensors[$0]?.temperature }.max()
            guard let zoneTemp = zonePeak, zoneTemp > 0 else { continue }

            if let prev = smoothedZoneTemps[zone] {
                smoothedZoneTemps[zone] = prev + smoothFactor * (zoneTemp - prev)
            } else {
                smoothedZoneTemps[zone] = zoneTemp
            }
            zonePcts[zone] = PerformanceCurve.speedPercent(
                intent: intent,
                temperature: smoothedZoneTemps[zone]!
            )
        }

        // Each fan = max contribution across zones (weighted by zone-fan affinity)
        var fanPcts: [Int: Double] = [:]
        let isSingleFan = fans.count <= 1
        for (zone, pct) in zonePcts {
            guard let affinity = Self.zoneFanAffinity[zone] else { continue }
            if isSingleFan {
                let contribution = pct * max(affinity.left, affinity.right)
                fanPcts[0] = max(fanPcts[0] ?? 0, contribution)
            } else {
                fanPcts[0] = max(fanPcts[0] ?? 0, pct * affinity.left)
                fanPcts[1] = max(fanPcts[1] ?? 0, pct * affinity.right)
                for fan in fans where fan.id > 1 {
                    let contribution = pct * max(affinity.left, affinity.right)
                    fanPcts[fan.id] = max(fanPcts[fan.id] ?? 0, contribution)
                }
            }
        }

        // Soft floor only while engaged
        for fan in fans {
            fanPcts[fan.id] = max(fanPcts[fan.id] ?? 0, floor)
        }

        let maxPct = fanPcts.values.max() ?? floor
        let curvePercent = maxPct * 100
        if abs(performanceCurvePercent - curvePercent) >= 0.5 {
            performanceCurvePercent = curvePercent
        }

        for fan in fans {
            let pct = fanPcts[fan.id] ?? floor
            let desiredRPM = fan.minRPM + pct * (fan.maxRPM - fan.minRPM)

            var rampedRPM = desiredRPM
            if let lastRPM = lastSentRPM[fan.id] {
                let delta = desiredRPM - lastRPM
                if delta > 0 {
                    rampedRPM = min(desiredRPM, lastRPM + upRate)
                } else {
                    rampedRPM = max(desiredRPM, lastRPM - downRate)
                }
            }

            let rounded = (rampedRPM / 100).rounded() * 100

            let currentTarget = targetOverrides[fan.id] ?? -1
            let alreadyManual = manualOverrides[fan.id] == true
            guard abs(rounded - currentTarget) >= 100 || !alreadyManual else { continue }

            let fanId = fan.id
            let rpmToSend = Int(rounded)
            helper.setFanSpeed(fanIndex: fanId, rpm: rpmToSend) { [weak self] ok, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    FanTargetCommit.apply(
                        ok: ok,
                        fanId: fanId,
                        rpm: Double(rpmToSend),
                        manualOverrides: &self.manualOverrides,
                        targetOverrides: &self.targetOverrides,
                        lastSentRPM: &self.lastSentRPM
                    )
                }
            }
        }
    }

    private func handFansToAuto(helper: HelperConnection) {
        for fan in fans {
            helper.setFanMode(fanIndex: fan.id, isAuto: true) { _, _ in }
        }
        manualOverrides.removeAll()
        targetOverrides.removeAll()
        if performanceCurvePercent != 0 {
            performanceCurvePercent = 0
        }
        smoothedZoneTemps.removeAll()
        lastSentRPM.removeAll()
    }

    /// Clamp RPM to a sane range — guards against bad float/fpe2 decoding
    private func clampRPM(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 20000)
    }
}
