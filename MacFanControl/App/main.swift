import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let fanMonitor = FanMonitor()
    let systemInfo = SystemInfo()
    let memoryInfo = MemoryInfo()
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

        fanMonitor.startMonitoring()
        systemInfo.startMonitoring()
        memoryInfo.startMonitoring()
        statusBarController = StatusBarController(
            fanMonitor: fanMonitor,
            helper: helperConnection,
            systemInfo: systemInfo,
            memoryInfo: memoryInfo
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reset any manually controlled fans back to auto
        for (fanIndex, isManual) in fanMonitor.manualOverrides where isManual {
            helperConnection.setFanMode(fanIndex: fanIndex, isAuto: true) { _, _ in }
        }

        fanMonitor.stopMonitoring()
        systemInfo.stopMonitoring()
        memoryInfo.stopMonitoring()
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
