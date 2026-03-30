import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(theme.textQuaternary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: settings.showScrollIndicators) {
                VStack(spacing: 16) {
                    appearanceSection
                    temperatureSection
                    batterySaverSection
                    fanControlSection
                    displaySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Spacer()

            // Version
            HStack {
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textQuaternary)
                Spacer()
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPEARANCE")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            HStack(spacing: 8) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button(action: { settings.setAppearanceMode(mode) }) {
                        VStack(spacing: 8) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 20))
                                .foregroundColor(settings.appearanceMode == mode ? modeAccent(mode) : theme.textQuaternary)

                            Text(mode.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(settings.appearanceMode == mode ? theme.textPrimary : theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(settings.appearanceMode == mode ? theme.cardBgHover : theme.cardBg)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(settings.appearanceMode == mode ? modeAccent(mode).opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func modeAccent(_ mode: AppearanceMode) -> Color {
        switch mode {
        case .system: return .teal
        case .light: return .orange
        case .dark: return .blue
        }
    }

    // MARK: - Fan Control

    private var fanControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FAN CONTROL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "display")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Fans on Screen Sleep")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Text("Don't reset fans when display sleeps")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textQuaternary)
                    }
                    Spacer()
                    Toggle(isOn: $settings.keepFansOnScreenSleep) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(theme.cardBg)
            .cornerRadius(12)
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DISPLAY")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                // Scrollbar toggle
                HStack {
                    Image(systemName: "scroll")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 24)
                    Text("Show Scrollbars")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    Toggle(isOn: $settings.showScrollIndicators) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.teal)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()
                    .background(theme.dividerSubtle)

                // FPS counter toggle
                HStack {
                    Image(systemName: "gauge.open.with.cells.fill")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 24)
                    Text("Show FPS Counter")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    Toggle(isOn: $settings.showFPS) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.teal)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()
                    .background(theme.dividerSubtle)

                // Reset popover height
                HStack {
                    Image(systemName: "arrow.up.and.down.square")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Window Height")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Text("Drag the handle at the bottom to resize")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textQuaternary)
                    }
                    Spacer()
                    if abs(settings.popoverHeight - Double(AppSettings.popoverDefaultHeight)) > 10
                        || abs(settings.detailPanelHeight - Double(AppSettings.detailPanelDefaultHeight)) > 10 {
                        Button("Reset") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.popoverHeight = Double(AppSettings.popoverDefaultHeight)
                                settings.detailPanelHeight = Double(AppSettings.detailPanelDefaultHeight)
                            }
                            NotificationCenter.default.post(name: .detailPanelHeightReset, object: nil)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.teal)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(theme.cardBg)
            .cornerRadius(12)
        }
    }

    // MARK: - Battery Saver

    private var batterySaverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BATTERY SAVER")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                // Enable toggle
                HStack {
                    Image(systemName: "battery.25")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery Saver")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Text("Disable fan control on low battery")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textQuaternary)
                    }
                    Spacer()
                    Toggle(isOn: $settings.batterySaverEnabled) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.yellow)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if settings.batterySaverEnabled {
                    Divider()
                        .background(theme.dividerSubtle)

                    // Threshold slider
                    HStack {
                        Image(systemName: "gauge.low")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textTertiary)
                            .frame(width: 24)
                        Text("Threshold")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text("\(settings.batterySaverThreshold)%")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.yellow)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                    Slider(
                        value: Binding(
                            get: { Double(settings.batterySaverThreshold) },
                            set: { settings.batterySaverThreshold = Int($0) }
                        ),
                        in: 5...50,
                        step: 5
                    )
                    .tint(.yellow)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                    Divider()
                        .background(theme.dividerSubtle)

                    // Force performance toggle
                    HStack {
                        Image(systemName: "bolt.batteryblock.fill")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textTertiary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Force Performance")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(theme.textPrimary)
                            Text("Keep fan control on low battery")
                                .font(.system(size: 11))
                                .foregroundColor(theme.textQuaternary)
                        }
                        Spacer()
                        Toggle(isOn: $settings.forcePerformanceOnBattery) {
                            EmptyView()
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .background(theme.cardBg)
            .cornerRadius(12)
            .animation(.easeInOut(duration: 0.2), value: settings.batterySaverEnabled)
        }
    }

    // MARK: - Temperature

    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TEMPERATURE")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            HStack(spacing: 8) {
                Button(action: { settings.useFahrenheit = false }) {
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 16))
                        Text("Celsius (°C)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(!settings.useFahrenheit ? theme.textPrimary : theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(!settings.useFahrenheit ? theme.cardBgHover : theme.cardBg)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(!settings.useFahrenheit ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: { settings.useFahrenheit = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 16))
                        Text("Fahrenheit (°F)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(settings.useFahrenheit ? theme.textPrimary : theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(settings.useFahrenheit ? theme.cardBgHover : theme.cardBg)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settings.useFahrenheit ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
