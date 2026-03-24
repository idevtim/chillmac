import Foundation
import AppKit
import Darwin

final class MemoryInfo: ObservableObject {
    @Published var activeMemory: UInt64 = 0
    @Published var wiredMemory: UInt64 = 0
    @Published var compressedMemory: UInt64 = 0
    @Published var availableMemory: UInt64 = 0
    @Published var pressurePercent: Double = 0
    @Published var swapUsed: UInt64 = 0
    @Published var topProcesses: [ProcessMemory] = []

    let totalMemory = ProcessInfo.processInfo.physicalMemory

    private var timer: Timer?

    struct ProcessMemory: Identifiable {
        let id = UUID()
        let name: String
        let memoryBytes: UInt64
        let icon: NSImage?
    }

    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let stats = self.fetchVMStats()
            let swap = self.fetchSwap()
            let procs = self.fetchTopProcesses()

            DispatchQueue.main.async {
                self.activeMemory = stats.active
                self.wiredMemory = stats.wired
                self.compressedMemory = stats.compressed
                self.availableMemory = self.totalMemory - stats.active - stats.wired - stats.compressed
                self.pressurePercent = Double(stats.active + stats.wired + stats.compressed) / Double(self.totalMemory) * 100
                self.swapUsed = swap
                self.topProcesses = procs
            }
        }
    }

    // MARK: - System Calls

    private func fetchVMStats() -> (active: UInt64, wired: UInt64, compressed: UInt64) {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, 0, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        return (
            active: UInt64(info.active_count) * pageSize,
            wired: UInt64(info.wire_count) * pageSize,
            compressed: UInt64(info.compressor_page_count) * pageSize
        )
    }

    private func fetchSwap() -> UInt64 {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        guard result == 0 else { return 0 }
        return swap.xsu_used
    }

    private func fetchTopProcesses(limit: Int = 5) -> [ProcessMemory] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=,comm=,rss=", "-r"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        // Build a map of running app PIDs to their bundle icons
        var appIconsByPid: [pid_t: NSImage] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let icon = app.icon {
                appIconsByPid[app.processIdentifier] = icon
            }
        }

        var results: [ProcessMemory] = []
        var seenNames: Set<String> = []

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Format: "  PID /path/to/comm   RSS"
            guard let lastSpace = trimmed.lastIndex(of: " ") else { continue }
            let rssStr = String(trimmed[trimmed.index(after: lastSpace)...]).trimmingCharacters(in: .whitespaces)
            guard let kb = UInt64(rssStr), kb > 0 else { continue }

            let remaining = trimmed[trimmed.startIndex..<lastSpace].trimmingCharacters(in: .whitespaces)
            guard let firstSpace = remaining.firstIndex(of: " ") else { continue }
            let pidStr = String(remaining[remaining.startIndex..<firstSpace]).trimmingCharacters(in: .whitespaces)
            let commPath = String(remaining[remaining.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)

            let shortName = (commPath as NSString).lastPathComponent

            // Skip duplicates and system processes
            guard !seenNames.contains(shortName) else { continue }
            seenNames.insert(shortName)

            let pid = pid_t(pidStr) ?? 0
            let icon = appIconsByPid[pid]

            results.append(ProcessMemory(name: shortName, memoryBytes: kb * 1024, icon: icon))

            if results.count >= limit { break }
        }

        return results.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    // MARK: - Formatting

    static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
