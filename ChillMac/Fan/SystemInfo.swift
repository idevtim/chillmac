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

        if let cached = Self.loadCategoryCache() {
            diskCategories = cached.categories
            deniedFolders = cached.denied
        }

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
        // Disk usage — use volumeAvailableCapacityForImportantUsage to include purgeable space.
        // That key asks the volume how much space it could reclaim, which touches the disk and
        // can stall for hundreds of milliseconds, so it never runs on the main thread.
        diskCategoryQueue.async { [weak self] in
            guard let self else { return }
            let fileURL = URL(fileURLWithPath: "/")
            guard let values = try? fileURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ]),
                  let totalBytes = values.volumeTotalCapacity.map({ Int64($0) }),
                  let availableBytes = values.volumeAvailableCapacityForImportantUsage
            else { return }

            let freeTB = Double(availableBytes) / 1_000_000_000_000
            let formatted: String
            if freeTB >= 1.0 {
                formatted = String(format: "%.2f TB", freeTB)
            } else {
                let freeGB = Double(availableBytes) / 1_000_000_000
                formatted = String(format: "%.0f GB", freeGB)
            }
            DispatchQueue.main.async {
                // Only assign on change — every @Published write invalidates the popover's
                // view tree, and these values are usually identical poll to poll.
                if self.diskUsage != formatted { self.diskUsage = formatted }
                if self.diskTotalBytes != totalBytes { self.diskTotalBytes = totalBytes }
                if self.diskAvailableBytes != availableBytes { self.diskAvailableBytes = availableBytes }
                // Gather category breakdown on a background queue. This can be a large
                // filesystem walk, so keep it single-flight and refresh it less often than
                // the cheap disk capacity value. The bookkeeping it reads lives on main.
                if self.shouldRefreshDiskCategories(force: forceDiskCategories) {
                    self.fetchDiskCategories(totalBytes: totalBytes, availableBytes: availableBytes)
                }
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
            if self.uptime != formatted { self.uptime = formatted }
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
            // Drain the pipe *before* waiting. system_profiler blocks once it fills the
            // 64 KB pipe buffer, so waiting first would deadlock both processes forever.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

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
            let home = FileManager.default.homeDirectoryForCurrentUser
            let folders = Self.categoryFolders.map { $0.path ?? home.appendingPathComponent($0.name).path }
            let sizes = FolderSizer.sizes(of: folders)

            let usedBytes = totalBytes - availableBytes
            let categorized = sizes.reduce(Int64(0)) { $0 + ($1 ?? 0) }
            var entries = zip(Self.categoryFolders, sizes).map { folder, size in
                (name: folder.name, bytes: size ?? 0, denied: size == nil)
            }
            entries.append((name: "Other", bytes: max(0, usedBytes - categorized), denied: false))

            let categories = Self.makeCategories(entries)
            let denied = Set(entries.filter(\.denied).map(\.name))
            Self.saveCategoryCache(entries)

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

    // MARK: - Disk Categories

    /// Folders broken out in the Disk panel. Nil path means the folder of that name in home.
    private static let categoryFolders: [(name: String, path: String?)] = [
        ("Applications", "/Applications"),
        ("Downloads", nil),
        ("Documents", nil),
        ("Desktop", nil),
    ]

    private static let categoryColors: [String: NSColor] = [
        "Applications": .systemRed,
        "Downloads": .systemPink,
        "Documents": .systemBlue,
        "Desktop": .systemGreen,
        "Other": .systemGray,
    ]

    private static func makeCategories(_ entries: [(name: String, bytes: Int64, denied: Bool)]) -> [DiskCategory] {
        entries.map {
            DiskCategory(name: $0.name, bytes: $0.bytes, color: categoryColors[$0.name] ?? .systemGray, denied: $0.denied)
        }
    }

    // The last breakdown is kept across launches, so the Disk panel opens with figures from
    // the previous measurement while a fresh one runs, instead of a spinner for several
    // seconds on every first open.

    private static let categoryCacheKey = "diskCategoryCache"

    private static func saveCategoryCache(_ entries: [(name: String, bytes: Int64, denied: Bool)]) {
        let plist = entries.map { ["name": $0.name, "bytes": $0.bytes, "denied": $0.denied] as [String: Any] }
        UserDefaults.standard.set(plist, forKey: categoryCacheKey)
    }

    private static func loadCategoryCache() -> (categories: [DiskCategory], denied: Set<String>)? {
        guard let plist = UserDefaults.standard.array(forKey: categoryCacheKey) as? [[String: Any]] else { return nil }
        let entries = plist.compactMap { item -> (name: String, bytes: Int64, denied: Bool)? in
            guard let name = item["name"] as? String, let bytes = (item["bytes"] as? NSNumber)?.int64Value else { return nil }
            return (name, bytes, item["denied"] as? Bool ?? false)
        }
        guard !entries.isEmpty else { return nil }
        return (makeCategories(entries), Set(entries.filter(\.denied).map(\.name)))
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
