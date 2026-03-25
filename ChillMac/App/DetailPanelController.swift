import Cocoa
import SwiftUI

final class DetailPanelController {
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var currentPanelID: String?

    var isShown: Bool { panel?.isVisible ?? false }

    var containsMouse: Bool {
        guard let panel else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    func toggle<Content: View>(id: String = "", content: Content, relativeTo mainPopover: NSPopover) {
        if isShown {
            let wasShowingSamePanel = currentPanelID == id
            close()
            if wasShowingSamePanel { return }
        }

        currentPanelID = id

        // Get the main popover window frame to position adjacent
        guard let mainWindow = mainPopover.contentViewController?.view.window else { return }
        let mainFrame = mainWindow.frame

        let panelWidth: CGFloat = 370
        let panelHeight = CGFloat(AppSettings.shared.detailPanelHeight)

        // Position to the left of the main popover, top-aligned with content (below the arrow)
        let arrowHeight: CGFloat = 13
        let panelX = mainFrame.minX - panelWidth - 6
        let panelY = mainFrame.maxY - panelHeight - arrowHeight

        let panel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        panel.orderFront(nil)
        self.panel = panel

        // Close when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            // Check if click is outside both the panel and the main popover
            if !panel.frame.contains(NSEvent.mouseLocation) &&
               !mainFrame.contains(NSEvent.mouseLocation) {
                self.close()
            }
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
