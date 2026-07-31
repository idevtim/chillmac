import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let fanMonitor = FanMonitor()
    let systemInfo = SystemInfo()
    let memoryInfo = MemoryInfo()
    let batteryInfo = BatteryInfo()
    let cpuInfo = CpuInfo()
    let helperConnection = HelperConnection()
    let updateController = UpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only start FanMonitor at launch — it runs continuously for menu bar + Cool.
        // Detail-panel monitors (CPU, Memory, Battery, System) are unused from the Cool menu path.
        fanMonitor.startMonitoring()

        DiagnosticLogger.shared.fanMonitor = fanMonitor
        DiagnosticLogger.shared.startLogging()

        statusBarController = StatusBarController(
            fanMonitor: fanMonitor,
            systemInfo: systemInfo,
            updateController: updateController
        )
        // Sparkle starts its own scheduled checks when UpdateController is constructed.

        // Install/load the privileged helper in the background so the UI appears immediately
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if HelperInstaller.isRegistered() {
                let status = HelperInstaller.checkHelperStatus()
                switch status {
                case .runningCorrectVersion:
                    NSLog("AppDelegate: helper already running with correct version")
                case .runningWrongVersion:
                    NSLog("AppDelegate: helper version mismatch — unregister then register")
                    _ = HelperInstaller.reregister()
                case .notRunning:
                    NSLog("AppDelegate: helper registered but not responding — unregister then register")
                    _ = HelperInstaller.reregister()
                }
            } else {
                NSLog("AppDelegate: helper not registered — installing")
                _ = HelperInstaller.register()
            }

            HelperInstaller.openApprovalSettingsIfNeeded()

            // Brief settle after registration before probing XPC
            Thread.sleep(forTimeInterval: 0.5)
            let liveStatus = HelperInstaller.checkHelperStatus()
            let ready = HelperReadiness.isReady(liveStatus)

            if ready {
                self.resetFansToAuto()
            }

            DispatchQueue.main.async {
                self.fanMonitor.helper = self.helperConnection
                // Only advertise helper control when XPC actually answers
                self.fanMonitor.helperReady = ready
                if ready {
                    self.fanMonitor.setupSystemObservers()
                }
            }
        }
    }

    private func resetFansToAuto() {
        // Use SMC directly to read fan count, then ask helper to set each to auto
        if let smc = try? SMCConnection() {
            let fanCount = (try? smc.readFanCount()) ?? 0
            smc.close()
            for i in 0..<fanCount {
                helperConnection.setFanMode(fanIndex: i, isAuto: true) { _, _ in }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reset all fans back to auto so they aren't stuck at a fixed speed
        // while the app is closed. Performance mode preference is preserved
        // and will be re-applied on next launch.
        if let smc = try? SMCConnection() {
            let fanCount = (try? smc.readFanCount()) ?? 0
            smc.close()
            for i in 0..<fanCount {
                helperConnection.setFanMode(fanIndex: i, isAuto: true) { _, _ in }
            }
        }

        DiagnosticLogger.shared.stopLogging()
        fanMonitor.stopMonitoring()
        systemInfo.stopMonitoring()
        memoryInfo.stopMonitoring()
        batteryInfo.stopMonitoring()
        cpuInfo.stopMonitoring()
        helperConnection.disconnect()
    }
}

// Manual entry point — sets AppDelegate as the NSApp delegate and runs
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
