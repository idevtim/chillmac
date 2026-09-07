import Cocoa
import Combine
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var settingsSub: AnyCancellable?
    private var menuBarTempSub: AnyCancellable?
    /// Last string pushed to the status item, so identical values never touch AppKit.
    private var lastStatusTitle = ""
    private var heightObserver: Any?
    private var detailResetObserver: Any?
    private var detailPanelObserver: Any?
    private var lastPopoverHeight: CGFloat = 0
    /// When the popover was last torn down. Guards against a single click both closing the
    /// popover and reopening it via two different handlers.
    private var lastPopoverCloseAt: Date = .distantPast

    private let detailPanel = DetailPanelController()
    private let memoryInfo: MemoryInfo
    private let systemInfo: SystemInfo
    private let batteryInfo: BatteryInfo
    private let cpuInfo: CpuInfo
    private let fanMonitor: FanMonitor
    private let fpsMonitor: DisplayFPSMonitor
    private let updateController: UpdateController
    private let helper: HelperConnection

    init(fanMonitor: FanMonitor, helper: HelperConnection, systemInfo: SystemInfo, memoryInfo: MemoryInfo, batteryInfo: BatteryInfo, cpuInfo: CpuInfo, updateController: UpdateController) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        self.memoryInfo = memoryInfo
        self.systemInfo = systemInfo
        self.batteryInfo = batteryInfo
        self.cpuInfo = cpuInfo
        self.fanMonitor = fanMonitor
        self.fpsMonitor = DisplayFPSMonitor()
        self.updateController = updateController
        self.helper = helper

        super.init()

        // Secondary monitors start when popover opens, stop when it closes.
        // The SwiftUI hosting controller is built on open and dropped on close
        // so AttributeGraph doesn't accumulate tracked state across days of uptime.

        popover.behavior = .applicationDefined
        popover.animates = false
        popover.appearance = AppSettings.shared.nsAppearance
        popover.contentSize = NSSize(width: 420, height: CGFloat(AppSettings.shared.popoverHeight))

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "ChillMac")
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.imagePosition = .imageLeading
        }

        // Peak temperature drives the menu bar label. It keeps updating while the popover is
        // closed, which is exactly when the menu bar is the only thing the user can see.
        menuBarTempSub = fanMonitor.$peakTemperature
            .receive(on: DispatchQueue.main)
            .sink { [weak self] temp in self?.updateStatusItemTitle(peak: temp) }

        // Close popover when clicking outside both the popover and detail panel
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }

            // A click on our own menu bar icon reaches this monitor as well as the button's
            // action. Closing here would leave `togglePopover` to find a hidden popover a
            // moment later and dutifully reopen it, so the icon could never close anything.
            // Leave that click entirely to the button.
            if self.statusItemContainsMouse {
                return
            }

            // Don't close if clicking inside the detail panel
            if self.detailPanel.isShown, self.detailPanel.containsMouse {
                return
            }

            self.closePopover(sender: nil)
        }

        // Update popover appearance and size when settings change
        lastPopoverHeight = CGFloat(AppSettings.shared.popoverHeight)
        settingsSub = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.popover.appearance = AppSettings.shared.nsAppearance
                self.popover.contentViewController?.view.appearance = AppSettings.shared.nsAppearance
                // Mode and °F/°C both change the label without the temperature moving.
                self.updateStatusItemTitle(peak: self.fanMonitor.peakTemperature)

                // Handle height changes from settings (e.g. Reset button), not during live drag
                let newHeight = CGFloat(AppSettings.shared.popoverHeight)
                if self.popover.isShown && abs(newHeight - self.lastPopoverHeight) >= 1 {
                    let clamped = min(max(newHeight, AppSettings.popoverMinHeight), AppSettings.popoverMaxHeight)
                    self.popover.contentSize = NSSize(width: 420, height: clamped)
                    self.lastPopoverHeight = clamped
                }
            }
        }

        // Live resize during drag — bypasses AppSettings for smooth performance
        heightObserver = NotificationCenter.default.addObserver(forName: .popoverHeightChanged, object: nil, queue: .main) { [weak self] notification in
            guard let self, let height = notification.userInfo?["height"] as? CGFloat else { return }
            self.popover.contentSize = NSSize(width: 420, height: height)
            self.lastPopoverHeight = height
        }

        // Close detail panel when height is reset from settings
        detailResetObserver = NotificationCenter.default.addObserver(forName: .detailPanelHeightReset, object: nil, queue: .main) { [weak self] _ in
            self?.detailPanel.close()
        }

        // Gate expensive polling to only run when the relevant detail panel is visible
        detailPanelObserver = NotificationCenter.default.addObserver(forName: .detailPanelChanged, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            let panelID = notification.userInfo?["panelID"] as? String
            self.cpuInfo.isDetailVisible = (panelID == "cpu")
            self.memoryInfo.isDetailVisible = (panelID == "memory")
            self.systemInfo.isDetailVisible = (panelID == "disk")
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = heightObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = detailResetObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = detailPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Renders the menu bar label for `peak`.
    ///
    /// Deliberately text-only. A status item is expected to be a template image that adapts
    /// to the wallpaper and to Dark Mode, and `contentTintColor` on `NSStatusBarButton` does
    /// not survive that reliably, so heat is conveyed by the digits appearing at all rather
    /// than by colour.
    private func updateStatusItemTitle(peak: Double) {
        guard let button = statusItem.button else { return }

        let title: String
        switch AppSettings.shared.menuBarTemperature {
        case .off:
            title = ""
        case .always:
            title = peak > 0 ? " " + AppSettings.shared.formatMenuBarTemperature(peak) : ""
        case .whenWarm:
            // Nothing until the Mac is actually warm, so the bar stays quiet at idle.
            title = (peak > 0 && ThermalStatus.forTemperature(peak) != .good)
                ? " " + AppSettings.shared.formatMenuBarTemperature(peak)
                : ""
        }

        // The status item resizes when its title changes, which nudges every icon to its
        // left. Only touch it when the rendered string actually differs.
        guard title != lastStatusTitle else { return }
        lastStatusTitle = title
        button.title = title
    }

    /// Screen rect of the menu bar icon, used to tell our own icon apart from a click
    /// genuinely outside the app.
    private var statusItemContainsMouse: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let inWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(inWindow).contains(NSEvent.mouseLocation)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else if Date().timeIntervalSince(lastPopoverCloseAt) < 0.25 {
            // Something else already closed the popover for this same click. Reopening now
            // would turn a dismissal into a flicker, which is what a click on the icon used
            // to do. One user click means one state change.
            return
        } else if let button = statusItem.button {
            // Resume secondary monitors when popover opens
            cpuInfo.startMonitoring()
            memoryInfo.startMonitoring()
            batteryInfo.startMonitoring()
            systemInfo.startMonitoring()
            fpsMonitor.startMonitoring()
            fanMonitor.isPopoverVisible = true
            // Re-check the helper on every open. If the user just approved ChillMac under
            // Login Items & Extensions, this is the only thing that notices without a relaunch.
            fanMonitor.refreshHelperState()
            AppSettings.shared.syncLaunchAtLogin()
            NotificationCenter.default.post(name: .popoverDidClose, object: nil)
            popover.contentViewController = makeHostingController()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .popoverDidShow, object: nil)
        }
    }

    /// Tears the popover down and parks every monitor it was driving. Both the toolbar
    /// button and the click-outside monitor route through here so the two paths cannot
    /// drift apart and leave a poller running with the UI gone.
    private func closePopover(sender: AnyObject?) {
        lastPopoverCloseAt = Date()
        detailPanel.close()
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
        popover.performClose(sender)
        popover.contentViewController = nil
        cpuInfo.isDetailVisible = false
        memoryInfo.isDetailVisible = false
        systemInfo.isDetailVisible = false
        cpuInfo.stopMonitoring()
        memoryInfo.stopMonitoring()
        batteryInfo.stopMonitoring()
        systemInfo.stopMonitoring()
        fpsMonitor.stopMonitoring()
        fanMonitor.isPopoverVisible = false
    }

    private func makeHostingController() -> NSHostingController<PopoverView> {
        let hosting = NSHostingController(
            rootView: PopoverView(
                monitor: fanMonitor,
                settings: AppSettings.shared,
                systemInfo: systemInfo,
                batteryInfo: batteryInfo,
                cpuInfo: cpuInfo,
                memoryInfo: memoryInfo,
                fpsMonitor: fpsMonitor,
                updateController: updateController,
                helper: helper,
                onMemoryTap: { [weak self] in self?.toggleMemoryPanel() },
                onDiskTap: { [weak self] in self?.toggleDiskPanel() },
                onBatteryTap: { [weak self] in self?.toggleBatteryPanel() },
                onCpuTap: { [weak self] in self?.toggleCpuPanel() },
                onTemperatureTap: { [weak self] in self?.toggleTemperaturePanel() }
            )
        )
        let height = CGFloat(AppSettings.shared.popoverHeight)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 420, height: height)
        hosting.view.appearance = AppSettings.shared.nsAppearance
        popover.contentSize = NSSize(width: 420, height: height)
        return hosting
    }

    private func toggleMemoryPanel() {
        detailPanel.toggle(
            id: "memory",
            content: ThemedView(content: MemoryDetailView(memoryInfo: memoryInfo)),
            relativeTo: popover
        )
    }

    private func toggleDiskPanel() {
        detailPanel.toggle(
            id: "disk",
            content: ThemedView(content: DiskDetailView(systemInfo: systemInfo, monitor: fanMonitor, settings: AppSettings.shared)),
            relativeTo: popover
        )
    }

    private func toggleBatteryPanel() {
        detailPanel.toggle(
            id: "battery",
            content: ThemedView(content: BatteryDetailView(batteryInfo: batteryInfo, settings: AppSettings.shared)),
            relativeTo: popover
        )
    }

    private func toggleCpuPanel() {
        detailPanel.toggle(
            id: "cpu",
            content: ThemedView(content: CpuDetailView(cpuInfo: cpuInfo, systemInfo: systemInfo, monitor: fanMonitor, settings: AppSettings.shared)),
            relativeTo: popover
        )
    }

    private func toggleTemperaturePanel() {
        detailPanel.toggle(
            id: "temperature",
            content: ThemedView(content: TemperatureDetailView(monitor: fanMonitor, settings: AppSettings.shared)),
            relativeTo: popover
        )
    }
}
