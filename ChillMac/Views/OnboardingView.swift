import SwiftUI

/// First-run setup, shown in its own window by `OnboardingWindowController`.
struct OnboardingView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    /// Closes the window. `openPopover` is true for the final "Open ChillMac" button.
    let onFinish: (_ openPopover: Bool) -> Void

    enum Step: Int, CaseIterable {
        case welcome, fanControl, approve, cooling, menuBar, done

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .fanControl: return "Fan control"
            case .approve: return "Approve"
            case .cooling: return "Cooling"
            case .menuBar: return "Menu bar"
            case .done: return "Done"
            }
        }
    }

    @State private var step: Step = .welcome
    /// Steps visited, so Back retraces a skip instead of landing on a step that was skipped.
    @State private var history: [Step] = []
    /// Set when the user pressed Install, so a state change only advances the flow when it
    /// is the answer to that press.
    @State private var awaitingInstall = false
    @State private var cooling: CoolingMode = .smart
    @State private var level: PerformanceLevel = .low
    @State private var menuBar: MenuBarTemperatureMode = .whenWarm
    @State private var openAtLogin = true

    @Environment(\.theme) private var theme

    private let approvalPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            stepRail
            content
        }
        .frame(width: 680, height: 480)
        .background(theme.backgroundGradient)
        .onChange(of: monitor.helperState) { state in
            helperStateChanged(state)
        }
        .onReceive(approvalPoll) { _ in
            // Nothing tells the app when the user flips the switch in System Settings, so
            // the approve step asks about once a second.
            guard step == .approve, !monitor.helperBusy else { return }
            monitor.refreshHelperState()
        }
    }

    // MARK: - Navigation

    private func go(to next: Step) {
        withAnimation(.easeInOut(duration: 0.2)) {
            history.append(step)
            step = next
        }
    }

    private func back() {
        guard let previous = history.popLast() else { return }
        awaitingInstall = false
        withAnimation(.easeInOut(duration: 0.2)) { step = previous }
    }

    private func helperStateChanged(_ state: HelperInstaller.HelperState) {
        switch step {
        case .fanControl where awaitingInstall:
            if state == .running {
                awaitingInstall = false
                go(to: .cooling)
            } else if state == .needsApproval {
                awaitingInstall = false
                go(to: .approve)
            }
        case .approve where state == .running:
            go(to: .cooling)
        default:
            break
        }
    }

    private func installHelper() {
        switch monitor.helperState {
        case .running:
            go(to: .cooling)
        case .needsApproval:
            go(to: .approve)
        default:
            awaitingInstall = true
            monitor.installHelper()
        }
    }

    private func applyCooling() {
        settings.performanceLevel = level
        if monitor.helperReady {
            monitor.setCoolingMode(cooling)
        }
        go(to: .menuBar)
    }

    private func finish() {
        if openAtLogin != settings.launchAtLogin {
            settings.setLaunchAtLogin(openAtLogin)
        }
        onFinish(true)
    }

    // MARK: - Rail

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Step.allCases, id: \.self) { item in
                railRow(item)
            }
            Spacer()
        }
        .padding(.top, 48)
        .padding(.horizontal, 12)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(theme.isLight ? Color.white.opacity(0.5) : Color.black.opacity(0.22))
        .overlay(alignment: .trailing) {
            theme.rowDivider.frame(width: 1)
        }
    }

    private func railRow(_ item: Step) -> some View {
        let isCurrent = item == step
        let isDone = item.rawValue < step.rawValue
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(isDone || isCurrent ? theme.teal : theme.track, lineWidth: 1.5)
                    .background(Circle().fill(isDone ? theme.teal : Color.clear))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(item.rawValue + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isCurrent ? theme.teal : theme.textQuaternary)
                }
            }
            .frame(width: 20, height: 20)

            Text(item.title)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundColor(isCurrent ? theme.textPrimary : isDone ? theme.textSecondary : theme.textQuaternary)
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isCurrent ? theme.segmentedBg : Color.clear)
        )
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch step {
                case .welcome: welcomeStep
                case .fanControl: fanControlStep
                case .approve: approveStep
                case .cooling: coolingStep
                case .menuBar: menuBarStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
            .id(step)

            footer
        }
        .padding(.top, 40)
        .padding(.horizontal, 44)
        .padding(.bottom, 24)
    }

    private func header(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if step != .welcome && step != .done {
                Text("STEP \(step.rawValue + 1) OF \(Step.allCases.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(theme.orange)
            }
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            switch step {
            case .fanControl where monitor.helperState != .running:
                textLink("Skip — just monitor") { go(to: .menuBar) }
            case .approve:
                textLink("Do this later") { go(to: .menuBar) }
            default:
                EmptyView()
            }

            Spacer()

            if !history.isEmpty && step != .done {
                Button("Back", action: back)
                    .buttonStyle(SecondaryButtonStyle(theme: theme))
            }

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let style = PrimaryButtonStyle(color: theme.teal, horizontalPadding: 18, cornerRadius: 7)
        switch step {
        case .welcome:
            Button("Get started") { go(to: .fanControl) }
                .buttonStyle(style)
                .keyboardShortcut(.defaultAction)
        case .fanControl:
            if monitor.helperBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing…")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                }
            } else if monitor.helperState == .running {
                Button("Continue") { go(to: .cooling) }
                    .buttonStyle(style)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(action: installHelper) {
                    Label("Install helper", systemImage: "lock.fill")
                }
                .buttonStyle(style)
                .keyboardShortcut(.defaultAction)
            }
        case .approve:
            Button("Open System Settings") { HelperInstaller.openLoginItemsSettings() }
                .buttonStyle(style)
                .keyboardShortcut(.defaultAction)
        case .cooling:
            Button("Continue", action: applyCooling)
                .buttonStyle(style)
                .keyboardShortcut(.defaultAction)
        case .menuBar:
            Button("Continue") {
                settings.menuBarTemperature = menuBar
                go(to: .done)
            }
            .buttonStyle(style)
            .keyboardShortcut(.defaultAction)
        case .done:
            Button("Open ChillMac", action: finish)
                .buttonStyle(style)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func textLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(theme.textSecondary)
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to ChillMac")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text("See how hot your Mac is running and keep it cooler — right from the menu bar. Setup takes about a minute.")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "thermometer.medium", color: theme.green,
                           title: "Know when it’s warm",
                           caption: "Temperatures, CPU, memory, battery and disk in one glance")
                featureRow(icon: "fan.fill", color: theme.orange,
                           title: "Cool it down",
                           caption: "Smart fan curves that react before your Mac slows down")
                featureRow(icon: "checkmark.shield.fill", color: theme.teal,
                           title: "Safe by default",
                           caption: "Fans always return to automatic when ChillMac quits")
            }
            .padding(.top, 4)
        }
    }

    private func featureRow(icon: String, color: Color, title: String, caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
            }
        }
    }

    private var fanControlStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            if monitor.helperState == .running {
                header("Fan control is already on",
                       subtitle: "The helper is installed and responding, so there is nothing to set up here.")
            } else {
                header("Let ChillMac control your fans",
                       subtitle: "macOS only lets apps change fan speed through a small helper with admin rights. You’ll enter your password once.")
            }

            HStack(alignment: .top, spacing: 12) {
                promiseCard(title: "THE HELPER WILL", titleColor: theme.green, icon: "checkmark", iconColor: theme.green,
                            items: ["Set fan speeds", "Reset fans on quit or crash", "Only talk to signed ChillMac"])
                promiseCard(title: "IT WILL NEVER", titleColor: theme.textTertiary, icon: "xmark", iconColor: theme.textTertiary,
                            items: ["Read your files", "Send data anywhere", "Change other settings"])
            }

            Link(destination: URL(string: "https://github.com/idevtim/chillmac/tree/main/FanControlHelper")!) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Open source — read the helper’s code")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(theme.teal)
            }
            .buttonStyle(.plain)

            if monitor.helperState == .unresponsive || monitor.helperState == .needsUpdate {
                Text(monitor.helperState == .needsUpdate
                     ? "An older helper is installed. Installing replaces it."
                     : "A helper is installed but not answering. Installing again usually fixes this.")
                    .font(.system(size: 12))
                    .foregroundColor(theme.orange)
            }
        }
    }

    private func promiseCard(title: String, titleColor: Color, icon: String, iconColor: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundColor(titleColor)
            ForEach(items, id: \.self) { item in
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 14)
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundColor(theme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground(theme, radius: 10)
    }

    private var approveStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("One more switch in System Settings",
                   subtitle: "macOS asks you to approve background helpers yourself.")

            VStack(alignment: .leading, spacing: 0) {
                numberedRow(1, Text("Click ") + Text("Open System Settings").bold() + Text(" below"))
                CardDivider()
                numberedRow(2, Text("Under ") + Text("Allow in the Background").bold() + Text(", turn on ") + Text("ChillMac").bold())
                CardDivider()
                numberedRow(3, Text("Come back — we’ll notice automatically"))
            }
            .cardBackground(theme, radius: 10)

            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.textQuaternary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
    }

    private func numberedRow(_ number: Int, _ text: Text) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(theme.teal)
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.soft(theme.teal)))
            text
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var coolingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("How should ChillMac cool?", subtitle: "Change this anytime from the menu bar.")

            VStack(spacing: 8) {
                coolingChoice(.smart, title: "Smart cooling", icon: "bolt.fill",
                              caption: "Fans speed up as your Mac heats up, then quiet down.", recommended: true)
                coolingChoice(.auto, title: "Leave it to macOS", icon: "arrow.triangle.2.circlepath",
                              caption: "Quietest. Your Mac may run warmer under load.")
                coolingChoice(.manual, title: "I’ll set speeds myself", icon: "slider.horizontal.3",
                              caption: "Fixed fan speeds you adjust from the menu bar.")
            }

            if cooling == .smart {
                HStack(spacing: 12) {
                    Text("Intensity")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Picker("", selection: $level) {
                        ForEach(PerformanceLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cooling)
    }

    private func coolingChoice(_ mode: CoolingMode, title: String, icon: String, caption: String, recommended: Bool = false) -> some View {
        let isSelected = cooling == mode
        return Button(action: { cooling = mode }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? theme.teal : theme.track, lineWidth: 1.5)
                    if isSelected {
                        Circle().fill(theme.teal).frame(width: 8, height: 8)
                    }
                }
                .frame(width: 16, height: 16)

                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? (mode == .smart ? theme.orange : theme.teal) : theme.textTertiary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        if recommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(theme.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(theme.soft(theme.orange)))
                        }
                    }
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.cardBg : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? theme.teal : theme.rowDivider, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var menuBarStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Your menu bar, your way")

            MenuBarPreview(mode: menuBar, peak: monitor.peakTemperature, settings: settings)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show temperature next to the icon")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Text(menuBar.explanation)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textQuaternary)
                    }
                    MenuBarTemperaturePicker(selection: $menuBar)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                CardDivider()
                SettingsRow(title: "Temperature units") {
                    TemperatureUnitPicker(useFahrenheit: $settings.useFahrenheit)
                }
            }
            .cardBackground(theme, radius: 10)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(theme.green)
                .frame(width: 52, height: 52)
                .background(Circle().fill(theme.soft(theme.green)))

            VStack(alignment: .leading, spacing: 6) {
                Text("You’re all set")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text("ChillMac lives in your menu bar — look for the fan icon at the top right of your screen.")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                summaryRow("Fan control", monitor.helperReady ? "On" : "Off")
                CardDivider()
                summaryRow("Cooling", coolingSummary)
                CardDivider()
                summaryRow("Menu bar", "\(settings.menuBarTemperature.label) · \(settings.useFahrenheit ? "°F" : "°C")")
            }
            .cardBackground(theme, radius: 10)

            SwitchRow(
                title: "Open ChillMac when I log in",
                caption: Text("So your cooling settings are always active"),
                isOn: $openAtLogin,
                tint: theme.teal
            )
            .cardBackground(theme, radius: 10)
        }
    }

    private var coolingSummary: String {
        guard monitor.helperReady else { return "macOS" }
        switch settings.coolingMode {
        case .auto: return "macOS"
        case .smart: return "Smart · \(settings.performanceLevel.label)"
        case .manual: return "Manual"
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(theme.green)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Supporting views

/// "Back": quiet fill, primary text.
private struct SecondaryButtonStyle: ButtonStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(theme.segmentedBg.opacity(configuration.isPressed ? 2 : 1))
            .cornerRadius(7)
            .contentShape(Rectangle())
    }
}

/// A strip of menu bar showing what the status item will look like with `mode`.
private struct MenuBarPreview: View {
    let mode: MenuBarTemperatureMode
    let peak: Double
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme

    /// What the status item would show right now. "When warm" previews the reading even on
    /// a cool Mac, or the strip would look identical to "Never".
    private var label: String? {
        switch mode {
        case .off: return nil
        case .whenWarm, .always: return settings.formatMenuBarTemperature(peak > 0 ? peak : 52)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            HStack(spacing: 4) {
                Image(nsImage: .fanMarkTemplate(pointSize: 15))
                    .renderingMode(.template)
                if let label {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.16)))

            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                .font(.system(size: 13, weight: .medium))
        }
        .font(.system(size: 13))
        .foregroundColor(theme.isLight ? Color(red: 0.08, green: 0.08, blue: 0.10) : .white)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.isLight ? Color.white.opacity(0.85) : Color.white.opacity(0.1))
        )
        .animation(.easeInOut(duration: 0.2), value: mode)
    }
}
