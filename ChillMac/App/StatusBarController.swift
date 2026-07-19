import Cocoa
import Combine
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var settingsSub: AnyCancellable?
    private var statusItemSubs = Set<AnyCancellable>()
    private var lastStatusItemSignature: String?

    private var settingsWindow: NSWindow?

    private let systemInfo: SystemInfo
    private let fanMonitor: FanMonitor
    private let updateChecker: UpdateChecker

    init(fanMonitor: FanMonitor, systemInfo: SystemInfo, updateChecker: UpdateChecker) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        self.systemInfo = systemInfo
        self.fanMonitor = fanMonitor
        self.updateChecker = updateChecker

        super.init()

        popover.behavior = .applicationDefined
        popover.animates = false
        popover.appearance = AppSettings.shared.nsAppearance
        popover.contentSize = NSSize(
            width: AppSettings.popoverWidth,
            height: CGFloat(AppSettings.shared.popoverHeight)
        )

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        updateStatusItem()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }

        settingsSub = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.popover.appearance = AppSettings.shared.nsAppearance
                self.popover.contentViewController?.view.appearance = AppSettings.shared.nsAppearance
                self.settingsWindow?.contentView?.appearance = AppSettings.shared.nsAppearance
                self.updateStatusItem()
            }
        }

        fanMonitor.$peakTemperature
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &statusItemSubs)
    }

    /// Template fan always; compact temp title only when setting is on and status is Warm/Hot.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let peak = fanMonitor.peakTemperature
        let thermal = ThermalStatus.from(peakCelsius: peak)
        let settings = AppSettings.shared
        let showTemp = settings.showMenuBarTemp && thermal.showsMenuBarTemperature
        let title = showTemp
            ? ThermalStatus.menuBarTemperatureText(celsius: peak, useFahrenheit: settings.useFahrenheit)
            : ""
        let signature = "\(showTemp)|\(title)|\(settings.useFahrenheit)|\(thermal.label)"
        guard signature != lastStatusItemSignature else { return }
        lastStatusItemSignature = signature

        let image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.title = title
        button.imagePosition = showTemp ? .imageLeft : .imageOnly
        button.toolTip = showTemp ? "ChillMac — \(thermal.label) \(title)" : "ChillMac"
        button.setAccessibilityLabel(showTemp ? "ChillMac, \(thermal.label), \(title)" : "ChillMac")
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover()
        } else if let button = statusItem.button {
            fanMonitor.isPopoverVisible = true
            AppSettings.shared.syncLaunchAtLogin()
            popover.contentViewController = makeHostingController()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .popoverDidShow, object: nil)
        }
    }

    private func closePopover() {
        guard popover.isShown else { return }
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
        popover.performClose(nil)
        popover.contentViewController = nil
        fanMonitor.isPopoverVisible = false
    }

    private func makeHostingController() -> NSHostingController<PopoverView> {
        let hosting = NSHostingController(
            rootView: PopoverView(
                monitor: fanMonitor,
                settings: AppSettings.shared,
                updateChecker: updateChecker,
                onOpenSettings: { [weak self] in
                    self?.closePopover()
                    self?.showSettingsWindow()
                }
            )
        )
        let height = CGFloat(AppSettings.shared.popoverHeight)
        hosting.view.frame = NSRect(x: 0, y: 0, width: AppSettings.popoverWidth, height: height)
        hosting.view.appearance = AppSettings.shared.nsAppearance
        popover.contentSize = NSSize(width: AppSettings.popoverWidth, height: height)
        return hosting
    }

    // MARK: - Settings window

    func showSettingsWindow() {
        if settingsWindow == nil {
            let root = SettingsView(
                settings: AppSettings.shared,
                updateChecker: updateChecker,
                fanMonitor: fanMonitor,
                systemInfo: systemInfo
            )
            let hosting = NSHostingController(rootView: AppearanceHost(content: root))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ChillMac Settings"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 380, height: 560))
            window.center()
            settingsWindow = window
        }

        settingsWindow?.contentView?.appearance = AppSettings.shared.nsAppearance
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
