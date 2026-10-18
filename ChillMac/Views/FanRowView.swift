import SwiftUI

/// One fan inside the Cooling card. `mode` is who currently drives the fan; nil means the
/// helper is unavailable and the row is read-only.
struct FanRowView: View {
    let fan: FanInfo
    @ObservedObject var monitor: FanMonitor
    let mode: CoolingMode?
    @State private var errorMessage: String?
    @Environment(\.theme) private var theme

    private var targetRPM: Binding<Double> {
        Binding(
            get: { monitor.targetOverrides[fan.id] ?? fan.targetRPM },
            set: { newValue in
                monitor.targetOverrides[fan.id] = newValue
                setFanSpeed(rpm: Int(newValue))
            }
        )
    }

    private var sliderRange: ClosedRange<Double> {
        let lo = fan.minRPM
        let hi = fan.maxRPM
        guard hi > lo else { return lo...(lo + 100) }
        return lo...hi
    }

    private var rpmPercent: Double {
        guard fan.maxRPM > fan.minRPM else { return 0 }
        return (fan.currentRPM - fan.minRPM) / (fan.maxRPM - fan.minRPM)
    }

    private var rpmColor: Color {
        if rpmPercent > 0.8 { return theme.red }
        if rpmPercent > 0.5 { return theme.orange }
        return theme.green
    }

    /// Share of the fan's range the current target asks for.
    private var targetPercent: Int {
        guard fan.maxRPM > fan.minRPM else { return 0 }
        let target = monitor.targetOverrides[fan.id] ?? fan.targetRPM
        return Int(((target - fan.minRPM) / (fan.maxRPM - fan.minRPM) * 100).rounded())
    }

    private var ownerLine: (text: String, color: Color) {
        switch mode {
        case nil:
            return ("macOS", theme.textQuaternary)
        case .auto:
            return ("Run by macOS", theme.textTertiary)
        case .smart:
            if monitor.batterySaverActive { return ("Battery saver · run by macOS", theme.yellow) }
            let pct = targetPercent
            return (pct < 1 ? "Smart cooling · idling" : "Smart cooling · \(pct)%", theme.orange)
        case .manual:
            return ("Fixed at \(max(targetPercent, 0))%", theme.textTertiary)
        }
    }

    private var showsSlider: Bool {
        mode == .manual && monitor.manualOverrides[fan.id] == true && sliderRange.upperBound > sliderRange.lowerBound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "fan.fill")
                    .font(.system(size: 20))
                    .foregroundColor(fan.currentRPM > 0 ? theme.green : theme.textSubtle)
                    .rotationEffect(.degrees(fan.currentRPM > 0 ? 360 : 0))
                    .animation(
                        fan.currentRPM > 0
                            ? .linear(duration: max(0.5, 3000 / fan.currentRPM)).repeatForever(autoreverses: false)
                            : .default,
                        value: fan.currentRPM > 0
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(fan.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(ownerLine.text)
                        .font(.system(size: 11))
                        .foregroundColor(ownerLine.color)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(fan.currentRPM.rounded()))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(rpmColor)
                    Text("RPM")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                }
            }

            if showsSlider {
                VStack(spacing: 4) {
                    Slider(value: targetRPM, in: sliderRange, step: 100)
                        .tint(theme.green)
                        .controlSize(.small)

                    HStack {
                        Text("Quietest")
                        Spacer()
                        Text("\(Int(targetRPM.wrappedValue).formatted()) RPM")
                            .fontWeight(.medium)
                            .foregroundColor(theme.textSecondary)
                        Spacer()
                        Text("Fastest")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(theme.textQuaternary)
                }
                .padding(.leading, 30)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(theme.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func setFanSpeed(rpm: Int) {
        errorMessage = nil
        // Routed through the monitor so a slider drag collapses into a couple of privileged
        // writes instead of one per 100 RPM step.
        monitor.requestManualFanSpeed(fanIndex: fan.id, rpm: rpm) { message in
            errorMessage = message
        }
    }
}
