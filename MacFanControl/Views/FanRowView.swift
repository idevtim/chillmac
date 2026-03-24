import SwiftUI

struct FanRowView: View {
    let fan: FanInfo
    let helper: HelperConnection
    @ObservedObject var monitor: FanMonitor
    @State private var errorMessage: String?

    private var isManual: Binding<Bool> {
        Binding(
            get: { monitor.manualOverrides[fan.id] ?? fan.isManualMode },
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
        return .cyan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: icon, name, RPM
            HStack {
                Image(systemName: "fan.fill")
                    .font(.system(size: 16))
                    .foregroundColor(fan.currentRPM > 0 ? .cyan : .white.opacity(0.3))
                    .rotationEffect(.degrees(fan.currentRPM > 0 ? 360 : 0))
                    .animation(
                        fan.currentRPM > 0
                            ? .linear(duration: max(0.5, 3000 / fan.currentRPM)).repeatForever(autoreverses: false)
                            : .default,
                        value: fan.currentRPM > 0
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(fan.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    Text(isManual.wrappedValue ? "Manual" : "Auto")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Text("\(Int(fan.currentRPM.rounded()))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(rpmColor)
                +
                Text(" RPM")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Manual/Auto toggle
            HStack {
                Toggle(isOn: isManual) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.cyan)

                Text(isManual.wrappedValue ? "Manual Control" : "Automatic")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }

            // Speed slider (only in manual mode)
            if isManual.wrappedValue, sliderRange.upperBound > sliderRange.lowerBound {
                VStack(spacing: 4) {
                    Slider(
                        value: targetRPM,
                        in: sliderRange,
                        step: 100
                    )
                    .tint(.cyan)

                    HStack {
                        Text("\(Int(fan.minRPM))")
                        Spacer()
                        Text("Target: \(Int(targetRPM.wrappedValue)) RPM")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(fan.maxRPM))")
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
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
