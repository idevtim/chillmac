import AppKit
import Foundation

// MARK: - Report Types

struct DiagnosticReport: Codable {
    let exportDate: Date
    let appVersion: String
    let system: SystemSnapshot
    let settings: SettingsSnapshot
    let sleepIntervals: [SleepInterval]
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

// MARK: - Exporter

enum DiagnosticExporter {
    static func export(
        logger: DiagnosticLogger,
        systemInfo: SystemInfo
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
            sleepIntervals: logger.sleepIntervalsSnapshot(),
            history: logger.snapshot()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
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
