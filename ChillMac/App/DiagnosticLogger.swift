import AppKit
import Foundation
import IOKit.ps
import Darwin

struct FanSample: Codable {
    let name: String
    let currentRPM: Double
    let targetRPM: Double
    let isManualMode: Bool
}

struct DiagnosticSample: Codable {
    let timestamp: Date
    let cpuUsage: Double
    let gpuUsage: Double
    /// 0 = nominal, 1 = fair, 2 = serious, 3 = critical (ProcessInfo.ThermalState)
    let thermalState: Int
    /// Real memory pressure level from sysctl (1 = normal, 2 = warning, 4 = critical)
    let memoryPressureLevel: Int
    /// Percent of physical RAM actively in use (active + wired + compressed). NOT macOS "pressure".
    let memoryUsedPercent: Double
    let memoryActive: UInt64
    let memoryWired: UInt64
    let memoryCompressed: UInt64
    let swapUsed: UInt64
    let batteryCharge: Int
    let batteryIsCharging: Bool
    let batteryTemperature: Double
    let fans: [FanSample]
    let peakTemperature: Double
    let peakTemperatureLabel: String
    let peakCpuTemperature: Double
    let peakGpuTemperature: Double
    let peakSsdTemperature: Double
    let performanceCurvePercent: Double
}

struct SleepInterval: Codable {
    let start: Date
    let end: Date
}

/// Wire format for on-disk persistence (history + sleep intervals).
private struct PersistedHistory: Codable {
    let samples: [DiagnosticSample]
    let sleepIntervals: [SleepInterval]
}

