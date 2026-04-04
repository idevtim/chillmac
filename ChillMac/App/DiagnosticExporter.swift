import AppKit
import Foundation

// MARK: - Report Types

struct DiagnosticReport: Codable {
    let exportDate: Date
    let appVersion: String
    let system: SystemSnapshot
    let settings: SettingsSnapshot
    let currentState: CurrentStateSnapshot
    let history: [DiagnosticSample]
}

struct SystemSnapshot: Codable {
    let machineModel: String
    let chipName: String
    let ramAmount: String
    let macOSVersion: String
    let uptime: String
    let diskUsage: String
}

struct SettingsSnapshot: Codable {
    let performanceMode: Bool
    let performanceLevel: String
    let batterySaverEnabled: Bool
    let batterySaverThreshold: Int
    let useFahrenheit: Bool
    let keepFansOnScreenSleep: Bool
}

struct SensorSample: Codable {
    let label: String
    let id: String
    let temperature: Double
}

struct CpuSnapshot: Codable {
    let totalUsage: Double
    let userPercent: Double
    let systemPercent: Double
}

struct MemorySnapshot: Codable {
    let activeMemory: UInt64
    let wiredMemory: UInt64
    let compressedMemory: UInt64
    let availableMemory: UInt64
    let pressurePercent: Double
    let swapUsed: UInt64
}

struct BatterySnapshot: Codable {
    let currentCharge: Int
    let healthPercent: Int
    let cycleCount: Int
    let temperature: Double
    let isCharging: Bool
    let isPluggedIn: Bool
}

struct CurrentStateSnapshot: Codable {
    let fans: [FanSample]
    let sensors: [SensorSample]
    let cpu: CpuSnapshot
    let memory: MemorySnapshot
    let battery: BatterySnapshot
}

// MARK: - Exporter

enum DiagnosticExporter {
    static func export(
        logger: DiagnosticLogger,
        systemInfo: SystemInfo,
        fanMonitor: FanMonitor,
        cpuInfo: CpuInfo,
        memoryInfo: MemoryInfo,
        batteryInfo: BatteryInfo
    ) {
        let settings = AppSettings.shared

        let report = DiagnosticReport(
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            system: SystemSnapshot(
                machineModel: systemInfo.machineModel,
                chipName: systemInfo.chipName,
                ramAmount: systemInfo.ramAmount,
                macOSVersion: systemInfo.macOSVersion,
                uptime: systemInfo.uptime,
                diskUsage: systemInfo.diskUsage
            ),
            settings: SettingsSnapshot(
                performanceMode: settings.performanceMode,
                performanceLevel: settings.performanceLevel.rawValue,
                batterySaverEnabled: settings.batterySaverEnabled,
                batterySaverThreshold: settings.batterySaverThreshold,
                useFahrenheit: settings.useFahrenheit,
                keepFansOnScreenSleep: settings.keepFansOnScreenSleep
            ),
            currentState: CurrentStateSnapshot(
                fans: fanMonitor.fans.map {
                    FanSample(name: $0.name, currentRPM: $0.currentRPM, targetRPM: $0.targetRPM, isManualMode: $0.isManualMode)
                },
                sensors: fanMonitor.sensors.map {
                    SensorSample(label: $0.label, id: $0.id, temperature: $0.temperature)
                },
                cpu: CpuSnapshot(
                    totalUsage: cpuInfo.totalUsage,
                    userPercent: cpuInfo.userPercent,
                    systemPercent: cpuInfo.systemPercent
                ),
                memory: MemorySnapshot(
                    activeMemory: memoryInfo.activeMemory,
                    wiredMemory: memoryInfo.wiredMemory,
                    compressedMemory: memoryInfo.compressedMemory,
                    availableMemory: memoryInfo.availableMemory,
                    pressurePercent: memoryInfo.pressurePercent,
                    swapUsed: memoryInfo.swapUsed
                ),
                battery: BatterySnapshot(
                    currentCharge: batteryInfo.currentCharge,
                    healthPercent: batteryInfo.healthPercent,
                    cycleCount: batteryInfo.cycleCount,
                    temperature: batteryInfo.temperature,
                    isCharging: batteryInfo.isCharging,
                    isPluggedIn: batteryInfo.isPluggedIn
                )
            ),
            history: logger.snapshot()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(report) else {
            NSLog("DiagnosticExporter: failed to encode report")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ChillMac-Diagnostics-\(dateStr).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
            NSLog("DiagnosticExporter: saved report to \(url.path)")
        } catch {
            NSLog("DiagnosticExporter: failed to write report — \(error)")
        }
    }
}
