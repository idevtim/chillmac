import SwiftUI

struct FanRowView: View {
    let fan: FanInfo
    let helper: HelperConnection
    @ObservedObject var monitor: FanMonitor
    @ObservedObject private var settings = AppSettings.shared
    @State private var errorMessage: String?

    private var activelyCooling: Bool {
        PerformanceControl.isActivelyControlling(
            performanceMode: settings.performanceMode,
            helperReady: monitor.helperReady,
            coolingEngaged: monitor.coolingEngaged
        )
    }

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

    private var modeLabel: String {
        if activelyCooling { return "Cooling" }
        if isManual.wrappedValue { return "Manual" }
        return "Auto"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Space.sm) {
            HStack {
                Image(systemName: "fan.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(fan.currentRPM > 0 ? Color.green : Color.secondary)
                    .rotationEffect(.degrees(fan.currentRPM > 0 ? 360 : 0))
                    .animation(
                        fan.currentRPM > 0
                            ? .linear(duration: max(0.5, 3000 / max(fan.currentRPM, 1))).repeatForever(autoreverses: false)
                            : .default,
                        value: fan.currentRPM > 0
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(fan.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(modeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(activelyCooling ? Color.accentColor : Color.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(fan.currentRPM.rounded()))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(rpmColor)
                    Text("RPM")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 110, alignment: .trailing)
            }

            if activelyCooling {
                Label("Controlled by Cool", systemImage: "snowflake")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else if monitor.helperReady {
                HStack {
                    Toggle(isOn: isManual) { EmptyView() }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Text(isManual.wrappedValue ? "Manual Control" : "Automatic")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                HStack(spacing: DesignSystem.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to helper…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            if !settings.performanceMode, monitor.helperReady, isManual.wrappedValue, sliderRange.upperBound > sliderRange.lowerBound {
                VStack(spacing: 6) {
                    Slider(value: targetRPM, in: sliderRange, step: 100)
                    HStack {
                        Text("\(Int(fan.minRPM))")
                        Spacer()
                        Text("Target: \(Int(targetRPM.wrappedValue)) RPM").fontWeight(.medium)
                        Spacer()
                        Text("\(Int(fan.maxRPM))")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .chillCard()
    }

    private func setFanMode(manual: Bool) {
        helper.setFanMode(fanIndex: fan.id, isAuto: !manual) { success, error in
            DispatchQueue.main.async {
                if !success {
                    errorMessage = error ?? "Failed to set fan mode"
                    monitor.manualOverrides[fan.id] = !manual
                } else {
                    errorMessage = nil
                    if manual {
                        let initialRPM = fan.currentRPM > fan.minRPM ? fan.currentRPM : fan.minRPM
                        monitor.targetOverrides[fan.id] = initialRPM
                        setFanSpeed(rpm: Int(initialRPM))
                    }
                }
            }
        }
    }

    private func setFanSpeed(rpm: Int) {
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

#if DEBUG
#Preview("FanRowView") {
    FanRowView(
        fan: PreviewSupport.sampleFans[0],
        helper: PreviewSupport.helper,
        monitor: PreviewSupport.fanMonitor
    )
    .previewHost(scheme: .dark)
}
#endif
