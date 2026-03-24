import SwiftUI

struct TemperatureRowView: View {
    let sensor: TemperatureSensor
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack {
            Circle()
                .fill(temperatureColor)
                .frame(width: 6, height: 6)

            Text(sensor.label)
                .font(.caption)

            Spacer()

            Text(settings.formatTemperature(sensor.temperature))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private var temperatureColor: Color {
        switch sensor.temperature {
        case ..<50: return .green
        case 50..<75: return .yellow
        case 75..<90: return .orange
        default: return .red
        }
    }
}
