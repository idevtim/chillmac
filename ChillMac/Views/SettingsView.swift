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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    appearanceSection
                    temperatureSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Spacer()
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
                    Button(action: { settings.appearanceMode = mode }) {
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
