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
                SpinningFanIcon(rpm: fan.currentRPM, maxRPM: fan.maxRPM,
                                color: fan.currentRPM > 0 ? theme.green : theme.textSubtle)

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

/// Fan glyph that turns while the fan does, faster as the RPM rises.
///
/// Driven by a clock rather than a repeating SwiftUI animation: a repeating animation only
/// starts when its value changes, so a fan already running when the popover first draws
/// would sit still. The angle is accumulated frame by frame, so a change in speed eases the
/// rate instead of making the blades jump.
private struct SpinningFanIcon: View {
    let rpm: Double
    let maxRPM: Double
    let color: Color

    @State private var spin = Spin()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private final class Spin {
        var angle: Double = 0
        var lastTick: Date?
    }

    /// Degrees per second on screen. A real fan's speed would just blur, so this maps the
    /// fan's range onto a slow-to-brisk turn.
    private var degreesPerSecond: Double {
        guard rpm > 0 else { return 0 }
        let fraction = maxRPM > 0 ? min(rpm / maxRPM, 1) : 0.5
        return 120 + fraction * 600
    }

    var body: some View {
        if rpm > 0 && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                glyph.rotationEffect(.degrees(angle(at: context.date)))
            }
        } else {
            glyph.rotationEffect(.degrees(spin.angle))
        }
    }

    private var glyph: some View {
        Image(systemName: "fan.fill")
            .font(.system(size: 20))
            .foregroundColor(color)
    }

    private func angle(at date: Date) -> Double {
        // Cap the step so a pause (popover closed, then reopened) doesn't fling the blades.
        let elapsed = spin.lastTick.map { min(date.timeIntervalSince($0), 0.1) } ?? 0
        spin.lastTick = date
        spin.angle = (spin.angle + elapsed * degreesPerSecond).truncatingRemainder(dividingBy: 360)
        return spin.angle
    }
}
