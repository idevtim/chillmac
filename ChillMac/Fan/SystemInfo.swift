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
    @Published var deniedFolders: Set<String> = []

    struct DiskCategory: Identifiable {
        let id = UUID()
        let name: String
        let bytes: Int64
        let color: NSColor
        var denied: Bool = false
    }

    /// When true, fetches disk category breakdown (expensive filesystem walk). Set by StatusBarController when Disk detail panel is visible.
    var isDetailVisible = false {
        didSet {
            if isDetailVisible && !oldValue {
                refreshDynamic(forceDiskCategories: true)
            }
        }
    }

    private var timer: Timer?
    private let diskCategoryQueue = DispatchQueue(label: "com.idevtim.ChillMac.diskCategories", qos: .utility)
    private var diskCategoryRefreshInFlight = false
    private var lastDiskCategoryRefreshAt: Date?
    private let diskCategoryRefreshInterval: TimeInterval = 5 * 60

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

    private func refreshDynamic(forceDiskCategories: Bool = false) {
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
            // Gather category breakdown on background thread. This can be a large filesystem walk,
            // so keep it single-flight and refresh it less often than the cheap disk capacity value.
            if self.shouldRefreshDiskCategories(force: forceDiskCategories) {
                self.fetchDiskCategories(totalBytes: totalBytes, availableBytes: availableBytes)
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

    private func shouldRefreshDiskCategories(force: Bool) -> Bool {
        guard isDetailVisible, !diskCategoryRefreshInFlight else { return false }
        guard !force, let lastDiskCategoryRefreshAt else { return true }
        return Date().timeIntervalSince(lastDiskCategoryRefreshAt) >= diskCategoryRefreshInterval
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
        diskCategoryRefreshInFlight = true
        diskCategoryQueue.async { [weak self] in
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser

            /// Returns (size, denied). A folder is "denied" when we cannot enumerate it at all.
            func directorySize(_ url: URL) -> (Int64, Bool) {
                guard fm.isReadableFile(atPath: url.path),
                      let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
                    return (0, true)
                }
                var total: Int64 = 0
                for case let fileURL as URL in enumerator {
                    autoreleasepool {
                        guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                              values.isRegularFile == true,
                              let size = values.totalFileAllocatedSize else { return }
                        total += Int64(size)
                    }
                }
                return (total, false)
            }

            let (appsSize, appsDenied) = directorySize(URL(fileURLWithPath: "/Applications"))
            let (downloadsSize, downloadsDenied) = directorySize(home.appendingPathComponent("Downloads"))
            let (documentsSize, documentsDenied) = directorySize(home.appendingPathComponent("Documents"))
            let (desktopSize, desktopDenied) = directorySize(home.appendingPathComponent("Desktop"))

            let usedBytes = totalBytes - availableBytes
            let categorized = appsSize + downloadsSize + documentsSize + desktopSize
            let otherSize = max(0, usedBytes - categorized)

            var denied = Set<String>()
            if appsDenied { denied.insert("Applications") }
            if downloadsDenied { denied.insert("Downloads") }
            if documentsDenied { denied.insert("Documents") }
            if desktopDenied { denied.insert("Desktop") }

            let categories: [DiskCategory] = [
                DiskCategory(name: "Applications", bytes: appsSize, color: .systemRed, denied: appsDenied),
                DiskCategory(name: "Downloads", bytes: downloadsSize, color: .systemPink, denied: downloadsDenied),
                DiskCategory(name: "Documents", bytes: documentsSize, color: .systemBlue, denied: documentsDenied),
                DiskCategory(name: "Desktop", bytes: desktopSize, color: .systemGreen, denied: desktopDenied),
                DiskCategory(name: "Other", bytes: otherSize, color: .systemGray),
            ]

            DispatchQueue.main.async {
                guard let self else { return }
                self.diskCategoryRefreshInFlight = false
                self.lastDiskCategoryRefreshAt = Date()
                guard self.isDetailVisible else { return }
                self.diskCategories = categories
                self.deniedFolders = denied
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
