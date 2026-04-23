import Foundation
import AppKit
import Darwin

final class CpuInfo: ObservableObject {
    @Published var userPercent: Double = 0
    @Published var systemPercent: Double = 0
    @Published var idlePercent: Double = 100
    @Published var totalUsage: Double = 0
    @Published var history: [Double] = []
    @Published var userHistory: [Double] = []
    @Published var systemHistory: [Double] = []
    @Published var topProcesses: [CpuProcess] = []

    /// When true, fetches top processes (expensive). Set by StatusBarController when CPU detail panel is visible.
    var isDetailVisible = false

    private var timer: Timer?
    private var previousInfo: host_cpu_load_info?
    private let maxHistory = 120
    private let hostPort = mach_host_self()
    private var pollCount: UInt = 0
    private var topProcessFetchInFlight = false

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    struct CpuProcess: Identifiable {
        let id = UUID()
        let name: String
        let cpuPercent: Double
        let icon: NSImage?
    }

    func startMonitoring() {
        guard timer == nil else { return }
        previousInfo = fetchCpuLoadInfo()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        guard let current = fetchCpuLoadInfo(), let previous = previousInfo else {
            previousInfo = fetchCpuLoadInfo()
            return
        }

        let userDiff = Double(current.cpu_ticks.0 - previous.cpu_ticks.0)
        let sysDiff = Double(current.cpu_ticks.1 - previous.cpu_ticks.1)
        let idleDiff = Double(current.cpu_ticks.2 - previous.cpu_ticks.2)
        let niceDiff = Double(current.cpu_ticks.3 - previous.cpu_ticks.3)
        let totalDiff = userDiff + sysDiff + idleDiff + niceDiff

        previousInfo = current

        if totalDiff > 0 {
            userPercent = (userDiff + niceDiff) / totalDiff * 100
            systemPercent = sysDiff / totalDiff * 100
            idlePercent = idleDiff / totalDiff * 100
            totalUsage = 100 - idlePercent
        }

        history.append(totalUsage)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }

        userHistory.append(userPercent)
        if userHistory.count > maxHistory {
            userHistory.removeFirst(userHistory.count - maxHistory)
        }

        systemHistory.append(systemPercent)
        if systemHistory.count > maxHistory {
            systemHistory.removeFirst(systemHistory.count - maxHistory)
        }

        // Fetch top processes every 5th poll, only when detail panel is visible.
        pollCount += 1
        guard isDetailVisible, pollCount % 5 == 0, !topProcessFetchInFlight else { return }
        topProcessFetchInFlight = true

        // Snapshot app metadata on main thread. NSWorkspace/AppKit stays on main; sorting stays off-main.
        var appBundles: [(path: String, name: String, icon: NSImage?)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let bundleURL = app.bundleURL, let name = app.localizedName {
                appBundles.append((bundleURL.path, name, app.icon))
            }
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let procs = self?.fetchTopProcesses(appBundles: appBundles) ?? []
            DispatchQueue.main.async {
                self?.topProcesses = procs
                self?.topProcessFetchInFlight = false
            }
        }
    }

    // MARK: - System Calls

    private func fetchCpuLoadInfo() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(self.hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }

    private func fetchTopProcesses(appBundles: [(path: String, name: String, icon: NSImage?)], limit: Int = 5) -> [CpuProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=", "-o", "%cpu=", "-o", "comm="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var cpuByApp: [String: (cpu: Double, name: String, icon: NSImage?)] = [:]

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let tokens = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard tokens.count >= 3 else { continue }

            guard let cpu = Double(tokens[1]), cpu > 0 else { continue }
            let comm = String(tokens[2])

            for app in appBundles {
                if comm.hasPrefix(app.path) {
                    cpuByApp[app.name, default: (0, app.name, app.icon)].cpu += cpu
                    break
                }
            }
        }

        // Sort and take top results, then fetch icons only for those
        let top = cpuByApp.values
            .sorted { $0.cpu > $1.cpu }
            .prefix(limit)

        return top.map { item in
            CpuProcess(name: item.name, cpuPercent: item.cpu, icon: item.icon)
        }
    }
}
