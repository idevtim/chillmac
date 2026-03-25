import SwiftUI

extension Notification.Name {
    static let popoverHeightChanged = Notification.Name("ChillMac.popoverHeightChanged")
    static let detailPanelHeightReset = Notification.Name("ChillMac.detailPanelHeightReset")
}

/// Drag handle for resizing detail panels. Finds and resizes the hosting NSPanel directly for smooth performance.
struct PanelResizeHandle: View {
    @Binding var panelHeight: CGFloat
    var minHeight: CGFloat = AppSettings.detailPanelMinHeight
    var maxHeight: CGFloat = AppSettings.detailPanelMaxHeight
    var onCommit: (() -> Void)? = nil

    @State private var hostWindow: NSWindow?
    @State private var dragStartHeight: CGFloat = 0
    @Environment(\.theme) private var theme

    var body: some View {
        Capsule()
            .fill(theme.textQuaternary.opacity(0.5))
            .frame(width: 36, height: 4)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartHeight == 0 {
                            dragStartHeight = panelHeight
                            if hostWindow == nil {
                                hostWindow = NSApp.windows.first {
                                    $0.isVisible && $0 is NSPanel && $0.frame.contains(NSEvent.mouseLocation)
                                }
                            }
                        }
                        let delta = value.location.y - value.startLocation.y
                        let newHeight = min(max(dragStartHeight + delta, minHeight), maxHeight)
                        panelHeight = newHeight

                        if let window = hostWindow {
                            var frame = window.frame
                            let heightDelta = newHeight - frame.height
                            frame.size.height = newHeight
                            frame.origin.y -= heightDelta
                            window.setFrame(frame, display: true, animate: false)
                        }
                    }
                    .onEnded { _ in
                        onCommit?()
                        dragStartHeight = 0
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
    }
}
