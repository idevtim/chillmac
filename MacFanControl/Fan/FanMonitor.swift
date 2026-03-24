import Foundation
import Combine

final class FanMonitor: ObservableObject {
    @Published var fans: [FanInfo] = []
    @Published var sensors: [TemperatureSensor] = []
    @Published var smcError: String?

    /// User overrides that persist across poll cycles
    @Published var manualOverrides: [Int: Bool] = [:]   // fanIndex → manual on/off
    @Published var targetOverrides: [Int: Double] = [:]  // fanIndex → target RPM

    private var smc: SMCConnection?
    private var timer: Timer?
    private var discoveredSensors: [String: TemperatureSensor] = [:]

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

        // Read temperature sensors — keep previously discovered sensors stable
        for (key, label) in SMCKey.temperatureKeys {
            if let temp = try? smc.readTemperature(key: key), temp > 0, temp < 150 {
                discoveredSensors[key] = TemperatureSensor(id: key, label: label, temperature: temp)
            }
            // If key was discovered before but fails now, keep the last known value
        }
        let stableSensors = SMCKey.temperatureKeys.compactMap { key, _ in
            discoveredSensors[key]
        }
        DispatchQueue.main.async {
            self.sensors = stableSensors
        }
    }

    /// Clamp RPM to a sane range — guards against bad float/fpe2 decoding
    private func clampRPM(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 20000)
    }
}
