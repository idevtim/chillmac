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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "fan")
                    .foregroundColor(fan.currentRPM > 0 ? .accentColor : .secondary)

                Text(fan.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(Int(fan.currentRPM.rounded())) RPM")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Manual/Auto toggle
            HStack {
                Toggle(isOn: isManual) {
                    Text(isManual.wrappedValue ? "Manual" : "Auto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            // Speed slider (only in manual mode)
            if isManual.wrappedValue, sliderRange.upperBound > sliderRange.lowerBound {
                VStack(spacing: 2) {
                    Slider(
                        value: targetRPM,
                        in: sliderRange,
                        step: 100
                    )

                    HStack {
                        Text("\(Int(fan.minRPM))")
                        Spacer()
                        Text("Target: \(Int(targetRPM.wrappedValue)) RPM")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(fan.maxRPM))")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func setFanMode(manual: Bool) {
        NSLog("FanRowView: setFanMode fan=%d manual=%d", fan.id, manual ? 1 : 0)
        helper.setFanMode(fanIndex: fan.id, isAuto: !manual) { success, error in
            DispatchQueue.main.async {
                if !success {
                    errorMessage = error ?? "Failed to set fan mode"
                    monitor.manualOverrides[fan.id] = !manual // revert
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
