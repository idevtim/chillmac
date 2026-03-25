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

    private var smc: SMCConnection?
    private var timer: Timer?
    private var discoveredSensors: [String: TemperatureSensor] = [:]
    /// After initial discovery, only poll keys that have been found at least once
    private var activeSensorKeys: Set<String>?
    private var discoveryPollCount: Int = 0
    /// Track whether performance mode was active last poll so we can reset fans on toggle-off
    private var wasPerformanceModeActive = false

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

    // MARK: - System Event Observers

    /// Call once after helper is ready. Listens for sleep/wake/lid-close to reset fans.
    func setupSystemObservers() {
        let ws = NSWorkspace.shared.notificationCenter

        ws.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleScreenSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleScreenWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
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
        NSLog("FanMonitor: screen sleep (lid closed) — resetting fans to auto")
        resetAllFansToAuto()
    }

    @objc private func handleScreenWake() {
        NSLog("FanMonitor: screen woke (lid opened)")
        // Performance curve will reapply on next poll cycle automatically
    }

    /// Reset all fans that we've set to manual back to auto mode
    func resetAllFansToAuto() {
        guard let helper = helper else { return }
        for fan in fans {
            helper.setFanMode(fanIndex: fan.id, isAuto: true) { _, _ in }
        }
        DispatchQueue.main.async {
            self.manualOverrides.removeAll()
            self.targetOverrides.removeAll()
            self.performanceCurvePercent = 0
        }
        smoothedPeakTemp = nil
        lastSentRPM.removeAll()
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
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        smc?.close()
        smc = nil
    }

    private func poll() {
        guard let smc = smc else { return }

        // Read fans
        do {
            let fanCount = try smc.readFanCount()
            var updatedFans: [FanInfo] = []

            for i in 0..<fanCount {
                let current = clampRPM((try? smc.readFanSpeed(index: i)) ?? 0)
                var minRPM = clampRPM((try? smc.readFanMinSpeed(index: i)) ?? 0)
                var maxRPM = clampRPM((try? smc.readFanMaxSpeed(index: i)) ?? 6500)
                let target = clampRPM((try? smc.readFanTargetSpeed(index: i)) ?? 0)
                let isManual = (try? smc.readFanMode(index: i)) ?? false

                // Sanity check: if min/max are nonsensical, use reasonable defaults
                // M-series MacBook Pro fans can exceed 12,000 RPM
                if minRPM < 100 { minRPM = 1000 }
                if maxRPM < 1000 || maxRPM <= minRPM { maxRPM = 15000 }

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
                self.fans = updatedFans
            }
        } catch {
            DispatchQueue.main.async {
                self.smcError = error.localizedDescription
            }
        }

        // Read temperature sensors — after 5 full discovery passes, only poll active keys
        discoveryPollCount += 1
        let keysToProbe: [(key: String, label: String)]
        if let activeKeys = activeSensorKeys {
            keysToProbe = SMCKey.temperatureKeys.filter { activeKeys.contains($0.key) }
        } else {
            keysToProbe = SMCKey.temperatureKeys
        }

        for (key, label) in keysToProbe {
            if let temp = try? smc.readTemperature(key: key), temp > 0, temp < 150 {
                discoveredSensors[key] = TemperatureSensor(id: key, label: label, temperature: temp)
            }
        }

        // After 5 discovery passes, lock to only discovered keys
        if activeSensorKeys == nil && discoveryPollCount >= 5 && !discoveredSensors.isEmpty {
            activeSensorKeys = Set(discoveredSensors.keys)
        }

        let stableSensors = SMCKey.temperatureKeys.compactMap { key, _ in
            discoveredSensors[key]
        }
        let peak = stableSensors.map(\.temperature).max() ?? 0

        DispatchQueue.main.async {
            self.sensors = stableSensors
            self.peakTemperature = peak
        }

        // Performance mode: apply aggressive fan curve based on peak temperature
        applyPerformanceCurve(peak: peak)
    }

    // MARK: - Performance Mode Fan Curve

    /// Maps peak sensor temperature to fan speed % based on the selected performance level.
    private func fanSpeedPercent(forTemperature temp: Double) -> Double {
        let level = AppSettings.shared.performanceLevel

        // Max: always full blast
        if level == .max { return 1.0 }

        switch level {
        case .low:
            // Gentle: fans stay off longer, ramp slowly, cap at ~70%
            switch temp {
            case ...60:
                return 0
            case 60..<75:
                return 0.20 + (temp - 60) / 15.0 * 0.20   // 20%→40%
            case 75..<90:
                return 0.40 + (temp - 75) / 15.0 * 0.30   // 40%→70%
            default:
                return 0.70
            }
        case .medium:
            // Balanced: moderate thresholds, moderate speeds
            switch temp {
            case ...50:
                return 0
            case 50..<65:
                return 0.25 + (temp - 50) / 15.0 * 0.20   // 25%→45%
            case 65..<80:
                return 0.45 + (temp - 65) / 15.0 * 0.30   // 45%→75%
            case 80..<90:
                return 0.75 + (temp - 80) / 10.0 * 0.20   // 75%→95%
            default:
                return 0.95
            }
        case .high:
            // Aggressive: original curve — early ramp, high ceiling
            switch temp {
            case ...40:
                return 0
            case 40..<55:
                return 0.30 + (temp - 40) / 15.0 * 0.20   // 30%→50%
            case 55..<70:
                return 0.50 + (temp - 55) / 15.0 * 0.25   // 50%→75%
            case 70..<85:
                return 0.75 + (temp - 70) / 15.0 * 0.20   // 75%→95%
            default:
                return 1.0
            }
        case .max:
            return 1.0  // handled above, but Swift requires exhaustive switch
        }
    }

    private func applyPerformanceCurve(peak: Double) {
        // Skip fan commands while system is asleep
        guard !systemAsleep else { return }

        let performanceEnabled = AppSettings.shared.performanceMode && helperReady

        // Battery saver: suppress performance mode when on battery below threshold
        let batterySaving = performanceEnabled && checkBatterySaver()
        let isActive = performanceEnabled && !batterySaving
        DispatchQueue.main.async {
            self.batterySaverActive = batterySaving
        }

        guard let helper = helper else {
            if isActive { NSLog("FanMonitor: performance mode active but no helper reference") }
            return
        }

        // If performance mode was just turned off (or suppressed by battery saver), reset fans
        if wasPerformanceModeActive && !isActive {
            wasPerformanceModeActive = false
            for fan in fans {
                helper.setFanMode(fanIndex: fan.id, isAuto: true) { _, _ in }
            }
            DispatchQueue.main.async {
                self.manualOverrides.removeAll()
                self.targetOverrides.removeAll()
                self.performanceCurvePercent = 0
            }
            smoothedPeakTemp = nil
            lastSentRPM.removeAll()
            return
        }

        guard isActive else { return }
        wasPerformanceModeActive = true

        // Smooth the peak temperature to avoid chasing sensor noise
        if let prev = smoothedPeakTemp {
            smoothedPeakTemp = prev + tempSmoothingFactor * (peak - prev)
        } else {
            smoothedPeakTemp = peak
        }
        let smoothedPeak = smoothedPeakTemp!

        let pct = fanSpeedPercent(forTemperature: smoothedPeak)
        DispatchQueue.main.async {
            self.performanceCurvePercent = pct * 100
        }

        // Below threshold — let macOS auto-manage
        if pct <= 0 {
            // If we previously set manual, return to auto
            for fan in fans where manualOverrides[fan.id] == true {
                helper.setFanMode(fanIndex: fan.id, isAuto: true) { _, _ in }
                DispatchQueue.main.async {
                    self.manualOverrides[fan.id] = nil
                    self.targetOverrides[fan.id] = nil
                }
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

            helper.setFanSpeed(fanIndex: fan.id, rpm: Int(rounded)) { [weak self] success, _ in
                if success {
                    DispatchQueue.main.async {
                        self?.manualOverrides[fan.id] = true
                        self?.targetOverrides[fan.id] = rounded
                        self?.lastSentRPM[fan.id] = rounded
                    }
                }
            }
        }
    }

    /// Clamp RPM to a sane range — guards against bad float/fpe2 decoding
    private func clampRPM(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 20000)
    }
}
