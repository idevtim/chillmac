import SwiftUI

struct BatteryDetailView: View {
    @ObservedObject var batteryInfo: BatteryInfo
    @ObservedObject var settings: AppSettings

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.12, blue: 0.20),
                    Color(red: 0.04, green: 0.08, blue: 0.14)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("Battery")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Gauge + status
                        gaugeSection

                        // Health & Temperature cards
                        healthCards

                        // Details
                        detailsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 370, height: 560)
    }

    // MARK: - Gauge

    private var gaugeSection: some View {
        HStack(spacing: 16) {
            // Circular battery gauge
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 14)

                // Charge level arc
                Circle()
                    .trim(from: 0, to: CGFloat(batteryInfo.currentCharge) / 100.0)
                    .stroke(
                        chargeColor,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Center percentage
                VStack(spacing: 2) {
                    Text("\(batteryInfo.currentCharge)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("%")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(10)
            .frame(width: 140, height: 140)

            // Status info
            VStack(alignment: .leading, spacing: 8) {
                Text(statusTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(statusDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))

                Divider().background(Color.white.opacity(0.1))

                HStack(spacing: 4) {
                    Text("\(batteryInfo.cycleCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("/ 1000")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                Text("charge cycles")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
    }

    private var chargeColor: Color {
        if batteryInfo.currentCharge <= 10 { return .red }
        if batteryInfo.currentCharge <= 20 { return .orange }
        return .green
    }

    private var statusTitle: String {
        if batteryInfo.currentCharge >= 100 { return "Fully Charged" }
        if batteryInfo.isCharging { return "Charging" }
        return "On Battery"
    }

    private var statusDescription: String {
        if batteryInfo.currentCharge >= 100 && batteryInfo.isPluggedIn {
            return "Connected to power adapter"
        }
        if batteryInfo.isCharging {
            return batteryInfo.timeRemaining
        }
        if batteryInfo.isPluggedIn {
            return "Connected to power"
        }
        return batteryInfo.timeRemaining
    }

    // MARK: - Health & Temperature Cards

    private var healthCards: some View {
        HStack(alignment: .top, spacing: 12) {
            // Health card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundColor(healthColor)
                    Text("Health")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(batteryInfo.healthPercent)%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(healthColor)
                }

                Text(healthDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.07))
            .cornerRadius(12)

            // Temperature card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 14))
                        .foregroundColor(tempColor)
                    Text("Temperature")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }

                Text(settings.formatTemperature(batteryInfo.temperature))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(tempColor)

                Text(tempDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.07))
            .cornerRadius(12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var healthColor: Color {
        if batteryInfo.healthPercent >= 80 { return .green }
        if batteryInfo.healthPercent >= 60 { return .orange }
        return .red
    }

    private var healthDescription: String {
        if batteryInfo.healthPercent >= 90 {
            return "Battery is in excellent condition."
        } else if batteryInfo.healthPercent >= 80 {
            return "Good condition, some capacity lost."
        } else if batteryInfo.healthPercent >= 60 {
            return "Battery has degraded significantly."
        } else {
            return "Battery needs replacement."
        }
    }

    private var tempColor: Color {
        if batteryInfo.temperature >= 40 { return .red }
        if batteryInfo.temperature >= 35 { return .orange }
        return .green
    }

    private var tempDescription: String {
        if batteryInfo.temperature >= 40 {
            return "Battery is too hot."
        } else if batteryInfo.temperature >= 35 {
            return "Battery is warm."
        } else {
            return "Within normal range."
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETAILS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.2)
                .padding(.leading, 4)
                .padding(.top, 4)

            VStack(spacing: 0) {
                DetailRow(label: "Condition", value: batteryInfo.condition)
                DetailRow(label: "Cycle Count", value: "\(batteryInfo.cycleCount)")
                DetailRow(label: "Max Capacity", value: "\(batteryInfo.maxCapacity) mAh")
                DetailRow(label: "Design Capacity", value: "\(batteryInfo.designCapacity) mAh")
            }
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
