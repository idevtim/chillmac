import Cocoa
import Combine
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var settingsSub: AnyCancellable?
    private var heightObserver: Any?
    private var lastPopoverHeight: CGFloat = 0

    private let detailPanel = DetailPanelController()
    private let memoryInfo: MemoryInfo
    private let systemInfo: SystemInfo
    private let batteryInfo: BatteryInfo
    private let cpuInfo: CpuInfo
    private let fanMonitor: FanMonitor

    init(fanMonitor: FanMonitor, helper: HelperConnection, systemInfo: SystemInfo, memoryInfo: MemoryInfo, batteryInfo: BatteryInfo, cpuInfo: CpuInfo) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        self.memoryInfo = memoryInfo
        self.systemInfo = systemInfo
        self.batteryInfo = batteryInfo
        self.cpuInfo = cpuInfo
        self.fanMonitor = fanMonitor

        super.init()

        // Start secondary monitors paused — they'll start when popover opens
        cpuInfo.stopMonitoring()
        memoryInfo.stopMonitoring()
        batteryInfo.stopMonitoring()
        systemInfo.stopMonitoring()

        popover.behavior = .applicationDefined
        popover.animates = false
        popover.appearance = AppSettings.shared.nsAppearance

        let hostingController = NSHostingController(
            rootView: PopoverView(
                monitor: fanMonitor,
                settings: AppSettings.shared,
                systemInfo: systemInfo,
                batteryInfo: batteryInfo,
                cpuInfo: cpuInfo,
                helper: helper,
                onMemoryTap: { [weak self] in
                    self?.toggleMemoryPanel()
                },
                onDiskTap: { [weak self] in
                    self?.toggleDiskPanel()
                },
                onBatteryTap: { [weak self] in
                    self?.toggleBatteryPanel()
                },
                onCpuTap: { [weak self] in
                    self?.toggleCpuPanel()
                },
                onTemperatureTap: { [weak self] in
                    self?.toggleTemperaturePanel()
                }
            )
        )
        let initialHeight = CGFloat(AppSettings.shared.popoverHeight)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 420, height: initialHeight)
        popover.contentSize = NSSize(width: 420, height: initialHeight)
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "ChillMac")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Close popover when clicking outside both the popover and detail panel
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }

            // Don't close if clicking inside the detail panel
            if self.detailPanel.isShown, self.detailPanel.containsMouse {
                return
            }

            self.detailPanel.close()
            self.popover.performClose(nil)
            // Pause secondary monitors when popover closes
            self.cpuInfo.stopMonitoring()
            self.memoryInfo.stopMonitoring()
            self.batteryInfo.stopMonitoring()
            self.systemInfo.stopMonitoring()
        }

        // Update popover appearance and size when settings change
        lastPopoverHeight = CGFloat(AppSettings.shared.popoverHeight)
        settingsSub = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.popover.appearance = AppSettings.shared.nsAppearance

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
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = heightObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            detailPanel.close()
            popover.performClose(sender)
            // Pause secondary monitors when popover closes
            cpuInfo.stopMonitoring()
            memoryInfo.stopMonitoring()
            batteryInfo.stopMonitoring()
            systemInfo.stopMonitoring()
        } else if let button = statusItem.button {
            // Resume secondary monitors when popover opens
            cpuInfo.startMonitoring()
            memoryInfo.startMonitoring()
            batteryInfo.startMonitoring()
            systemInfo.startMonitoring()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
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
