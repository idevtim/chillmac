import Cocoa
import SwiftUI
import Combine

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?

    init(fanMonitor: FanMonitor, helper: HelperConnection) {
        statusItem = NSStatusBar.system.statusItem(withLength: 70)
        popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = false

        let hostingController = NSHostingController(
            rootView: PopoverView(monitor: fanMonitor, helper: helper)
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "Mac Fan Control")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Update menu bar title with primary fan RPM
        cancellable = fanMonitor.$fans
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fans in
                if let fan = fans.first {
                    self?.statusItem.button?.title = " \(Int(fan.currentRPM))"
                }
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
