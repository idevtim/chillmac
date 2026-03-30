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

    // MARK: - Fan Speed Smoothing
    /// Exponential moving average of peak temperature to dampen sensor noise
    private var smoothedPeakTemp: Double?
    /// EMA factor: 0.3 = 30% new reading, 70% history (smooths out 2-3°C fluctuations)
    private let tempSmoothingFactor: Double = 0.3
    /// Track the last RPM we actually sent to each fan for gradual ramping
    private var lastSentRPM: [Int: Double] = [:]
    /// Max RPM increase per poll cycle (ramp up moderately fast — ~500 RPM/sec)
    private let maxRampUpPerCycle: Double = 1000
    /// Max RPM decrease per poll cycle (ramp down slowly — ~150 RPM/sec)
    private let maxRampDownPerCycle: Double = 300

    /// Track whether system is asleep so we skip fan commands
    private var systemAsleep = false
    /// Track whether performance curve is suspended (screen sleep/lock)
    private var performanceSuspended = false

    // MARK: - System Event Observers

    /// Call once after helper is ready. Listens for sleep/wake/lid-close to reset fans.
    func setupSystemObservers() {
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
        if AppSettings.shared.keepFansOnScreenSleep {
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
        if AppSettings.shared.keepFansOnScreenSleep {
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
        smoothedPeakTemp = nil
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

    private func checkBatterySaver() -> Bool {
        let settings = AppSettings.shared
        guard settings.batterySaverEnabled, !settings.forcePerformanceOnBattery else { return false }

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, firstSource)?.takeUnretainedValue() as? [String: Any]
        else { return false }

        let isOnAC = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if isOnAC { return false }

        let charge = info[kIOPSCurrentCapacityKey] as? Int ?? 100
        return charge <= settings.batterySaverThreshold
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

    /// Current poll interval: 2s when popover visible or performance mode active, 5s otherwise
    private var currentPollInterval: TimeInterval {
        (isPopoverVisible || AppSettings.shared.performanceMode) ? 2.0 : 5.0
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

        smcQueue.async { [weak self] in
            guard let self else { return }
            defer { self.pollInFlight = false }

            // Read fans
            do {
                let fanCount = try self.cachedFanCount ?? smc.readFanCount()
                if self.cachedFanCount == nil { self.cachedFanCount = fanCount }

                var updatedFans: [FanInfo] = []

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

                    let target = self.clampRPM((try? smc.readFanTargetSpeed(index: i)) ?? 0)
                    let isManual = (try? smc.readFanMode(index: i)) ?? false

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

                    updatedFans.append(FanInfo(
                        id: i,
                        name: name,
                        currentRPM: current,
                        minRPM: minRPM,
                        maxRPM: maxRPM,
                        targetRPM: target,
                        isManualMode: isManual
                    ))
                }

                DispatchQueue.main.async {
                    if self.fans != updatedFans {
                        self.fans = updatedFans
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.smcError = error.localizedDescription
                }
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
            let peak = stableSensors.map(\.temperature).max() ?? 0

            DispatchQueue.main.async {
                if self.sensors != stableSensors {
                    self.sensors = stableSensors
                }
                if self.peakTemperature != peak {
                    self.peakTemperature = peak
                }
                // Performance mode: apply aggressive fan curve based on peak temperature
                self.applyPerformanceCurve(peak: peak)
            }
        }
    }

    // MARK: - Performance Mode Fan Curve

    /// Maps peak sensor temperature to fan speed % based on the selected performance level.
    private func fanSpeedPercent(forTemperature temp: Double) -> Double {
        let level = AppSettings.shared.performanceLevel

        // Max: always full blast
        if level == .max { return 1.0 }

        switch level {
        case .low:
            // Gentle cooling, moderate cap
            switch temp {
            case ...65:
                return 0
            case 65..<80:
                return 0.15 + (temp - 65) / 15.0 * 0.15   // 15%→30%
            case 80..<92:
                return 0.30 + (temp - 80) / 12.0 * 0.25   // 30%→55%
            case 92..<100:
                return 0.55 + (temp - 92) / 8.0 * 0.15    // 55%→70%
            default:
                return 0.70
            }
        case .medium:
            // Balanced: earlier ramp, higher ceiling
            switch temp {
            case ...55:
                return 0
            case 55..<70:
                return 0.20 + (temp - 55) / 15.0 * 0.20   // 20%→40%
            case 70..<85:
                return 0.40 + (temp - 70) / 15.0 * 0.30   // 40%→70%
            case 85..<95:
                return 0.70 + (temp - 85) / 10.0 * 0.25   // 70%→95%
            default:
                return 1.0
            }
        case .high:
            // Aggressive: early ramp, fast escalation
            switch temp {
            case ...45:
                return 0
            case 45..<60:
                return 0.30 + (temp - 45) / 15.0 * 0.20   // 30%→50%
            case 60..<75:
                return 0.50 + (temp - 60) / 15.0 * 0.30   // 50%→80%
            case 75..<88:
                return 0.80 + (temp - 75) / 13.0 * 0.20   // 80%→100%
            default:
                return 1.0
            }
        case .max:
            return 1.0  // handled above, but Swift requires exhaustive switch
        }
    }

    private func applyPerformanceCurve(peak: Double) {
        // Skip fan commands while system is asleep or performance is suspended (screen lock/sleep)
        guard !systemAsleep, !performanceSuspended else { return }

        let performanceEnabled = AppSettings.shared.performanceMode && helperReady

        // Re-evaluate poll interval when performance mode changes
        if performanceEnabled != wasPerformanceModeActive || (performanceEnabled && !wasPerformanceModeActive) {
            updatePollInterval()
        }

        // Battery saver: suppress performance mode when on battery below threshold
        let batterySaving = performanceEnabled && checkBatterySaver()
        let isActive = performanceEnabled && !batterySaving
        batterySaverActive = batterySaving

        guard let helper = helper else { return }

        // If performance mode was just turned off (or suppressed by battery saver), reset fans
        if wasPerformanceModeActive && !isActive {
            wasPerformanceModeActive = false
            for fan in fans {
                helper.setFanMode(fanIndex: fan.id, isAuto: true) { _, _ in }
            }
            manualOverrides.removeAll()
            targetOverrides.removeAll()
            performanceCurvePercent = 0
            smoothedPeakTemp = nil
            lastSentRPM.removeAll()
            return
        }

        guard isActive else { return }
        wasPerformanceModeActive = true

        // Check raw reading first — if it would activate fans, seed the
        // smoothed value so there's no EMA lag on the idle→active transition
        let rawPct = fanSpeedPercent(forTemperature: peak)
        if rawPct > 0 && fanSpeedPercent(forTemperature: smoothedPeakTemp ?? peak) <= 0 {
            smoothedPeakTemp = peak
        }

        // Smooth the peak temperature to avoid chasing sensor noise
        if let prev = smoothedPeakTemp {
            smoothedPeakTemp = prev + tempSmoothingFactor * (peak - prev)
        } else {
            smoothedPeakTemp = peak
        }
        let smoothedPeak = smoothedPeakTemp!

        let pct = fanSpeedPercent(forTemperature: smoothedPeak)
        performanceCurvePercent = pct * 100

        // Below threshold — let macOS auto-manage
        if pct <= 0 {
            // If we previously set manual, return to auto
            for fan in fans where manualOverrides[fan.id] == true {
                helper.setFanMode(fanIndex: fan.id, isAuto: true) { _, _ in }
                manualOverrides[fan.id] = nil
                targetOverrides[fan.id] = nil
            }
            lastSentRPM.removeAll()
            return
        }

        // Set each fan to the calculated RPM with gradual ramping
        for fan in fans {
            let desiredRPM = fan.minRPM + pct * (fan.maxRPM - fan.minRPM)

            // Apply rate limiting: ramp up faster than ramp down
            var rampedRPM = desiredRPM
            if let lastRPM = lastSentRPM[fan.id] {
                let delta = desiredRPM - lastRPM
                if delta > 0 {
                    // Ramping up — allow up to maxRampUpPerCycle per poll
                    rampedRPM = min(desiredRPM, lastRPM + maxRampUpPerCycle)
                } else {
                    // Ramping down — limit decrease for smooth wind-down
                    rampedRPM = max(desiredRPM, lastRPM - maxRampDownPerCycle)
                }
            }

            let rounded = (rampedRPM / 100).rounded() * 100  // snap to 100 RPM increments

            // Only send commands if target changed meaningfully (avoid XPC spam)
            let currentTarget = targetOverrides[fan.id] ?? 0
            guard abs(rounded - currentTarget) >= 100 else { continue }

            // Track target immediately so next poll doesn't re-send the same value
            lastSentRPM[fan.id] = rounded
            targetOverrides[fan.id] = rounded
            manualOverrides[fan.id] = true
            helper.setFanSpeed(fanIndex: fan.id, rpm: Int(rounded)) { _, _ in }
        }
    }

    /// Clamp RPM to a sane range — guards against bad float/fpe2 decoding
    private func clampRPM(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 20000)
    }
}
