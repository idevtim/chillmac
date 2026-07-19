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

    private var rpmText: String {
        "\(Int(fan.currentRPM.rounded()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if activelyCooling {
                LabeledContent {
                    Text(rpmText)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary)
                } label: {
                    Text(shortName)
                        .foregroundStyle(.primary)
                }
            } else if monitor.helperReady {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(rpmText)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Toggle(isOn: isManual) { EmptyView() }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                } label: {
                    Text(shortName)
                }

                if !settings.performanceMode, isManual.wrappedValue, sliderRange.upperBound > sliderRange.lowerBound {
                    Slider(value: targetRPM, in: sliderRange, step: 100)
                        .controlSize(.small)
                }
            } else {
                LabeledContent {
                    ProgressView()
                        .controlSize(.small)
                } label: {
                    Text(shortName)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var shortName: String {
        fan.name
            .replacingOccurrences(of: " Fan", with: "")
            .replacingOccurrences(of: "fan", with: "")
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
    Form {
        Section("Fans") {
            FanRowView(
                fan: PreviewSupport.sampleFans[0],
                helper: PreviewSupport.helper,
                monitor: PreviewSupport.fanMonitor
            )
        }
    }
    .formStyle(.grouped)
    .previewHost(scheme: .dark)
}
#endif
