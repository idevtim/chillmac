import SwiftUI

struct BatteryDetailView: View {
    @ObservedObject var batteryInfo: BatteryInfo
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme

    /// Apple rates current MacBook batteries for 1,000 cycles.
    private static let ratedCycles = 1000

    var body: some View {
        DetailPanelScaffold(title: "Battery") {
            gaugeSection

            VStack(spacing: 0) {
                PanelValueRow(
                    icon: "heart.fill",
                    iconColor: healthColor,
                    title: "Health",
                    value: "\(healthLabel) · \(batteryInfo.healthPercent)%",
                    valueColor: healthColor
                ) {
                    Text("Holds \(batteryInfo.healthPercent)% of the charge it did when new. Apple considers 80%+ normal.")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textQuaternary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 30)
                }
                CardDivider()
                PanelValueRow(
                    icon: "arrow.clockwise",
                    iconColor: theme.teal,
                    title: "Charge cycles",
                    value: "\(batteryInfo.cycleCount.formatted()) of \(Self.ratedCycles.formatted())"
                ) {
                    ProgressBar(
                        fraction: Double(batteryInfo.cycleCount) / Double(Self.ratedCycles),
                        color: theme.teal,
                        height: 4
                    )
                    .padding(.leading, 30)
                }
                CardDivider()
                PanelValueRow(
                    icon: "thermometer.medium",
                    iconColor: tempColor,
                    title: "Temperature",
                    value: "\(tempLabel) · \(settings.formatTemperature(batteryInfo.temperature))",
                    valueColor: tempColor
                )
            }
            .cardBackground(theme)

            detailsSection
        }
    }

    // MARK: - Gauge

    private var gaugeSection: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(theme.ringTrack, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(batteryInfo.currentCharge) / 100.0)
                    .stroke(chargeColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(batteryInfo.currentCharge)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Text("%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(5)
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                HStack(spacing: 5) {
                    Image(systemName: batteryInfo.isPluggedIn ? "powerplug.fill" : "battery.75")
                        .font(.system(size: 12))
                    Text(statusDescription)
                        .font(.system(size: 13))
                }
                .foregroundColor(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var chargeColor: Color {
        if batteryInfo.currentCharge <= 10 { return theme.red }
        if batteryInfo.currentCharge <= 20 { return theme.orange }
        return theme.green
    }

    private var statusTitle: String {
        if batteryInfo.currentCharge >= 100 { return "Fully charged" }
        if batteryInfo.isCharging { return "Charging" }
        return "On battery"
    }

    private var statusDescription: String {
        if batteryInfo.isPluggedIn && !batteryInfo.isCharging { return "On power adapter" }
        return batteryInfo.timeRemaining
    }

    // MARK: - Health & Temperature

    private var healthLabel: String {
        if batteryInfo.healthPercent >= 80 { return "Good" }
        if batteryInfo.healthPercent >= 60 { return "Worn" }
        return "Replace soon"
    }

    private var healthColor: Color {
        if batteryInfo.healthPercent >= 80 { return theme.green }
        if batteryInfo.healthPercent >= 60 { return theme.orange }
        return theme.red
    }

    private var tempLabel: String {
        if batteryInfo.temperature >= 40 { return "Hot" }
        if batteryInfo.temperature >= 35 { return "Warm" }
        return "Normal"
    }

    private var tempColor: Color {
        if batteryInfo.temperature >= 40 { return theme.red }
        if batteryInfo.temperature >= 35 { return theme.orange }
        return theme.green
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: "Details")

            VStack(spacing: 0) {
                BatteryDetailRow(label: "Condition", value: batteryInfo.condition)
                CardDivider()
                BatteryDetailRow(label: "Current capacity", value: "\(batteryInfo.maxCapacity.formatted()) mAh")
                CardDivider()
                BatteryDetailRow(label: "Original capacity", value: "\(batteryInfo.designCapacity.formatted()) mAh")
            }
            .cardBackground(theme)
        }
    }
}

private struct BatteryDetailRow: View {
    let label: String
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
