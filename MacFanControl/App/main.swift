import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let fanMonitor = FanMonitor()
    let systemInfo = SystemInfo()
    let memoryInfo = MemoryInfo()
    let batteryInfo = BatteryInfo()
    let helperConnection = HelperConnection()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install or re-load the privileged helper
        if !HelperInstaller.isHelperInstalled() {
            _ = HelperInstaller.installHelper()
        }
        // Ensure the daemon is loaded (may have been unloaded on last quit)
        if !HelperInstaller.isHelperInstalled() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["bootstrap", "system", "/Library/LaunchDaemons/com.timothymurphy.MacFanControl.Helper.plist"]
            try? process.run()
            process.waitUntilExit()
        }

        // Reset all fans to auto on startup in case a previous session left them in manual mode
        resetFansToAuto()

        fanMonitor.startMonitoring()
        systemInfo.startMonitoring()
        memoryInfo.startMonitoring()
        batteryInfo.startMonitoring()
        statusBarController = StatusBarController(
            fanMonitor: fanMonitor,
            helper: helperConnection,
            systemInfo: systemInfo,
            memoryInfo: memoryInfo,
            batteryInfo: batteryInfo
        )
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
        // Reset any manually controlled fans back to auto
        for (fanIndex, isManual) in fanMonitor.manualOverrides where isManual {
            helperConnection.setFanMode(fanIndex: fanIndex, isAuto: true) { _, _ in }
        }

        fanMonitor.stopMonitoring()
        systemInfo.stopMonitoring()
        memoryInfo.stopMonitoring()
        batteryInfo.stopMonitoring()
        helperConnection.disconnect()

        // Unload the helper daemon so it's not running when the app isn't
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "system/com.timothymurphy.MacFanControl.Helper"]
        try? process.run()
        process.waitUntilExit()
    }
}

// Manual entry point — sets AppDelegate as the NSApp delegate and runs
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
