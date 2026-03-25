import SwiftUI

struct TemperatureRowView: View {
    let sensor: TemperatureSensor
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

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
        let isLight = (settings.preferredColorScheme ?? colorScheme) == .light
        switch sensor.temperature {
        case ..<50: return .green
        case 50..<75: return isLight ? Color(red: 0.75, green: 0.55, blue: 0.0) : .yellow
        case 75..<90: return isLight ? Color(red: 0.80, green: 0.45, blue: 0.0) : .orange
        default: return .red
        }
    }
}
