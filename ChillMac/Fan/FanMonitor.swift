import Cocoa
import Combine
import IOKit.ps

final class FanMonitor: ObservableObject {
    @Published var fans: [FanInfo] = []
    @Published var sensors: [TemperatureSensor] = []
    @Published var smcError: String?
    @Published var helperReady = false
    /// False until the first poll has published results. Lets the UI tell "still reading the
    /// SMC" apart from "this Mac genuinely has no fans" — a fanless MacBook Air must end up
    /// with the empty-state message, not a spinner that never stops.
    @Published var hasCompletedFirstPoll = false

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
    /// The target RPM % that performance mode is currently requesting (0–100)
    @Published var performanceCurvePercent: Double = 0
    /// True when battery saver has suppressed performance mode
    @Published var batterySaverActive = false

    /// User overrides that persist across poll cycles
    @Published var manualOverrides: [Int: Bool] = [:]   // fanIndex → manual on/off
    @Published var targetOverrides: [Int: Double] = [:]  // fanIndex → target RPM

    /// Set by AppDelegate after helper is ready
    var helper: HelperConnection?

    /// Set by StatusBarController when popover opens/closes — controls adaptive poll interval
    var isPopoverVisible = false {
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
    /// When target/mode were last read from SMC. Drives the reduced-rate refresh while hidden.
    private var lastFullFanRead: Date?
    /// Last target/mode actually read from the hardware, per fan index. Reused on cycles that
    /// skip those reads so diagnostics record a measurement rather than an echo of our own
    /// commands. Cleared whenever we hand the fans back to macOS.
    private var lastMeasuredTarget: [Int: Double] = [:]
    private var lastMeasuredMode: [Int: Bool] = [:]

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
        // The fans just changed hands — anything we measured before is no longer their state.
        // Cleared on smcQueue because that's where the poll writes them.
        invalidateMeasuredFanState()
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

    /// Current poll interval: 2s when popover visible or performance mode active, 10s idle
    private var currentPollInterval: TimeInterval {
        if isPopoverVisible || AppSettings.shared.performanceMode { return 2.0 }
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
        let popoverVisible = isPopoverVisible
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

                // Full read every cycle when visible. When hidden, refresh target/mode on a
                // time basis rather than a poll count — the poll interval varies (2s vs 10s),
                // and the diagnostic logger samples once a minute, so a count-based cadence
                // left it with nothing recently measured to record.
                let now = Date()
                let needsFullRead = popoverVisible
                    || self.lastFullFanRead.map { now.timeIntervalSince($0) >= 25 } ?? true
                if needsFullRead { self.lastFullFanRead = now }

                for i in 0..<fanCount {
                    // Keep the raw optional: a failed read is "unknown", not "0 RPM".
                    let rawCurrent = try? smc.readFanSpeed(index: i)
                    let current = self.clampRPM(rawCurrent ?? 0)

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

                    // Skip target/mode reads on in-between cycles — saves 2 IOKit calls per fan.
                    // On those cycles reuse the last real SMC reading (at most ~25s old) so
                    // diagnostics still get a measurement. Only when the hardware has never
                    // answered do we fall back to the app's own override cache, and that
                    // value is flagged unmeasured so it can be logged as null instead of
                    // being passed off as a reading.
                    let target: Double
                    let isManual: Bool
                    let targetValid: Bool
                    let modeValid: Bool
                    if needsFullRead {
                        let rawTarget = try? smc.readFanTargetSpeed(index: i)
                        let rawMode = try? smc.readFanMode(index: i)
                        if let rawTarget { self.lastMeasuredTarget[i] = self.clampRPM(rawTarget) }
                        if let rawMode { self.lastMeasuredMode[i] = rawMode }
                        target = self.clampRPM(rawTarget ?? 0)
                        isManual = rawMode ?? false
                        targetValid = rawTarget != nil
                        modeValid = rawMode != nil
                    } else {
                        let measuredTarget = self.lastMeasuredTarget[i]
                        let measuredMode = self.lastMeasuredMode[i]
                        target = measuredTarget ?? targetOverridesSnapshot[i] ?? 0
                        isManual = measuredMode ?? manualOverridesSnapshot[i] ?? false
                        targetValid = measuredTarget != nil
                        modeValid = measuredMode != nil
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
                        isManualMode: isManual,
                        currentRPMValid: rawCurrent != nil,
                        targetRPMValid: targetValid,
                        isManualModeValid: modeValid
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

                // Only publish when popover is visible or performance mode needs fan data,
                // to avoid unnecessary SwiftUI view diffs while the popover is hidden.
                if let updatedFans, self.isPopoverVisible || performanceMode {
                    if self.fans != updatedFans {
                        self.fans = updatedFans
                    }
                    // Flagged on publish, not on poll completion: while the popover is hidden
                    // and performance mode is off, polls run but `fans` is never filled in, so
                    // "a poll finished" wouldn't mean the array is trustworthy yet.
                    if !self.hasCompletedFirstPoll {
                        self.hasCompletedFirstPoll = true
                    }
                }

                // Threshold @Published updates — EMA produces hundredths-of-a-degree noise that
                // would otherwise fire SwiftUI invalidations every 2s for the entire 24/7 lifetime
                // of the app, even with the popover closed (NSHostingController retains the view tree).
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
                // Only publish sensor array UI data when the popover is visible
                if self.isPopoverVisible {
                    if self.sensors != stableSensors {
                        self.sensors = stableSensors
                    }
                }
                // Performance mode: zone-aware fan curve based on per-zone temperatures
                self.applyPerformanceCurve(sensors: sensorsByKey, batterySaverShouldSuppress: batterySaverShouldSuppress)
            }
        }
    }

    // MARK: - Performance Mode Fan Curve

    /// Minimum fan speed % (above minRPM) while performance mode is engaged.
    /// Keeping a non-zero floor — and staying in manual mode — eliminates the audible
    /// "on / off / on / off" cycling that happens when fans bounce between manual and auto.
    private func minFanSpeedFloor() -> Double {
        switch AppSettings.shared.performanceLevel {
        case .low: return 0.0      // sits at exactly minRPM — inaudible, but never auto
        case .medium: return 0.10
        case .high: return 0.25
        case .max: return 0.50     // proactive baseline; never need to spin up from cold
        }
    }

    /// Max RPM increase per 2s poll cycle. Lower = gentler audible ramp-up.
    private func rampUpRate() -> Double {
        switch AppSettings.shared.performanceLevel {
        case .low: return 400
        case .medium: return 700
        case .high: return 1200
        case .max: return 2000
        }
    }

    /// Max RPM decrease per 2s poll cycle. Always slower than ramp-up.
    private func rampDownRate() -> Double {
        switch AppSettings.shared.performanceLevel {
        case .low: return 150
        case .medium: return 250
        case .high: return 400
        case .max: return 500
        }
    }

    /// EMA factor for temperature smoothing — lower = heavier smoothing, slower reactivity.
    /// Low mode is heavily damped so brief temp spikes don't audibly spin the fans up.
    private func smoothingFactor() -> Double {
        switch AppSettings.shared.performanceLevel {
        case .low: return 0.15
        case .medium: return 0.25
        case .high: return 0.35
        case .max: return 0.50
        }
    }

    /// Maps a (smoothed) peak zone temperature to a fan speed % between the level's
    /// floor and 100%. Curves are continuous so there are no audible cliffs.
    private func fanSpeedPercent(forTemperature temp: Double) -> Double {
        switch AppSettings.shared.performanceLevel {
        case .low:
            // Floor = minRPM (inaudible). Only intervenes once the chassis is genuinely hot.
            switch temp {
            case ...70: return 0.0
            case 70..<85:  return        (temp - 70) / 15.0 * 0.30  // 0 → 30%
            case 85..<95:  return 0.30 + (temp - 85) / 10.0 * 0.30  // 30 → 60%
            case 95..<105: return 0.60 + (temp - 95) / 10.0 * 0.20  // 60 → 80%
            default: return 0.80
            }
        case .medium:
            // Floor = 10%. Quiet idle, responsive once load shows up.
            switch temp {
            case ...55: return 0.10
            case 55..<70: return 0.10 + (temp - 55) / 15.0 * 0.25   // 10 → 35%
            case 70..<82: return 0.35 + (temp - 70) / 12.0 * 0.30   // 35 → 65%
            case 82..<92: return 0.65 + (temp - 82) / 10.0 * 0.25   // 65 → 90%
            default: return min(0.90 + (temp - 92) / 8.0 * 0.10, 1.0)
            }
        case .high:
            // Floor = 25%. Aggressive — keeps the chassis cool well before thermal pressure.
            switch temp {
            case ...45: return 0.25
            case 45..<58: return 0.25 + (temp - 45) / 13.0 * 0.25   // 25 → 50%
            case 58..<70: return 0.50 + (temp - 58) / 12.0 * 0.25   // 50 → 75%
            case 70..<82: return 0.75 + (temp - 70) / 12.0 * 0.20   // 75 → 95%
            default: return 1.0
            }
        case .max:
            // Smart max: high baseline (50%) so cooling is preemptive, ramps to 100% well
            // before throttle territory. NOT constant-100% — that's pointless noise & wear
            // when there's thermal headroom.
            switch temp {
            case ...40: return 0.50
            case 40..<55: return 0.50 + (temp - 40) / 15.0 * 0.20   // 50 → 70%
            case 55..<68: return 0.70 + (temp - 55) / 13.0 * 0.30   // 70 → 100%
            default: return 1.0
            }
        }
    }

    private func applyPerformanceCurve(sensors: [String: TemperatureSensor], batterySaverShouldSuppress: Bool) {
        // Skip fan commands while system is asleep or performance is suspended (screen lock/sleep)
        guard !systemAsleep, !performanceSuspended else { return }

        let performanceEnabled = AppSettings.shared.performanceMode && helperReady

        // Re-evaluate poll interval when performance mode changes
        if performanceEnabled != wasPerformanceModeActive || (performanceEnabled && !wasPerformanceModeActive) {
            updatePollInterval()
        }

        // Battery saver: suppress performance mode when on battery below threshold
        let batterySaving = performanceEnabled && batterySaverShouldSuppress
        let isActive = performanceEnabled && !batterySaving
        batterySaverActive = batterySaving

        guard let helper = helper else { return }

        // If performance mode was just turned off (or suppressed by battery saver), hand fans
        // back to macOS auto. This is the ONLY path that returns fans to auto — while perf
        // mode is engaged, fans stay in manual mode (at the level's floor at minimum).
        if wasPerformanceModeActive && !isActive {
            wasPerformanceModeActive = false
            for fan in fans {
                helper.setFanMode(fanIndex: fan.id, isAuto: true) { _, _ in }
            }
            manualOverrides.removeAll()
            targetOverrides.removeAll()
            performanceCurvePercent = 0
            smoothedZoneTemps.removeAll()
            lastSentRPM.removeAll()
            // Force a fresh read now that macOS owns the fans again.
            invalidateMeasuredFanState()
            return
        }

        guard isActive else { return }
        wasPerformanceModeActive = true

        let floor = minFanSpeedFloor()
        let smoothFactor = smoothingFactor()
        let upRate = rampUpRate()
        let downRate = rampDownRate()

        // Per-zone smoothed temp → curve % contribution
        var zonePcts: [ThermalZone: Double] = [:]
        for zone in ThermalZone.allCases {
            guard let zoneKeys = Self.zoneSensorKeys[zone] else { continue }
            let zonePeak = zoneKeys.compactMap { sensors[$0]?.temperature }.max()
            guard let peak = zonePeak, peak > 0 else { continue }

            if let prev = smoothedZoneTemps[zone] {
                smoothedZoneTemps[zone] = prev + smoothFactor * (peak - prev)
            } else {
                smoothedZoneTemps[zone] = peak
            }
            zonePcts[zone] = fanSpeedPercent(forTemperature: smoothedZoneTemps[zone]!)
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

        // Floor: every fan sits at >= floor while perf mode is on. This is what kills
        // the audible on/off/on/off cycling — fans never drop to "auto" mid-session.
        for fan in fans {
            fanPcts[fan.id] = max(fanPcts[fan.id] ?? 0, floor)
        }

        // UI shows the highest fan percentage
        let maxPct = fanPcts.values.max() ?? floor
        performanceCurvePercent = maxPct * 100

        // Send each fan to its target with per-level rate limiting
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

            // Suppress XPC spam unless the target moved or we don't yet own the fan
            let currentTarget = targetOverrides[fan.id] ?? -1
            let alreadyManual = manualOverrides[fan.id] == true
            guard abs(rounded - currentTarget) >= 100 || !alreadyManual else { continue }

            lastSentRPM[fan.id] = rounded
            targetOverrides[fan.id] = rounded
            manualOverrides[fan.id] = true
            helper.setFanSpeed(fanIndex: fan.id, rpm: Int(rounded)) { _, _ in }
        }
    }

    /// Drops the cached SMC readings for target/mode and forces the next poll to re-read them.
    /// Hops to `smcQueue` because that is the only place those values are written.
    private func invalidateMeasuredFanState() {
        smcQueue.async {
            self.lastFullFanRead = nil
            self.lastMeasuredTarget.removeAll()
            self.lastMeasuredMode.removeAll()
        }
    }

    /// Clamp RPM to a sane range — guards against bad float/fpe2 decoding
    private func clampRPM(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 20000)
    }
}
