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
        // Only start FanMonitor at launch — it runs continuously for menu bar + performance mode.
        // Secondary monitors (CPU, Memory, Battery, System) start when the popover opens
        // and stop when it closes, managed by StatusBarController.
        fanMonitor.startMonitoring()

        DiagnosticLogger.shared.fanMonitor = fanMonitor
        DiagnosticLogger.shared.startLogging()

        statusBarController = StatusBarController(
            fanMonitor: fanMonitor,
            helper: helperConnection,
            systemInfo: systemInfo,
            memoryInfo: memoryInfo,
            batteryInfo: batteryInfo,
            cpuInfo: cpuInfo,
            updateController: updateController
        )
        // Sparkle starts its own scheduled checks when UpdateController is constructed.

        // Resolve the privileged helper in the background so the UI appears immediately.
        // `helperReady` is derived from what the daemon actually reports, so nothing here
        // needs to (or may) assert that fan control works.
        fanMonitor.helper = helperConnection
        fanMonitor.setupSystemObservers()
        fanMonitor.resolveHelperAtLaunch { [weak self] in
            // Fans always start on auto. Only worth asking once the helper can answer.
            DispatchQueue.global(qos: .utility).async { self?.resetFansToAuto() }
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
        //
        // This waits briefly for the helper to confirm. Firing the messages asynchronously
        // left them undelivered: the process was gone before XPC got to them, and the fans
        // stayed locked at their last manual speed until something else reset them.
        //
        // Skipped entirely unless the helper is known good. There is nothing to hand back
        // when it never took control, and waiting on a daemon that cannot start is how
        // quitting turned into a hang.
        if fanMonitor.helperState.canControlFans, let smc = try? SMCConnection() {
            let fanCount = (try? smc.readFanCount()) ?? 0
            smc.close()
            helperConnection.setFansToAutoAndWait(fanCount: fanCount)
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
