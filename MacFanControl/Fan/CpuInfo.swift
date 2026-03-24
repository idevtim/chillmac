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

    private var timer: Timer?
    private var previousInfo: host_cpu_load_info?
    private let maxHistory = 120

    struct CpuProcess: Identifiable {
        let id = UUID()
        let name: String
        let cpuPercent: Double
        let icon: NSImage?
    }

    func startMonitoring() {
        previousInfo = fetchCpuLoadInfo()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        // CPU ticks are fast — read on main thread
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

        // Fetch top processes on background thread (spawns ps)
        // Snapshot app icons on main thread first
        var appIcons: [pid_t: (NSImage, String)] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let icon = app.icon, let name = app.localizedName {
                appIcons[app.processIdentifier] = (icon, name)
            }
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let procs = self?.fetchTopProcesses(appIcons: appIcons) ?? []
            DispatchQueue.main.async {
                self?.topProcesses = procs
            }
        }
    }

    // MARK: - System Calls

    private func fetchCpuLoadInfo() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }

    private func fetchTopProcesses(appIcons: [pid_t: (NSImage, String)], limit: Int = 5) -> [CpuProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=", "-o", "%cpu=", "-o", "comm="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        // Build a map of app bundle paths to their info for matching subprocesses
        // e.g. "/Applications/Google Chrome.app" -> (icon, name)
        var appsByBundlePath: [(path: String, icon: NSImage, name: String, pid: pid_t)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let bundleURL = app.bundleURL, let icon = app.icon, let name = app.localizedName {
                appsByBundlePath.append((bundleURL.path, icon, name, app.processIdentifier))
            }
        }

        // Aggregate CPU % by app bundle (matching subprocess paths to parent app bundles)
        var cpuByApp: [String: (cpu: Double, icon: NSImage, name: String)] = [:]

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let tokens = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard tokens.count >= 3 else { continue }

            guard let cpu = Double(tokens[1]), cpu > 0 else { continue }
            let comm = String(tokens[2])

            // Find which app bundle this process belongs to
            for app in appsByBundlePath {
                if comm.hasPrefix(app.path) {
                    cpuByApp[app.name, default: (0, app.icon, app.name)].cpu += cpu
                    break
                }
            }
        }

        return cpuByApp.values
            .sorted { $0.cpu > $1.cpu }
            .prefix(limit)
            .map { CpuProcess(name: $0.name, cpuPercent: $0.cpu, icon: $0.icon) }
    }
}
