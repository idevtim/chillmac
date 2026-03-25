import Foundation
import Combine

final class FanMonitor: ObservableObject {
    @Published var fans: [FanInfo] = []
    @Published var sensors: [TemperatureSensor] = []
    @Published var smcError: String?
    @Published var helperReady = false

    /// The hottest sensor temperature from the last poll (used by performance mode UI)
    @Published var peakTemperature: Double = 0
    /// The target RPM % that performance mode is currently requesting (0–100)
    @Published var performanceCurvePercent: Double = 0

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

    /// Aggressive fan curve for power users. Maps peak sensor temperature to fan speed.
    ///
    /// Curve:
    ///   ≤ 40°C  →  0% (auto / idle)
    ///   40–55°C →  30%–50%  (early ramp — stay ahead of heat)
    ///   55–70°C →  50%–75%
    ///   70–85°C →  75%–95%
    ///   > 85°C  →  100% (full blast)
    private func fanSpeedPercent(forTemperature temp: Double) -> Double {
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
    }

    private func applyPerformanceCurve(peak: Double) {
        let isActive = AppSettings.shared.performanceMode && helperReady
        guard let helper = helper else {
            if isActive { NSLog("FanMonitor: performance mode active but no helper reference") }
            return
        }

        // If performance mode was just turned off, reset fans to auto
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
            return
        }

        guard isActive else { return }
        wasPerformanceModeActive = true

        let pct = fanSpeedPercent(forTemperature: peak)
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
            return
        }

        // Set each fan to the calculated RPM
        for fan in fans {
            let targetRPM = fan.minRPM + pct * (fan.maxRPM - fan.minRPM)
            let rounded = (targetRPM / 100).rounded() * 100  // snap to 100 RPM increments

            // Only send commands if target changed meaningfully (avoid XPC spam)
            let currentTarget = targetOverrides[fan.id] ?? 0
            guard abs(rounded - currentTarget) >= 100 else { continue }

            helper.setFanSpeed(fanIndex: fan.id, rpm: Int(rounded)) { [weak self] success, _ in
                if success {
                    DispatchQueue.main.async {
                        self?.manualOverrides[fan.id] = true
                        self?.targetOverrides[fan.id] = rounded
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
