import Foundation
import IOKit.ps

final class BatteryInfo: ObservableObject {
    @Published var currentCharge: Int = 0        // 0-100
    @Published var maxCapacity: Int = 0          // mAh
    @Published var designCapacity: Int = 0       // mAh
    @Published var cycleCount: Int = 0
    @Published var healthPercent: Int = 100
    @Published var temperature: Double = 0       // Celsius
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var timeRemaining: String = "..."
    @Published var condition: String = "Normal"

    private var timer: Timer?

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, firstSource)?.takeUnretainedValue() as? [String: Any]
        else { return }

        DispatchQueue.main.async {
            self.currentCharge = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            self.isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            self.isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            if let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0, !self.isCharging {
                let hours = timeToEmpty / 60
                let mins = timeToEmpty % 60
                self.timeRemaining = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
            } else if let timeToCharge = info[kIOPSTimeToFullChargeKey] as? Int, timeToCharge > 0 {
                let hours = timeToCharge / 60
                let mins = timeToCharge % 60
                self.timeRemaining = hours > 0 ? "\(hours)h \(mins)m to full" : "\(mins)m to full"
            } else if self.currentCharge >= 100 {
                self.timeRemaining = "Fully Charged"
            } else {
                self.timeRemaining = "Calculating..."
            }
        }

        // Get detailed battery info from IORegistry
        fetchIORegistryBatteryInfo()
    }

    private func fetchIORegistryBatteryInfo() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let maxCap = getIntProperty(service, "AppleRawMaxCapacity")
            ?? getIntProperty(service, "MaxCapacity") ?? 0
        let designCap = getIntProperty(service, "DesignCapacity") ?? maxCap
        let cycles = getIntProperty(service, "CycleCount") ?? 0
        let tempRaw = getIntProperty(service, "Temperature") ?? 0
        let temp = Double(tempRaw) / 100.0  // centi-degrees to degrees

        let health: Int
        if designCap > 0 {
            health = min(100, Int(Double(maxCap) / Double(designCap) * 100))
        } else {
            health = 100
        }

        let cond: String
        if health >= 80 {
            cond = "Normal"
        } else if health >= 60 {
            cond = "Service Recommended"
        } else {
            cond = "Service Battery"
        }

        DispatchQueue.main.async {
            self.maxCapacity = maxCap
            self.designCapacity = designCap
            self.cycleCount = cycles
            self.temperature = temp
            self.healthPercent = health
            self.condition = cond
        }
    }

    private func getIntProperty(_ service: io_object_t, _ key: String) -> Int? {
        guard let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return ref.takeRetainedValue() as? Int
    }
}
