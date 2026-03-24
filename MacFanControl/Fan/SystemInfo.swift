import Foundation
import Combine

final class SystemInfo: ObservableObject {
    @Published var machineModel: String = "..."
    @Published var chipName: String = "..."
    @Published var ramAmount: String
    @Published var macOSVersion: String
    @Published var diskUsage: String = "..."
    @Published var uptime: String = "..."

    private var timer: Timer?

    init() {
        // RAM — available immediately
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb = Double(bytes) / 1_073_741_824
        if gb == gb.rounded() {
            ramAmount = "\(Int(gb)) GB"
        } else {
            ramAmount = String(format: "%.1f GB", gb)
        }

        // macOS version — available immediately
        let v = ProcessInfo.processInfo.operatingSystemVersion
        macOSVersion = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"

        // Machine model & chip — async via system_profiler
        fetchHardwareInfo()

        // Disk & uptime — compute now, then poll
        refreshDynamic()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshDynamic()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func refreshDynamic() {
        // Disk usage
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let totalBytes = attrs[.systemSize] as? Int64,
           let freeBytes = attrs[.systemFreeSize] as? Int64 {
            let totalGB = Double(totalBytes) / 1_000_000_000
            let usedGB = Double(totalBytes - freeBytes) / 1_000_000_000
            DispatchQueue.main.async {
                self.diskUsage = String(format: "%.0f / %.0f GB", usedGB, totalGB)
            }
        }

        // Uptime
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let formatted: String
        if days > 0 {
            formatted = "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            formatted = "\(hours)h \(minutes)m"
        } else {
            formatted = "\(minutes)m"
        }
        DispatchQueue.main.async {
            self.uptime = formatted
        }
    }

    private func fetchHardwareInfo() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPHardwareDataType", "-json"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["SPHardwareDataType"] as? [[String: Any]],
                  let hw = items.first else { return }

            let model = hw["machine_name"] as? String ?? "Unknown Mac"
            let chip = hw["chip_type"] as? String ?? hw["cpu_type"] as? String ?? "Unknown"

            DispatchQueue.main.async {
                self?.machineModel = model
                self?.chipName = chip
            }
        }
    }
}
