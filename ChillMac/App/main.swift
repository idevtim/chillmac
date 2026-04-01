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
    let updateChecker = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        fanMonitor.startMonitoring()
        systemInfo.startMonitoring()
        memoryInfo.startMonitoring()
        batteryInfo.startMonitoring()
        cpuInfo.startMonitoring()
        statusBarController = StatusBarController(
            fanMonitor: fanMonitor,
            helper: helperConnection,
            systemInfo: systemInfo,
            memoryInfo: memoryInfo,
            batteryInfo: batteryInfo,
            cpuInfo: cpuInfo,
            updateChecker: updateChecker
        )
        updateChecker.startPeriodicChecks()

        // Install/load the privileged helper in the background so the UI appears immediately
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if HelperInstaller.isRegistered() {
                // Daemon is registered — check if it's the right version
                let status = HelperInstaller.checkHelperStatus()
                switch status {
                case .runningCorrectVersion:
                    NSLog("AppDelegate: helper already running with correct version")
                case .runningWrongVersion:
                    NSLog("AppDelegate: helper version mismatch — re-registering")
                    HelperInstaller.unregister()
                    _ = HelperInstaller.register()
                case .notRunning:
                    // Registered but not responding — likely just needs a moment after launch
                    NSLog("AppDelegate: helper registered but not responding")
                }
            } else {
                // Not registered at all — first install, prompt is expected
                NSLog("AppDelegate: helper not registered — installing")
                _ = HelperInstaller.register()
            }

            // Reset all fans to auto on startup
            self.resetFansToAuto()

            DispatchQueue.main.async {
                self.fanMonitor.helper = self.helperConnection
                self.fanMonitor.helperReady = true
                self.fanMonitor.setupSystemObservers()
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
