import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateController: UpdateController
    let systemInfo: SystemInfo
    @ObservedObject var fanMonitor: FanMonitor
    let cpuInfo: CpuInfo
    let memoryInfo: MemoryInfo
    let batteryInfo: BatteryInfo
    var onShowWelcome: (() -> Void)?
    @Environment(\.theme) private var theme
    let onDismiss: () -> Void

    @State private var showingAdvanced = false
    @State private var showingHelperActions = false

    var body: some View {
        ZStack {
            if showingAdvanced {
                AdvancedSettingsView(settings: settings, systemInfo: systemInfo) {
                    withAnimation(.easeInOut(duration: 0.2)) { showingAdvanced = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainPage
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            updateController.refreshUpdateStatus()
        }
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Settings", onBack: onDismiss)

            ScrollView(.vertical, showsIndicators: settings.showScrollIndicators) {
                VStack(alignment: .leading, spacing: 14) {
                    helperStatusRow
                    generalSection
                    menuBarSection
                    coolingSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Helper

    private var helperIsHealthy: Bool { fanMonitor.helperState == .running }

    private var helperStatusRow: some View {
        VStack(spacing: 0) {
            helperSummary
            if showingHelperActions {
                CardDivider()
                HelperActions(monitor: fanMonitor)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground(theme)
        .animation(.easeInOut(duration: 0.2), value: showingHelperActions)
    }

    private var helperSummary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(helperIsHealthy ? theme.green : theme.orange)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(helperIsHealthy ? "Fan control is on" : "Fan control is off")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(helperCaption)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textQuaternary)
            }
            Spacer()
            Button(showingHelperActions ? "Done" : "Manage") { showingHelperActions.toggle() }
                .buttonStyle(LinkButtonStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.teal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var helperCaption: String {
        switch fanMonitor.helperState {
        case .checking: return "Checking the helper…"
        case .running: return "Helper installed and responding"
        case .needsApproval: return "Waiting for approval in System Settings"
        case .needsInstall: return "Helper not installed"
        case .needsUpdate: return "Helper needs an update"
        case .unresponsive: return "Helper installed but not responding"
        }
    }

    // MARK: - General

    private var generalSection: some View {
        SettingsSection(title: "General") {
            SwitchRow(
                title: "Open at login",
                isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }),
                tint: theme.teal
            )
            CardDivider()
            SettingsRow(title: "Appearance") {
                Picker("", selection: Binding(
                    get: { settings.appearanceMode },
                    set: { settings.setAppearanceMode($0) }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            CardDivider()
            SettingsRow(title: "Temperature units") {
                TemperatureUnitPicker(useFahrenheit: $settings.useFahrenheit)
            }
        }
    }

    // MARK: - Menu Bar

    private var menuBarSection: some View {
        SettingsSection(title: "Menu bar") {
            SettingsRow(title: "Show temperature", caption: Text(settings.menuBarTemperature.explanation)) {
                MenuBarTemperaturePicker(selection: $settings.menuBarTemperature, compact: true)
            }
        }
    }

    // MARK: - Cooling Behavior

    private var coolingSection: some View {
        SettingsSection(title: "Cooling behavior") {
            VStack(alignment: .leading, spacing: 4) {
                SwitchRow(
                    title: "Save battery",
                    caption: Text("Let macOS run the fans when battery drops below ")
                        + Text("\(settings.batterySaverThreshold)%").fontWeight(.semibold).foregroundColor(theme.yellow),
                    isOn: $settings.batterySaverEnabled,
                    tint: theme.yellow
                )
                if settings.batterySaverEnabled {
                    Slider(
                        value: Binding(
                            get: { Double(settings.batterySaverThreshold) },
                            set: { settings.batterySaverThreshold = Int($0) }
                        ),
                        in: 5...50,
                        step: 5
                    )
                    .tint(theme.yellow)
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: settings.batterySaverEnabled)
            CardDivider()
            SwitchRow(
                title: "Keep cooling while display sleeps",
                caption: Text("Otherwise fans reset to automatic"),
                isOn: $settings.keepFansOnScreenSleep,
                tint: theme.teal
            )
            CardDivider()
            SwitchRow(
                title: "Keep cooling with lid closed",
                caption: Text("When plugged in and using an external display"),
                isOn: $settings.keepFansClosedOnPower,
                tint: theme.teal
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsRow(title: "ChillMac \(updateController.currentVersion)", caption: updateCaption) {
                if updateController.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    // Both hand off to Sparkle, which downloads, verifies the signature, swaps
                    // the bundle and relaunches.
                    Button(updateController.updateAvailable ? "Update" : "Check for updates") {
                        updateController.checkForUpdates()
                    }
                    .buttonStyle(LinkButtonStyle())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.teal)
                    .disabled(!updateController.canCheckForUpdates)
                }
            }
            CardDivider()
            if let onShowWelcome {
                LinkRow(title: "Show welcome again", action: onShowWelcome)
                CardDivider()
            }
            LinkRow(title: "Advanced") {
                withAnimation(.easeInOut(duration: 0.2)) { showingAdvanced = true }
            }
        }
    }

    private var updateCaption: Text? {
        if updateController.updateAvailable, let version = updateController.latestVersion {
            return Text("v\(version) available").foregroundColor(theme.teal)
        }
        if updateController.hasChecked {
            return Text("You’re up to date").foregroundColor(theme.green)
        }
        return nil
    }
}

// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @ObservedObject var settings: AppSettings
    let systemInfo: SystemInfo
    let onBack: () -> Void
    @Environment(\.theme) private var theme

    private var heightIsCustom: Bool {
        abs(settings.popoverHeight - Double(AppSettings.popoverDefaultHeight)) > 10
            || abs(settings.detailPanelHeight - Double(AppSettings.detailPanelDefaultHeight)) > 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Advanced", onBack: onBack)

            ScrollView(.vertical, showsIndicators: settings.showScrollIndicators) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSection(title: "Display") {
                        SwitchRow(title: "Show scrollbars", isOn: $settings.showScrollIndicators, tint: theme.teal)
                        CardDivider()
                        SwitchRow(title: "Show FPS counter", isOn: $settings.showFPS, tint: theme.teal)
                        CardDivider()
                        SettingsRow(title: "Window height", caption: Text("Drag the handle at the bottom to resize")) {
                            if heightIsCustom {
                                Button("Reset") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        settings.popoverHeight = Double(AppSettings.popoverDefaultHeight)
                                        settings.detailPanelHeight = Double(AppSettings.detailPanelDefaultHeight)
                                    }
                                    NotificationCenter.default.post(name: .detailPanelHeightReset, object: nil)
                                }
                                .buttonStyle(LinkButtonStyle())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(theme.teal)
                            }
                        }
                    }

                    SettingsSection(title: "Battery") {
                        // The popover's battery saver banner sets this through "Override".
                        // It stays reachable here so an override can be undone.
                        SwitchRow(
                            title: "Keep Smart cooling on low battery",
                            caption: Text("Ignore Save battery while Smart cooling is on"),
                            isOn: $settings.forcePerformanceOnBattery,
                            tint: theme.orange
                        )
                    }

                    SettingsSection(title: "Diagnostics") {
                        SettingsRow(title: "Export diagnostics", caption: Text("Save a system metrics log for troubleshooting")) {
                            Button("Export") {
                                DiagnosticExporter.export(logger: DiagnosticLogger.shared, systemInfo: systemInfo)
                            }
                            .buttonStyle(LinkButtonStyle())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.teal)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Helper actions

/// Reinstall, open Login Items, or remove the privileged helper. Expands under the status row.
private struct HelperActions: View {
    @ObservedObject var monitor: FanMonitor
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The helper is the small background process that sets fan speeds. Removing it hands the fans back to macOS; monitoring keeps working.")
                .font(.system(size: 11))
                .foregroundColor(theme.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Group {
                actionRow("Reinstall", icon: "arrow.clockwise") { monitor.installHelper() }
                CardDivider(leadingInset: 14)
                actionRow("Open Login Items", icon: "gearshape") { HelperInstaller.openLoginItemsSettings() }
                CardDivider(leadingInset: 14)
                actionRow("Remove", icon: "trash", color: theme.red) { monitor.removeHelper() }
                    .disabled(monitor.helperState == .needsInstall)
            }
            .disabled(monitor.helperBusy)
        }
    }

    private func actionRow(_ title: String, icon: String, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if monitor.helperBusy {
                    ProgressView().controlSize(.mini)
                }
            }
            .foregroundColor(color ?? theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

// MARK: - Building blocks

/// Back chevron and a 22pt title.
struct SettingsHeader: View {
    let title: String
    let onBack: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(HoverIconButtonStyle(diameter: 30, tint: theme.teal, hoverTint: theme.teal))
            .help("Back")
            .padding(.leading, -6)
            .keyboardShortcut(.cancelAction)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

/// Section header above one card of rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: title)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(theme)
        }
    }
}

/// A full-width row that navigates or performs an action, with a trailing chevron.
private struct LinkRow: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textQuaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// °C | °F. Shared with onboarding.
struct TemperatureUnitPicker: View {
    @Binding var useFahrenheit: Bool

    var body: some View {
        Picker("", selection: $useFahrenheit) {
            Text("°C").tag(false)
            Text("°F").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }
}

/// Never | When warm | Always. Shared with onboarding.
struct MenuBarTemperaturePicker: View {
    @Binding var selection: MenuBarTemperatureMode
    /// A pop-up button for the trailing edge of a Settings row, where three segments
    /// squeeze the row's title onto two lines. Onboarding has the width for segments.
    var compact = false

    var body: some View {
        let picker = Picker("", selection: $selection) {
            ForEach(MenuBarTemperatureMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .labelsHidden()

        if compact {
            picker.pickerStyle(.menu).controlSize(.small).fixedSize()
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}
