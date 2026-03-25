import SwiftUI

struct FanRowView: View {
    let fan: FanInfo
    let helper: HelperConnection
    @ObservedObject var monitor: FanMonitor
    @ObservedObject private var settings = AppSettings.shared
    @State private var errorMessage: String?
    @Environment(\.theme) private var theme

    private var isManual: Binding<Bool> {
        Binding(
            get: { monitor.manualOverrides[fan.id] ?? false },
            set: { newValue in
                monitor.manualOverrides[fan.id] = newValue
                setFanMode(manual: newValue)
            }
        )
    }

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
        if rpmPercent > 0.8 { return .red }
        if rpmPercent > 0.5 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: icon, name, RPM
            HStack {
                Image(systemName: "fan.fill")
                    .font(.system(size: 20))
                    .foregroundColor(fan.currentRPM > 0 ? .green : theme.textSubtle)
                    .rotationEffect(.degrees(fan.currentRPM > 0 ? 360 : 0))
                    .animation(
                        fan.currentRPM > 0
                            ? .linear(duration: max(0.5, 3000 / fan.currentRPM)).repeatForever(autoreverses: false)
                            : .default,
                        value: fan.currentRPM > 0
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(fan.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textPrimary)

                    Text(settings.performanceMode ? "Performance" : (isManual.wrappedValue ? "Manual" : "Auto"))
                        .font(.system(size: 12))
                        .foregroundColor(settings.performanceMode ? .orange : theme.textQuaternary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(fan.currentRPM.rounded()))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(rpmColor)
                    Text("RPM")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                }
                .frame(width: 110, alignment: .trailing)
            }

            // Manual/Auto toggle
            if settings.performanceMode {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Controlled by Performance Mode")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textQuaternary)
                    Spacer()
                }
            } else if monitor.helperReady {
                HStack {
                    Toggle(isOn: isManual) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.green)
                    .animation(monitor.manualOverrides[fan.id] != nil ? .default : nil, value: isManual.wrappedValue)

                    Text(isManual.wrappedValue ? "Manual Control" : "Automatic")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)

                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting to helper…")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textQuaternary)
                    Spacer()
                }
            }

            // Speed slider (only in manual mode, not during performance mode)
            if !settings.performanceMode, monitor.helperReady, isManual.wrappedValue, sliderRange.upperBound > sliderRange.lowerBound {
                VStack(spacing: 6) {
                    Slider(
                        value: targetRPM,
                        in: sliderRange,
                        step: 100
                    )
                    .tint(.green)

                    HStack {
                        Text("\(Int(fan.minRPM))")
                        Spacer()
                        Text("Target: \(Int(targetRPM.wrappedValue)) RPM")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(fan.maxRPM))")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(theme.textQuaternary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
        }
        .padding(14)
        .background(theme.cardBg)
        .cornerRadius(12)
    }

    private func setFanMode(manual: Bool) {
        NSLog("FanRowView: setFanMode fan=%d manual=%d", fan.id, manual ? 1 : 0)
        helper.setFanMode(fanIndex: fan.id, isAuto: !manual) { success, error in
            DispatchQueue.main.async {
                if !success {
                    errorMessage = error ?? "Failed to set fan mode"
                    monitor.manualOverrides[fan.id] = !manual
                } else {
                    errorMessage = nil
                    if manual {
                        // Initialize slider to current RPM (or minRPM if fans aren't spinning)
                        let initialRPM = fan.currentRPM > fan.minRPM ? fan.currentRPM : fan.minRPM
                        monitor.targetOverrides[fan.id] = initialRPM
                        // Immediately send the target so the fan actually spins
                        setFanSpeed(rpm: Int(initialRPM))
                    }
                }
            }
        }
    }

    private func setFanSpeed(rpm: Int) {
        NSLog("FanRowView: setFanSpeed fan=%d rpm=%d", fan.id, rpm)
        helper.setFanSpeed(fanIndex: fan.id, rpm: rpm) { success, error in
            DispatchQueue.main.async {
                if !success {
                    errorMessage = error ?? "Failed to set fan speed"
                } else {
                    errorMessage = nil
                }
            }
        }
    }
}
