import Cocoa
import SwiftUI
import Combine

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?

    init(fanMonitor: FanMonitor, helper: HelperConnection, systemInfo: SystemInfo) {
        statusItem = NSStatusBar.system.statusItem(withLength: 130)
        popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = false

        let hostingController = NSHostingController(
            rootView: PopoverView(monitor: fanMonitor, settings: AppSettings.shared, systemInfo: systemInfo, helper: helper)
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 400, height: 620)
        popover.contentSize = NSSize(width: 400, height: 620)
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
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
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
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
