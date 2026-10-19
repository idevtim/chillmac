import Foundation
import IOKit.ps

final class BatteryInfo: ObservableObject {
    @Published var currentCharge: Int = 0        // 0-100
    @Published var maxCapacity: Int = 0          // mAh, 0 when not reported
    @Published var designCapacity: Int = 0       // mAh, 0 when not reported
    @Published var cycleCount: Int = 0
    @Published var healthPercent: Int = 100
    @Published var temperature: Double?          // Celsius, nil when not reported
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
    /// For the battery temperature fallback. Only touched on `healthQueue`.
    private var smc: SMCConnection?

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

    /// Called on main by the timer. IOPowerSources and the IORegistry both round-trip to
    /// other processes, so the reads themselves run off-main and only the published values
    /// come back — otherwise every poll stalls the UI for the duration of the lookup.
    private func refresh() {
        healthQueue.async { [weak self] in
            self?.refreshOffMain()
        }
    }

    private func refreshOffMain() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, firstSource)?.takeUnretainedValue() as? [String: Any]
        else { return }

        let charge = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let charging = (info[kIOPSIsChargingKey] as? Bool) ?? false
        let pluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        let remaining: String
        if let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0, !charging {
            let hours = timeToEmpty / 60
            let mins = timeToEmpty % 60
            remaining = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        } else if let timeToCharge = info[kIOPSTimeToFullChargeKey] as? Int, timeToCharge > 0 {
            let hours = timeToCharge / 60
            let mins = timeToCharge % 60
            remaining = hours > 0 ? "\(hours)h \(mins)m to full" : "\(mins)m to full"
        } else if charge >= 100 {
            remaining = "Fully Charged"
        } else {
            remaining = "Calculating..."
        }

        DispatchQueue.main.async {
            if self.currentCharge != charge { self.currentCharge = charge }
            if self.isCharging != charging { self.isCharging = charging }
            if self.isPluggedIn != pluggedIn { self.isPluggedIn = pluggedIn }
            if self.timeRemaining != remaining { self.timeRemaining = remaining }
        }

        // Get detailed battery info from IORegistry
        fetchIORegistryBatteryInfo()
        probeAppleReportedHealthIfNeeded()
    }

    /// Must be called on `healthQueue`.
    private func fetchIORegistryBatteryInfo() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        // Recent macOS (seen on 27) keeps most battery keys only inside the BatteryData
        // dictionary, and its top-level MaxCapacity is a percentage, not mAh. Reading the
        // top level alone showed "100 mAh" for both capacities, so each value is looked
        // up at the top level first, then in BatteryData.
        let batteryData = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? {
            getIntProperty(service, key) ?? batteryData[key] as? Int
        }

        // NominalChargeCapacity is the gauge's temperature/age-corrected full charge
        // capacity and is what macOS bases Maximum Capacity on. AppleRawMaxCapacity is
        // the uncorrected reading and runs several percent low, so it is only a fallback.
        // MaxCapacity is mAh on Intel but a percentage on Apple Silicon, hence the floor.
        let maxCap = value("NominalChargeCapacity")
            ?? value("AppleRawMaxCapacity")
            ?? value("FullChargeCapacity")
            ?? getIntProperty(service, "MaxCapacity").flatMap { $0 > 100 ? $0 : nil }
            ?? 0
        let designCap = value("DesignCapacity") ?? 0
        let cycles = getIntProperty(service, "CycleCount") ?? 0
        // The registry reports centi-degrees, when it reports at all; macOS 27 dropped the
        // key, so fall back to the SMC's battery sensors.
        let temp = (getIntProperty(service, "Temperature") ?? getIntProperty(service, "VirtualTemperature"))
            .map { Double($0) / 100.0 }
            ?? readSMCBatteryTemperature()

        let computedHealth: Int
        if designCap > 0 && maxCap > 0 {
            computedHealth = min(100, Int((Double(maxCap) / Double(designCap) * 100).rounded()))
        } else {
            computedHealth = 100
        }

        DispatchQueue.main.async {
            if self.maxCapacity != maxCap { self.maxCapacity = maxCap }
            if self.designCapacity != designCap { self.designCapacity = designCap }
            if self.cycleCount != cycles { self.cycleCount = cycles }
            if let temp {
                if abs((self.temperature ?? -100) - temp) >= 0.05 { self.temperature = temp }
            } else if self.temperature != nil {
                self.temperature = nil
            }
            let health = self.appleReportedHealth ?? computedHealth
            if self.healthPercent != health { self.healthPercent = health }
            let condition = Self.conditionLabel(forHealth: health)
            if self.condition != condition { self.condition = condition }
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

    /// Hottest of the SMC's battery sensors. Must be called on `healthQueue`.
    private func readSMCBatteryTemperature() -> Double? {
        if smc == nil { smc = try? SMCConnection() }
        guard let smc else { return nil }
        let readings = ["TB0T", "TB1T", "TB2T"].compactMap { try? smc.readTemperature(key: $0) }
        return readings.filter { $0 > 0 && $0 < 100 }.max()
    }

    private func getIntProperty(_ service: io_object_t, _ key: String) -> Int? {
        guard let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return ref.takeRetainedValue() as? Int
    }
}
