import AppKit
import Foundation

// MARK: - Report Types

struct DiagnosticReport: Codable {
    let exportDate: Date
    let appVersion: String
    let system: SystemSnapshot
    let settings: SettingsSnapshot
    let helper: HelperSnapshot
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

/// Fan control helper status at export time. Reports of "the helper won't install" were
/// unanswerable without it: the history only shows that the helper never replied, not why.
struct HelperSnapshot: Codable {
    let state: String
    let serviceStatus: String
    let lastInstallError: String?
    let locationProblem: String?
    let legacyHelperInstalled: Bool
    let appPath: String
    let coolingMode: String
}

// MARK: - Exporter

enum DiagnosticExporter {
    static func export(
        logger: DiagnosticLogger,
        systemInfo: SystemInfo,
        fanMonitor: FanMonitor
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
            helper: HelperSnapshot(
                state: String(describing: fanMonitor.helperState),
                serviceStatus: HelperInstaller.serviceStatusDescription,
                lastInstallError: fanMonitor.helperInstallError,
                locationProblem: HelperInstaller.locationProblem,
                legacyHelperInstalled: HelperInstaller.legacyHelperInstalled,
                appPath: (Bundle.main.bundlePath as NSString).abbreviatingWithTildeInPath,
                coolingMode: settings.coolingMode.rawValue
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
