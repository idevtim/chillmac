import AppKit
import SwiftUI

/// Builds the Cool status-item `NSMenu`. Pure tag ↔ mode mapping is unit-tested.
enum CoolStatusMenuBuilder {
    enum ItemTag: Int {
        case modeNative = 100
        case modeBalanced = 101
        case modePerformance = 102
        case settings = 200
        case quit = 201
        case installHelper = 202
        case overrideBatterySaver = 203
    }

    struct Actions {
        let target: AnyObject
        let selectMode: Selector
        let openSettings: Selector
        let quit: Selector
        let installHelper: Selector
        let overrideBatterySaver: Selector
    }

    static func intent(forTag tag: Int) -> CoolIntent? {
        switch ItemTag(rawValue: tag) {
        case .modeNative: return .native
        case .modeBalanced: return .balanced
        case .modePerformance: return .performance
        default: return nil
        }
    }

    static func tag(for intent: CoolIntent) -> Int {
        switch intent {
        case .native: return ItemTag.modeNative.rawValue
        case .balanced: return ItemTag.modeBalanced.rawValue
        case .performance: return ItemTag.modePerformance.rawValue
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

        appendHeader(menu: menu, monitor: monitor, settings: settings)
        appendZoneTrack(menu: menu, peakCelsius: monitor.peakTemperature)
        if let throttle = throttleCaption(for: monitor.processThermalState) {
            appendDisabledCaption(menu: menu, title: throttle)
        }

        menu.addItem(.separator())

        for mode in CoolIntent.allCases {
            menu.addItem(modeItem(mode, selected: settings.coolMode == mode, actions: actions))
        }

        if settings.coolMode != .native, !monitor.helperReady {
            menu.addItem(.separator())
            appendDisabledCaption(
                menu: menu,
                title: "Approve ChillMac in Login Items, then install the helper."
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

    private static func appendHeader(menu: NSMenu, monitor: FanMonitor, settings: AppSettings) {
        let thermal = ThermalStatus.from(peakCelsius: monitor.peakTemperature)
        let temp = monitor.peakTemperature > 0
            ? ThermalStatus.menuBarTemperatureText(
                celsius: monitor.peakTemperature,
                useFahrenheit: settings.useFahrenheit
            )
            : "--"
        let subline = "\(statusSubline(monitor: monitor))  ·  \(temp)"

        let title = NSMenuItem(title: "Cool", action: nil, keyEquivalent: "")
        title.isEnabled = false
        if #available(macOS 14.4, *) {
            title.title = "Cool"
            title.subtitle = subline
        } else {
            title.attributedTitle = headerAttributedTitle(
                primary: "Cool",
                secondary: subline,
                thermal: thermal
            )
        }
        menu.addItem(title)
    }

    private static func statusSubline(monitor: FanMonitor) -> String {
        var line = ThermalStatus.from(peakCelsius: monitor.peakTemperature).label
        if let suffix = ThermalStatus.severitySuffix(thermalState: monitor.processThermalState) {
            line += " · \(suffix)"
        }
        return line
    }

    private static func headerAttributedTitle(
        primary: String,
        secondary: String,
        thermal: ThermalStatus
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: primary,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let secondaryColor: NSColor = {
            switch thermal {
            case .warm: return .systemOrange
            case .hot: return .systemRed
            default: return .secondaryLabelColor
            }
        }()
        result.append(NSAttributedString(
            string: "\n\(secondary)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: secondaryColor,
            ]
        ))
        return result
    }

    private static func appendZoneTrack(menu: NSMenu, peakCelsius: Double) {
        let item = NSMenuItem()
        item.isEnabled = false
        let strip = CoolZoneTrackStrip(peakCelsius: peakCelsius)
        let host = NSHostingView(rootView: strip)
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
        selected: Bool,
        actions: Actions
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: mode.label,
            action: actions.selectMode,
            keyEquivalent: ""
        )
        item.target = actions.target
        item.tag = tag(for: mode)
        item.state = selected ? .on : .off
        item.isEnabled = true
        if mode == .native {
            if #available(macOS 14.4, *) {
                item.subtitle = mode.description
            } else {
                item.title = "\(mode.label) — \(mode.description)"
            }
        }
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
            title: "Quit ChillMac",
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

// MARK: - Zone track (only custom menu view)

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
