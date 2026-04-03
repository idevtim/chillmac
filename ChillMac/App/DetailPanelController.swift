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
            if wasShowingSamePanel {
                close()
                return
            }
            closeImmediately()
        }

        currentPanelID = id
        postPanelChanged()

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

        // Wrap content with a close button overlay, inside ThemedView for correct theme
        let wrappedContent = ThemedView(content:
            ZStack(alignment: .topTrailing) {
                content
                DetailPanelCloseButton { [weak self] in
                    self?.close()
                }
                .padding(.top, 16)
                .padding(.trailing, 14)
            }
        )

        let hostingView = NSHostingView(rootView: wrappedContent)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        // Start offset to the right and transparent, then animate to final position
        let slideOffset: CGFloat = 20
        panel.setFrame(
            NSRect(x: panelX + slideOffset, y: panelY, width: panelWidth, height: panelHeight),
            display: false
        )
        panel.alphaValue = 0
        panel.orderFront(nil)
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
                display: true
            )
            panel.animator().alphaValue = 1
        }

        // Close when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak mainWindow] _ in
            guard let self, let panel = self.panel else { return }
            // Check if click is outside both the panel and the main popover
            let currentMainFrame = mainWindow?.frame ?? .zero
            if !panel.frame.contains(NSEvent.mouseLocation) &&
               !currentMainFrame.contains(NSEvent.mouseLocation) {
                self.close()
            }
        }
    }

    /// Animated close — slides out to the right and fades
    func close() {
        guard let panel else {
            cleanupEventMonitor()
            return
        }

        currentPanelID = nil
        postPanelChanged()
        cleanupEventMonitor()
        self.panel = nil

        let finalFrame = panel.frame.offsetBy(dx: 20, dy: 0)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// Immediate close without animation — used when switching between panels
    private func closeImmediately() {
        panel?.orderOut(nil)
        panel = nil
        currentPanelID = nil
        cleanupEventMonitor()
    }

    private func postPanelChanged() {
        NotificationCenter.default.post(
            name: .detailPanelChanged,
            object: nil,
            userInfo: ["panelID": currentPanelID as Any]
        )
    }

    private func cleanupEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Close Button

struct DetailPanelCloseButton: View {
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(theme.textQuaternary)
        }
        .buttonStyle(.plain)
    }
}
