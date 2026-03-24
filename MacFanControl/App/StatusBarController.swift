import Cocoa
import SwiftUI
import Combine

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    private let detailPanel = DetailPanelController()
    private let memoryInfo: MemoryInfo

    init(fanMonitor: FanMonitor, helper: HelperConnection, systemInfo: SystemInfo, memoryInfo: MemoryInfo) {
        statusItem = NSStatusBar.system.statusItem(withLength: 130)
        popover = NSPopover()
        self.memoryInfo = memoryInfo

        super.init()

        popover.behavior = .transient
        popover.animates = false

        let hostingController = NSHostingController(
            rootView: PopoverView(
                monitor: fanMonitor,
                settings: AppSettings.shared,
                systemInfo: systemInfo,
                helper: helper,
                onMemoryTap: { [weak self] in
                    self?.toggleMemoryPanel()
                }
            )
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 420, height: 640)
        popover.contentSize = NSSize(width: 420, height: 640)
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "Mac Fan Control")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Update menu bar title with all fan RPMs
        cancellable = fanMonitor.$fans
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fans in
                guard !fans.isEmpty else { return }
                let rpms = fans.map { "\(Int($0.currentRPM))" }.joined(separator: " | ")
                self?.statusItem.button?.title = " \(rpms)"
            }

        // Close popover when clicking elsewhere
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.popover.isShown {
                self.detailPanel.close()
                self.popover.performClose(nil)
            }
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
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func toggleMemoryPanel() {
        detailPanel.toggle(
            content: MemoryDetailView(memoryInfo: memoryInfo),
            relativeTo: popover
        )
    }
}
