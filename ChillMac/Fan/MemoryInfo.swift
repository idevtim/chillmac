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

    /// When true, fetches top processes (expensive). Set by StatusBarController when Memory detail panel is visible.
    var isDetailVisible = false

    let totalMemory = ProcessInfo.processInfo.physicalMemory

    private var timer: Timer?
    private let hostPort = mach_host_self()

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    struct ProcessMemory: Identifiable {
        let id = UUID()
        let name: String
        let memoryBytes: UInt64
        let icon: NSImage?
    }

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        // Snapshot running apps on main thread only when detail panel needs top processes
        let appSnapshots: [(pid: pid_t, name: String)]?
        if isDetailVisible {
            appSnapshots = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app -> (pid: pid_t, name: String)? in
                    let name = app.localizedName ?? (app.bundleURL?.deletingPathExtension().lastPathComponent ?? "Unknown")
                    return (app.processIdentifier, name)
                }
        } else {
            appSnapshots = nil
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let stats = self.fetchVMStats()
            let swap = self.fetchSwap()
            let procs: [ProcessMemory]
            if let appSnapshots {
                procs = self.fetchTopProcesses(appSnapshots: appSnapshots)
            } else {
                procs = []
            }

            DispatchQueue.main.async {
                self.activeMemory = stats.active
                self.wiredMemory = stats.wired
                self.compressedMemory = stats.compressed
                self.availableMemory = self.totalMemory - stats.active - stats.wired - stats.compressed
                self.pressurePercent = Double(stats.active + stats.wired + stats.compressed) / Double(self.totalMemory) * 100
                self.swapUsed = swap
                if !procs.isEmpty || self.isDetailVisible {
                    self.topProcesses = procs
                }
            }
        }
    }

    // MARK: - System Calls

    private func fetchVMStats() -> (active: UInt64, wired: UInt64, compressed: UInt64) {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(self.hostPort, HOST_VM_INFO64, $0, &count)
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

    private func fetchTopProcesses(appSnapshots: [(pid: pid_t, name: String)], limit: Int = 5) -> [ProcessMemory] {
        var results: [(name: String, memoryBytes: UInt64)] = []

        for app in appSnapshots {
            var info = rusage_info_v0()
            let ret = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { ptr in
                    proc_pid_rusage(app.pid, RUSAGE_INFO_V0, ptr)
                }
            }
            guard ret == 0 else { continue }
            let memBytes = UInt64(info.ri_phys_footprint)
            guard memBytes > 0 else { continue }

            results.append((name: app.name, memoryBytes: memBytes))
        }

        let top = results
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(limit)

        // Fetch icons only for the top results (back on main thread would be ideal,
        // but NSWorkspace.shared.icon(forFile:) is thread-safe for bundle paths)
        return top.map { item in
            let icon = NSWorkspace.shared.runningApplications
                .first { $0.localizedName == item.name }?.icon
            return ProcessMemory(name: item.name, memoryBytes: item.memoryBytes, icon: icon)
        }
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
