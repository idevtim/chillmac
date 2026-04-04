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
    let memoryPressure: Double
    let memoryActive: UInt64
    let memoryWired: UInt64
    let memoryCompressed: UInt64
    let swapUsed: UInt64
    let batteryCharge: Int
    let batteryIsCharging: Bool
    let batteryTemperature: Double
    let fans: [FanSample]
    let peakTemperature: Double
    let performanceCurvePercent: Double
}

final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    private let queue = DispatchQueue(label: "com.idevtim.ChillMac.diagnostics")
    private var buffer: [DiagnosticSample?]
    private var writeIndex = 0
    private let capacity = 1440 // 24h at 1 sample/min
    private var timer: Timer?

    // CPU delta tracking
    private var previousCpuInfo: host_cpu_load_info?
    private let hostPort = mach_host_self()

    weak var fanMonitor: FanMonitor?

    private init() {
        buffer = [DiagnosticSample?](repeating: nil, count: capacity)
    }

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    func startLogging() {
        guard timer == nil else { return }
        previousCpuInfo = fetchCpuLoadInfo()
        takeSample()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.takeSample()
        }
    }

    func stopLogging() {
        timer?.invalidate()
        timer = nil
    }

    /// Returns all collected samples in chronological order.
    func snapshot() -> [DiagnosticSample] {
        queue.sync {
            // Read from writeIndex..end then 0..writeIndex to get chronological order
            let tail = buffer[writeIndex..<capacity]
            let head = buffer[0..<writeIndex]
            return (tail + head).compactMap { $0 }
        }
    }

    // MARK: - Sampling

    private func takeSample() {
        let fans = fanMonitor?.fans.map {
            FanSample(name: $0.name, currentRPM: $0.currentRPM, targetRPM: $0.targetRPM, isManualMode: $0.isManualMode)
        } ?? []
        let peak = fanMonitor?.peakTemperature ?? 0
        let perfCurve = fanMonitor?.performanceCurvePercent ?? 0

        let cpuUsage = readCpuUsage()
        let mem = readMemoryStats()
        let totalMem = ProcessInfo.processInfo.physicalMemory
        let pressure = Double(mem.active + mem.wired + mem.compressed) / Double(totalMem) * 100
        let batt = readBatteryState()

        let sample = DiagnosticSample(
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryPressure: pressure,
            memoryActive: mem.active,
            memoryWired: mem.wired,
            memoryCompressed: mem.compressed,
            swapUsed: mem.swap,
            batteryCharge: batt.charge,
            batteryIsCharging: batt.isCharging,
            batteryTemperature: batt.temperature,
            fans: fans,
            peakTemperature: peak,
            performanceCurvePercent: perfCurve
        )

        queue.async {
            self.buffer[self.writeIndex] = sample
            self.writeIndex = (self.writeIndex + 1) % self.capacity
        }
    }

    // MARK: - Direct System Reads

    private func readCpuUsage() -> Double {
        guard let current = fetchCpuLoadInfo(), let previous = previousCpuInfo else {
            previousCpuInfo = fetchCpuLoadInfo()
            return 0
        }
        previousCpuInfo = current

        let userDelta = Double(current.cpu_ticks.0 - previous.cpu_ticks.0)
        let systemDelta = Double(current.cpu_ticks.1 - previous.cpu_ticks.1)
        let idleDelta = Double(current.cpu_ticks.2 - previous.cpu_ticks.2)
        let niceDelta = Double(current.cpu_ticks.3 - previous.cpu_ticks.3)
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

    private func readBatteryState() -> (charge: Int, isCharging: Bool, temperature: Double) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any] else {
            return (0, false, 0)
        }

        let charge = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false

        // Temperature from IORegistry
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
