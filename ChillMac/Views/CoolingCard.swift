import SwiftUI

/// The popover's single fan control: Automatic, Smart or Manual, with the fans listed below.
/// Shown only once the helper can carry out commands; `HelperStatusCard` stands in otherwise.
struct CoolingCard: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings

    @Environment(\.theme) private var theme

    private var mode: CoolingMode { settings.coolingMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if monitor.batterySaverActive {
                    batterySaverBanner
                }

                CoolingModePicker(selection: Binding(
                    get: { mode },
                    set: { newMode in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.setCoolingMode(newMode)
                        }
                    }
                ))

                Text(mode.description)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if mode == .smart {
                    IntensityGrid(selection: $settings.performanceLevel)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)

            fanList
        }
        .cardBackground(theme)
        .animation(.easeInOut(duration: 0.2), value: mode)
        .animation(.easeInOut(duration: 0.2), value: monitor.batterySaverActive)
    }

    private var batterySaverBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "battery.25")
                .font(.system(size: 13))
                .foregroundColor(theme.yellow)
            Text("Battery saver — fans set to auto")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.yellow)
            Spacer()
            Button(action: { settings.forcePerformanceOnBattery = true }) {
                Text("Override")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(theme.yellow.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var fanList: some View {
        if monitor.fans.isEmpty {
            CardDivider()
            FanListPlaceholder(monitor: monitor)
        } else {
            ForEach(monitor.fans) { fan in
                CardDivider()
                FanRowView(fan: fan, monitor: monitor, mode: mode)
            }
        }
    }
}

/// "Reading fans…" before the first poll, "No fans detected" after it.
struct FanListPlaceholder: View {
    @ObservedObject var monitor: FanMonitor
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            // Until the first poll publishes, an empty array only means "not read yet":
            // claiming "No fans detected" there would be wrong on every Mac.
            if !monitor.hasCompletedFirstPoll && monitor.smcError == nil {
                PanelLoadingView(message: "Reading fans…", minHeight: 24)
            } else {
                HStack {
                    Image(systemName: "fan.slash")
                        .font(.system(size: 16))
                    Text("No fans detected")
                        .font(.system(size: 13))
                }
                .foregroundColor(theme.textQuaternary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
    }
}

// MARK: - Mode picker

/// Three-segment control with icons. Drawn by hand rather than as a native segmented
/// `Picker`: macOS drops either the icon or the label there, and Smart's selected label is
/// orange to match the rest of the Smart UI.
struct CoolingModePicker: View {
    @Binding var selection: CoolingMode
    @State private var hovered: CoolingMode?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CoolingMode.allCases, id: \.self) { mode in
                let isSelected = selection == mode
                let isHovered = hovered == mode && !isSelected
                Button(action: { selection = mode }) {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.label)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(isHovered ? theme.textPrimary : labelColor(mode, isSelected: isSelected))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? selectedFill : isHovered ? hoverFill : Color.clear)
                            .shadow(color: isSelected && theme.isLight ? .black.opacity(0.15) : .clear, radius: 1, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hovered = mode } else if hovered == mode { hovered = nil }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .padding(2)
        .background(theme.segmentedBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var selectedFill: Color {
        theme.isLight ? .white : Color.white.opacity(0.18)
    }

    /// Halfway to selected, so a hovered segment reads as clickable without looking chosen.
    private var hoverFill: Color {
        theme.isLight ? Color.white.opacity(0.55) : Color.white.opacity(0.09)
    }

    private func labelColor(_ mode: CoolingMode, isSelected: Bool) -> Color {
        guard isSelected else { return theme.textSecondary }
        return mode == .smart ? theme.orange : theme.textPrimary
    }
}

// MARK: - Intensity

/// Smart cooling's four levels as chips, with the selected level's description underneath.
struct IntensityGrid: View {
    @Binding var selection: PerformanceLevel
    @State private var hovered: PerformanceLevel?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(PerformanceLevel.allCases, id: \.self) { level in
                    chip(level)
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.orange)
                Text(selection.description)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chip(_ level: PerformanceLevel) -> some View {
        let isSelected = selection == level
        let isHovered = hovered == level && !isSelected
        return Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selection = level } }) {
            VStack(spacing: 4) {
                Image(systemName: level.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? theme.orange : isHovered ? theme.textSecondary : theme.textTertiary)
                    .frame(height: 20)
                Text(level.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected || isHovered ? theme.textPrimary : theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? theme.soft(theme.orange) : isHovered ? theme.cardBgHover : theme.segmentedBg)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? theme.orange : isHovered ? theme.orange.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = level } else if hovered == level { hovered = nil }
        }
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
