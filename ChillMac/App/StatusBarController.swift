import Cocoa
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?

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
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 420, height: 640)
        popover.contentSize = NSSize(width: 420, height: 640)
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
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
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
            content: MemoryDetailView(memoryInfo: memoryInfo),
            relativeTo: popover
        )
    }

    private func toggleDiskPanel() {
        detailPanel.toggle(
            id: "disk",
            content: DiskDetailView(systemInfo: systemInfo, monitor: fanMonitor, settings: AppSettings.shared),
            relativeTo: popover
        )
    }

    private func toggleBatteryPanel() {
        detailPanel.toggle(
            id: "battery",
            content: BatteryDetailView(batteryInfo: batteryInfo, settings: AppSettings.shared),
            relativeTo: popover
        )
    }

    private func toggleCpuPanel() {
        detailPanel.toggle(
            id: "cpu",
            content: CpuDetailView(cpuInfo: cpuInfo, systemInfo: systemInfo, monitor: fanMonitor, settings: AppSettings.shared),
            relativeTo: popover
        )
    }

    private func toggleTemperaturePanel() {
        detailPanel.toggle(
            id: "temperature",
            content: TemperatureDetailView(monitor: fanMonitor, settings: AppSettings.shared),
            relativeTo: popover
        )
    }
}
