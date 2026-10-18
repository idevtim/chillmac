import Cocoa
import SwiftUI

/// Owns the first-run window. Shown on first launch and from Settings › About.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let fanMonitor: FanMonitor
    /// Opens the popover once the window has closed.
    private let openPopover: () -> Void

    init(fanMonitor: FanMonitor, openPopover: @escaping () -> Void) {
        self.fanMonitor = fanMonitor
        self.openPopover = openPopover
    }

    var isShown: Bool { window?.isVisible ?? false }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = ThemedView(content: OnboardingView(
            monitor: fanMonitor,
            settings: AppSettings.shared,
            onFinish: { [weak self] openPopover in self?.finish(openPopover: openPopover) }
        ))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = AppSettings.shared.nsAppearance
        window.contentView = NSHostingView(rootView: root)
        window.title = "Welcome to ChillMac"
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(openPopover: Bool) {
        window?.close()
        if openPopover {
            // After the close, so the popover is not dismissed by the window losing key.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.openPopover()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early counts as done too: someone who dismissed the welcome does not want
        // it again on every launch. Settings › About brings it back.
        AppSettings.shared.hasCompletedOnboarding = true
        window?.delegate = nil
        window = nil
    }
}
