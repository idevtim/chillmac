import SwiftUI

struct TemperatureRowView: View {
    let sensor: TemperatureSensor
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(temperatureColor)
                .frame(width: 8, height: 8)

            Text(sensor.label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(settings.formatTemperature(sensor.temperature))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(temperatureColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var temperatureColor: Color {
        ThermalStatus.color(forCelsius: sensor.temperature)
    }
}

#if DEBUG
#Preview("TemperatureRowView") {
    VStack(spacing: 8) {
        ForEach(PreviewSupport.sampleSensors) { sensor in
            TemperatureRowView(
                sensor: sensor,
                settings: AppSettings.shared
            )
        }
    }
    .padding()
    .previewHost(scheme: .dark)
}
#endif
