import SwiftUI

struct TemperatureRowView: View {
    let sensor: TemperatureSensor
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(temperatureColor)
                .frame(width: 6, height: 6)

            Text(sensor.label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()

            Text(settings.formatTemperature(sensor.temperature))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(temperatureColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
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
