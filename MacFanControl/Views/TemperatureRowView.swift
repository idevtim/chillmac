import SwiftUI

struct TemperatureRowView: View {
    let sensor: TemperatureSensor
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(temperatureColor)
                .frame(width: 5, height: 5)

            Text(sensor.label)
                .font(.system(size: 10))
                .lineLimit(1)

            Spacer()

            Text(settings.formatTemperature(sensor.temperature))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
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
