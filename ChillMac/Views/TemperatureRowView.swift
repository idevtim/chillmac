import SwiftUI

struct TemperatureRowView: View {
    let sensor: TemperatureSensor
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(temperatureColor)
                .frame(width: 8, height: 8)

            Text(sensor.label)
                .font(.system(size: 12))
                .foregroundColor(theme.textSecondary)
                .lineLimit(1)

            Spacer()

            Text(settings.formatTemperature(sensor.temperature))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(temperatureColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.cardBgSecondary)
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
