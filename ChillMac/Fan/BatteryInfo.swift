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

    /// Maximum Capacity % exactly as macOS reports it, when we can read it.
    /// powerd filters and smooths the raw gauge reading before publishing this,
    /// so it does not match a plain capacity ratio. Nil on machines where
    /// system_profiler does not report it (Intel, desktops, no battery).
    private var appleReportedHealth: Int?
    private var lastHealthProbe: Date?
    private let healthQueue = DispatchQueue(label: "com.idevtim.ChillMac.batteryHealth", qos: .utility)

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
        probeAppleReportedHealthIfNeeded()
    }

    private func fetchIORegistryBatteryInfo() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        // NominalChargeCapacity is the gauge's temperature/age-corrected full charge
        // capacity and is what macOS bases Maximum Capacity on. AppleRawMaxCapacity is
        // the uncorrected reading and runs several percent low, so it is only a fallback.
        let maxCap = getIntProperty(service, "NominalChargeCapacity")
            ?? getIntProperty(service, "AppleRawMaxCapacity")
            ?? getIntProperty(service, "MaxCapacity") ?? 0
        let designCap = getIntProperty(service, "DesignCapacity") ?? maxCap
        let cycles = getIntProperty(service, "CycleCount") ?? 0
        let tempRaw = getIntProperty(service, "Temperature") ?? 0
        let temp = Double(tempRaw) / 100.0  // centi-degrees to degrees

        let computedHealth: Int
        if designCap > 0 {
            computedHealth = min(100, Int((Double(maxCap) / Double(designCap) * 100).rounded()))
        } else {
            computedHealth = 100
        }

        DispatchQueue.main.async {
            self.maxCapacity = maxCap
            self.designCapacity = designCap
            self.cycleCount = cycles
            self.temperature = temp
            self.healthPercent = self.appleReportedHealth ?? computedHealth
            self.condition = Self.conditionLabel(forHealth: self.healthPercent)
        }
    }

    private static func conditionLabel(forHealth health: Int) -> String {
        if health >= 80 { return "Normal" }
        if health >= 60 { return "Service Recommended" }
        return "Service Battery"
    }

    /// Maximum Capacity is only recalculated by powerd around full-charge events, so
    /// polling it more than a few times an hour is wasted work.
    private func probeAppleReportedHealthIfNeeded() {
        if let last = lastHealthProbe, Date().timeIntervalSince(last) < 900 { return }
        lastHealthProbe = Date()

        healthQueue.async { [weak self] in
            guard let health = Self.readSystemProfilerHealth() else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.appleReportedHealth = health
                self.healthPercent = health
                self.condition = Self.conditionLabel(forHealth: health)
            }
        }
    }

    /// macOS only exposes its filtered Maximum Capacity to clients holding the private
    /// `com.apple.private.iokit.batterydata` entitlement, so the value is unreachable
    /// through IOPowerSources from a third-party app. system_profiler has that
    /// entitlement, and its JSON output is the supported way to read the same number.
    private static func readSystemProfilerHealth() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["SPPowerDataType"] as? [[String: Any]]
        else { return nil }

        for entry in entries {
            guard let info = entry["sppower_battery_health_info"] as? [String: Any],
                  let raw = info["sppower_battery_health_maximum_capacity"] as? String
            else { continue }

            // Reported as "90%"
            let digits = raw.prefix { $0.isNumber }
            if let value = Int(digits) { return value }
        }
        return nil
    }

    private func getIntProperty(_ service: io_object_t, _ key: String) -> Int? {
        guard let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return ref.takeRetainedValue() as? Int
    }
}
