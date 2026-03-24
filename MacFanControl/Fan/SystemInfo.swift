import Cocoa
import Combine

final class SystemInfo: ObservableObject {
    @Published var machineModel: String = "..."
    @Published var chipName: String = "..."
    @Published var ramAmount: String
    @Published var macOSVersion: String
    @Published var diskUsage: String = "..."
    @Published var uptime: String = "..."

    // Disk detail data (raw bytes)
    @Published var diskTotalBytes: Int64 = 0
    @Published var diskAvailableBytes: Int64 = 0
    @Published var diskCategories: [DiskCategory] = []

    struct DiskCategory: Identifiable {
        let id = UUID()
        let name: String
        let bytes: Int64
        let color: NSColor
    }

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
        guard timer == nil else { return }
        refreshDynamic()
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
        // Disk usage — use volumeAvailableCapacityForImportantUsage to include purgeable space
        let fileURL = URL(fileURLWithPath: "/")
        if let values = try? fileURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
           let totalBytes = values.volumeTotalCapacity.map({ Int64($0) }),
           let availableBytes = values.volumeAvailableCapacityForImportantUsage {
            let freeTB = Double(availableBytes) / 1_000_000_000_000
            let formatted: String
            if freeTB >= 1.0 {
                formatted = String(format: "%.2f TB", freeTB)
            } else {
                let freeGB = Double(availableBytes) / 1_000_000_000
                formatted = String(format: "%.0f GB", freeGB)
            }
            DispatchQueue.main.async {
                self.diskUsage = formatted
                self.diskTotalBytes = totalBytes
                self.diskAvailableBytes = availableBytes
            }
            // Gather category breakdown on background thread
            self.fetchDiskCategories(totalBytes: totalBytes, availableBytes: availableBytes)
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

    private func fetchDiskCategories(totalBytes: Int64, availableBytes: Int64) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser

            func directorySize(_ url: URL) -> Int64 {
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
                var total: Int64 = 0
                for case let fileURL as URL in enumerator {
                    guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                          values.isRegularFile == true,
                          let size = values.totalFileAllocatedSize else { continue }
                    total += Int64(size)
                }
                return total
            }

            let appsSize = directorySize(URL(fileURLWithPath: "/Applications"))
            let downloadsSize = directorySize(home.appendingPathComponent("Downloads"))
            let documentsSize = directorySize(home.appendingPathComponent("Documents"))
            let desktopSize = directorySize(home.appendingPathComponent("Desktop"))

            let usedBytes = totalBytes - availableBytes
            let categorized = appsSize + downloadsSize + documentsSize + desktopSize
            let otherSize = max(0, usedBytes - categorized)

            let categories: [DiskCategory] = [
                DiskCategory(name: "Applications", bytes: appsSize, color: .systemRed),
                DiskCategory(name: "Downloads", bytes: downloadsSize, color: .systemPink),
                DiskCategory(name: "Documents", bytes: documentsSize, color: .systemBlue),
                DiskCategory(name: "Desktop", bytes: desktopSize, color: .systemGreen),
                DiskCategory(name: "Other", bytes: otherSize, color: .systemGray),
            ]

            DispatchQueue.main.async {
                self?.diskCategories = categories
            }
        }
    }

    static func formatDiskBytes(_ bytes: Int64) -> String {
        let absBytes = Double(abs(bytes))
        if absBytes >= 1_000_000_000_000 {
            return String(format: "%.2f TB", absBytes / 1_000_000_000_000)
        } else if absBytes >= 1_000_000_000 {
            return String(format: "%.1f GB", absBytes / 1_000_000_000)
        } else {
            return String(format: "%.0f MB", absBytes / 1_000_000)
        }
    }
}
