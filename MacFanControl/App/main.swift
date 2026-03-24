import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let fanMonitor = FanMonitor()
    let helperConnection = HelperConnection()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install privileged helper on first launch
        if !HelperInstaller.isHelperInstalled() {
            _ = HelperInstaller.installHelper()
        }

        fanMonitor.startMonitoring()
        statusBarController = StatusBarController(
            fanMonitor: fanMonitor,
            helper: helperConnection
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        fanMonitor.stopMonitoring()
        helperConnection.disconnect()
    }
}

// Manual entry point — sets AppDelegate as the NSApp delegate and runs
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
