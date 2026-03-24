import SwiftUI

struct FanRowView: View {
    let fan: FanInfo
    let helper: HelperConnection

    @State private var targetRPM: Double
    @State private var isManual: Bool
    @State private var errorMessage: String?

    init(fan: FanInfo, helper: HelperConnection) {
        self.fan = fan
        self.helper = helper
        _targetRPM = State(initialValue: fan.targetRPM)
        _isManual = State(initialValue: fan.isManualMode)
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
                    .rotationEffect(.degrees(fan.currentRPM > 0 ? 360 : 0))
                    .animation(
                        fan.currentRPM > 0
                            ? .linear(duration: max(0.3, 3000.0 / fan.currentRPM)).repeatForever(autoreverses: false)
                            : .default,
                        value: fan.currentRPM > 0
                    )

                Text(fan.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(Int(fan.currentRPM)) RPM")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Manual/Auto toggle
            HStack {
                Toggle(isOn: $isManual) {
                    Text(isManual ? "Manual" : "Auto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: isManual) { newValue in
                    setFanMode(manual: newValue)
                }
            }

            // Speed slider (only in manual mode)
            if isManual, sliderRange.upperBound > sliderRange.lowerBound {
                VStack(spacing: 2) {
                    Slider(
                        value: $targetRPM,
                        in: sliderRange,
                        step: 100
                    )
                    .onChange(of: targetRPM) { newValue in
                        setFanSpeed(rpm: Int(newValue))
                    }

                    HStack {
                        Text("\(Int(fan.minRPM))")
                        Spacer()
                        Text("Target: \(Int(targetRPM)) RPM")
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
        helper.setFanMode(fanIndex: fan.id, isAuto: !manual) { success, error in
            DispatchQueue.main.async {
                if !success {
                    errorMessage = error ?? "Failed to set fan mode"
                    isManual = !manual // revert
                } else {
                    errorMessage = nil
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
