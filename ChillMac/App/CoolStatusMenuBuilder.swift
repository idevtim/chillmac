import AppKit
import SwiftUI

/// Builds the Cool status-item `NSMenu`. Pure tag ↔ mode mapping is unit-tested.
enum CoolStatusMenuBuilder {
    enum ItemTag: Int {
        case modeNative = 100
        case modeMax = 101
        case modeUltra = 102
        case settings = 200
        case quit = 201
        case installHelper = 202
        case overrideBatterySaver = 203
    }

    struct Actions {
        let onSelectMode: (CoolIntent) -> Void
        let target: AnyObject
        let openSettings: Selector
        let quit: Selector
        let installHelper: Selector
        let overrideBatterySaver: Selector
    }

    static func intent(forTag tag: Int) -> CoolIntent? {
        switch ItemTag(rawValue: tag) {
        case .modeNative: return .native
        case .modeMax: return .max
        case .modeUltra: return .ultra
        default: return nil
        }
    }

    static func tag(for intent: CoolIntent) -> Int {
        switch intent {
        case .native: return ItemTag.modeNative.rawValue
        case .max: return ItemTag.modeMax.rawValue
        case .ultra: return ItemTag.modeUltra.rawValue
        }
    }

    static func rebuild(
        menu: NSMenu,
        monitor: FanMonitor,
        settings: AppSettings,
        updateAvailable: Bool,
        actions: Actions
    ) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        if let error = monitor.smcError {
            appendSMCError(menu: menu, error: error)
            appendFooter(menu: menu, updateAvailable: updateAvailable, actions: actions)
            return
        }

        // Color scale first — no Cool/status/temp header above it.
        appendZoneTrack(menu: menu, peakCelsius: monitor.peakTemperature)
        if let throttle = throttleCaption(for: monitor.processThermalState) {
            appendDisabledCaption(menu: menu, title: throttle)
        }

        menu.addItem(.separator())

        if #available(macOS 14.0, *) {
            menu.addItem(.sectionHeader(title: "Mode"))
        } else {
            appendDisabledCaption(menu: menu, title: "Mode")
        }

        for mode in CoolIntent.allCases {
            menu.addItem(modeItem(mode, actions: actions))
        }

        if settings.coolMode != .native, !monitor.helperReady {
            menu.addItem(.separator())
            appendDisabledCaption(
                menu: menu,
                title: "Approve \(AppBrand.displayName) in Login Items, then install the helper."
            )
            let install = NSMenuItem(
                title: "Install Helper",
                action: actions.installHelper,
                keyEquivalent: ""
            )
            install.target = actions.target
            install.tag = ItemTag.installHelper.rawValue
            install.isEnabled = true
            menu.addItem(install)
        }

        if monitor.batterySaverActive, settings.coolMode != .native {
            menu.addItem(.separator())
            appendDisabledCaption(menu: menu, title: "Battery saver — fans on Auto")
            let override = NSMenuItem(
                title: "Override Battery Saver",
                action: actions.overrideBatterySaver,
                keyEquivalent: ""
            )
            override.target = actions.target
            override.tag = ItemTag.overrideBatterySaver.rawValue
            override.isEnabled = true
            menu.addItem(override)
        }

        menu.addItem(.separator())
        appendFooter(menu: menu, updateAvailable: updateAvailable, actions: actions)
    }

    // MARK: - Sections

    private static func appendZoneTrack(menu: NSMenu, peakCelsius: Double) {
        let item = NSMenuItem()
        item.isEnabled = false
        let strip = CoolZoneTrackStrip(peakCelsius: peakCelsius)
        let host = MenuFirstClickHostingView(rootView: strip)
        host.frame = NSRect(x: 0, y: 0, width: 260, height: 34)
        item.view = host
        menu.addItem(item)
    }

    private static func throttleCaption(for state: ProcessInfo.ThermalState) -> String? {
        switch state {
        case .fair: return "Throttle: Fair"
        case .serious: return "Throttle: Serious"
        case .critical: return "Throttle: Critical"
        default: return nil
        }
    }

    private static func appendDisabledCaption(menu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private static func modeItem(
        _ mode: CoolIntent,
        actions: Actions
    ) -> NSMenuItem {
        let item = NSMenuItem(title: mode.label, action: nil, keyEquivalent: "")
        item.tag = tag(for: mode)
        item.isEnabled = true
        item.state = .off

        let row = CoolModeRowView(mode: mode) {
            actions.onSelectMode(mode)
        }
        let host = MenuFirstClickHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: 260, height: 36)
        item.view = host
        return item
    }

    private static func appendSMCError(menu: NSMenu, error: String) {
        let title = NSMenuItem(title: "SMC Error", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        appendDisabledCaption(menu: menu, title: error)
        menu.addItem(.separator())
    }

    private static func appendFooter(
        menu: NSMenu,
        updateAvailable: Bool,
        actions: Actions
    ) {
        let settingsTitle = updateAvailable ? "Settings… ●" : "Settings…"
        let settings = NSMenuItem(
            title: settingsTitle,
            action: actions.openSettings,
            keyEquivalent: ","
        )
        settings.target = actions.target
        settings.tag = ItemTag.settings.rawValue
        settings.isEnabled = true
        if updateAvailable {
            settings.attributedTitle = settingsAttributedTitle()
        }
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit \(AppBrand.displayName)",
            action: actions.quit,
            keyEquivalent: "q"
        )
        quit.target = actions.target
        quit.tag = ItemTag.quit.rawValue
        quit.isEnabled = true
        menu.addItem(quit)
    }

    private static func settingsAttributedTitle() -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "Settings…",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        result.append(NSAttributedString(string: "  "))
        let dot = NSAttributedString(string: "●", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.controlAccentColor,
        ])
        result.append(dot)
        return result
    }
}

// MARK: - Custom menu views

/// Hosting view that accepts the first click into the menu (no focus steal / second-click).
private final class MenuFirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CoolModeRowView: View {
    let mode: CoolIntent
    let onSelect: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    private var selected: Bool { settings.coolMode == mode }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                    .frame(width: 22, height: 22)
                if let symbol = mode.modeSystemImage {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                } else {
                    Circle()
                        .strokeBorder(
                            selected ? Color.white.opacity(0.9) : Color.secondary.opacity(0.55),
                            lineWidth: 1.5
                        )
                        .frame(width: 10, height: 10)
                }
            }

            Text(mode.label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            if mode == .native {
                Text(mode.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 260, height: 36, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Zone track

private struct CoolZoneTrackStrip: View {
    let peakCelsius: Double

    var body: some View {
        let status = ThermalStatus.from(peakCelsius: peakCelsius)
        let position = ThermalStatus.zoneTrackPosition(peakCelsius: peakCelsius)

        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .green, .orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 6)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(status.color, lineWidth: 1.5))
                        .offset(x: max(0, min(geo.size.width, geo.size.width * position) - 5))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)

            HStack {
                Text("Good")
                Spacer()
                Text("Warm")
                Spacer()
                Text("Hot")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .frame(width: 260, height: 34)
    }
}