final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    private let queue = DispatchQueue(label: "com.idevtim.ChillMac.diagnostics")
    private var buffer: [DiagnosticSample?]
    private var writeIndex = 0
    private let capacity = 1440 // 24h at 1 sample/min
    private var timer: Timer?

    // Sleep interval tracking
    private var sleepIntervals: [SleepInterval] = []
    private let maxSleepIntervals = 200
    private var sleepStartedAt: Date?

    // CPU delta tracking — accessed only on `queue` to avoid races
    private var previousCpuInfo: host_cpu_load_info?
    private let hostPort = mach_host_self()

    // Persistence
    private let persistencePath: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ChillMac", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()
    private let persistInterval = 15 // flush every N samples (~15 min)
    private var samplesSinceFlush = 0

    weak var fanMonitor: FanMonitor?

    private init() {
        buffer = [DiagnosticSample?](repeating: nil, count: capacity)
        loadFromDisk()
    }

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    func startLogging() {
        guard timer == nil else { return }
        queue.async { self.previousCpuInfo = self.fetchCpuLoadInfo() }
        takeSample()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.takeSample()
        }
        installSleepObservers()
    }

    func stopLogging() {
        timer?.invalidate()
        timer = nil
        removeSleepObservers()
        flushToDisk()
    }

    /// Returns all collected samples in chronological order.
    func snapshot() -> [DiagnosticSample] {
        queue.sync {
            let tail = buffer[writeIndex..<capacity]
            let head = buffer[0..<writeIndex]
            return (tail + head).compactMap { $0 }
        }
    }

    /// Returns recorded sleep intervals.
    func sleepIntervalsSnapshot() -> [SleepInterval] {
        queue.sync { sleepIntervals }
    }

    // MARK: - Sleep/Wake Tracking

    private func installSleepObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func removeSleepObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleWillSleep() {
        queue.async { self.sleepStartedAt = Date() }
    }

    @objc private func handleDidWake() {
        queue.async {
            defer { self.sleepStartedAt = nil }
            let end = Date()
            let start = self.sleepStartedAt ?? end
            // Only record real sleeps (>30s) to filter out noise
            guard end.timeIntervalSince(start) >= 30 else { return }
            self.sleepIntervals.append(SleepInterval(start: start, end: end))
            if self.sleepIntervals.count > self.maxSleepIntervals {
                self.sleepIntervals.removeFirst(self.sleepIntervals.count - self.maxSleepIntervals)
            }
            // Re-anchor CPU delta after sleep — ticks accumulated across sleep are meaningless
            self.previousCpuInfo = self.fetchCpuLoadInfo()
        }
    }

    // MARK: - Sampling

    private func takeSample() {
        // Snapshot fan-monitor values on main (cheap) — they're @Published so must be read here.
        let fans = fanMonitor?.fans.map {
            FanSample(name: $0.name, currentRPM: $0.currentRPM, targetRPM: $0.targetRPM, isManualMode: $0.isManualMode)
        } ?? []
        let peak = fanMonitor?.peakTemperature ?? 0
        let peakLabel = fanMonitor?.peakTemperatureLabel ?? ""
        let peakCpu = fanMonitor?.peakCpuTemperature ?? 0
        let peakGpu = fanMonitor?.peakGpuTemperature ?? 0
        let peakSsd = fanMonitor?.peakSsdTemperature ?? 0
        let perfCurve = fanMonitor?.performanceCurvePercent ?? 0
        let timestamp = Date()
        let totalMem = ProcessInfo.processInfo.physicalMemory
        let thermal = readThermalState()

        // Move IOKit/sysctl reads off main thread — they stall the UI over 24/7 operation.
        queue.async {
            let mem = self.readMemoryStats()
            let usedPct = Double(mem.active + mem.wired + mem.compressed) / Double(totalMem) * 100
            let pressureLevel = self.readMemoryPressureLevel()
            let batt = self.readBatteryState()
            let gpu = self.readGpuUsage()
            let cpuUsage = self.computeCpuUsage()

            let sample = DiagnosticSample(
                timestamp: timestamp,
                cpuUsage: cpuUsage,
                gpuUsage: gpu,
                thermalState: thermal,
                memoryPressureLevel: pressureLevel,
                memoryUsedPercent: usedPct,
                memoryActive: mem.active,
                memoryWired: mem.wired,
                memoryCompressed: mem.compressed,
                swapUsed: mem.swap,
                batteryCharge: batt.charge,
                batteryIsCharging: batt.isCharging,
                batteryTemperature: batt.temperature,
                fans: fans,
                peakTemperature: peak,
                peakTemperatureLabel: peakLabel,
                peakCpuTemperature: peakCpu,
                peakGpuTemperature: peakGpu,
                peakSsdTemperature: peakSsd,
                performanceCurvePercent: perfCurve
            )

            self.buffer[self.writeIndex] = sample
            self.writeIndex = (self.writeIndex + 1) % self.capacity

            self.samplesSinceFlush += 1
            if self.samplesSinceFlush >= self.persistInterval {
                self.samplesSinceFlush = 0
                self.flushToDiskLocked()
            }
        }
    }

    // MARK: - Persistence

    /// Thread-safe flush. Callable from any thread.
    func flushToDisk() {
        queue.async { self.flushToDiskLocked() }
    }

    /// Must be called on `queue`.
    private func flushToDiskLocked() {
        let samples = (buffer[writeIndex..<capacity] + buffer[0..<writeIndex]).compactMap { $0 }
        let payload = PersistedHistory(samples: samples, sleepIntervals: sleepIntervals)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        do {
            try data.write(to: persistencePath, options: .atomic)
        } catch {
            NSLog("DiagnosticLogger: persist failed — \(error)")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: persistencePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(PersistedHistory.self, from: data) else {
            NSLog("DiagnosticLogger: persisted history unreadable (schema change?), discarding")
            try? FileManager.default.removeItem(at: persistencePath)
            return
        }

        // Fill ring buffer from the end — most recent samples win if more than capacity
        let samples = payload.samples.suffix(capacity)
        for (i, s) in samples.enumerated() {
            buffer[i] = s
        }
        writeIndex = samples.count % capacity
        sleepIntervals = payload.sleepIntervals
    }

    // MARK: - Direct System Reads

    /// Must be called on `queue` (mutates previousCpuInfo).
    private func computeCpuUsage() -> Double {
        guard let current = fetchCpuLoadInfo() else { return 0 }
        guard let previous = previousCpuInfo else {
            previousCpuInfo = current
            return 0
        }
        previousCpuInfo = current

        let userDelta = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let systemDelta = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idleDelta = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let niceDelta = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else { return 0 }
        return (1 - idleDelta / total) * 100
    }

    private func fetchCpuLoadInfo() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }

    private func readMemoryStats() -> (active: UInt64, wired: UInt64, compressed: UInt64, swap: UInt64) {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(info.active_count) * pageSize
        let wired = UInt64(info.wire_count) * pageSize
        let compressed = UInt64(info.compressor_page_count) * pageSize

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        let swapUsed = swapResult == 0 ? swap.xsu_used : 0

        return (active, wired, compressed, swapUsed)
    }

    /// Real macOS memory pressure level via sysctl.
    /// Returns 1 (normal), 2 (warning), 4 (critical), or 0 on failure.
    private func readMemoryPressureLevel() -> Int {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return result == 0 ? Int(level) : 0
    }

    /// Maps ProcessInfo.ThermalState to an int (0 nominal → 3 critical).
    private func readThermalState() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    /// GPU utilization percent via IOKit's IOAccelerator PerformanceStatistics dictionary.
    /// Works on Apple Silicon; returns 0 if unavailable.
    private func readGpuUsage() -> Double {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else { return 0 }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var maxUtilization: Double = 0
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let stats = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            // Key name varies by GPU family; check the common ones.
            let candidates = ["Device Utilization %", "GPU Core Utilization", "Renderer Utilization %"]
            for key in candidates {
                if let val = stats[key] as? Int {
                    maxUtilization = max(maxUtilization, Double(val))
                } else if let val = stats[key] as? Double {
                    maxUtilization = max(maxUtilization, val)
                }
            }
        }
        return maxUtilization
    }

    private func readBatteryState() -> (charge: Int, isCharging: Bool, temperature: Double) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any] else {
            return (0, false, 0)
        }

        let charge = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false

        var temperature = 0.0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != IO_OBJECT_NULL {
            if let tempObj = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                if let tempVal = tempObj as? Int {
                    temperature = Double(tempVal) / 100.0
                }
            }
            IOObjectRelease(service)
        }

        return (charge, isCharging, temperature)
    }
}
