import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var systemInfo: SystemInfo
    @ObservedObject var batteryInfo: BatteryInfo
    @ObservedObject var cpuInfo: CpuInfo
    let helper: HelperConnection
    var onMemoryTap: (() -> Void)?
    var onDiskTap: (() -> Void)?
    var onBatteryTap: (() -> Void)?
    var onCpuTap: (() -> Void)?

    var body: some View {
        ZStack {
            // Dark blue-green gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.12, blue: 0.20),
                    Color(red: 0.04, green: 0.08, blue: 0.14)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // Header
                headerSection

                if let error = monitor.smcError {
                    errorSection(error)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            // System info cards
                            systemInfoCards

                            // Fan cards
                            fansSection

                            // Temperature cards
                            if !monitor.sensors.isEmpty {
                                temperaturesSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                }

                // Footer
                footerSection
            }
        }
        .frame(width: 420, height: 640)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("System Temp:")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Text(thermalStatus)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(thermalStatusColor)
                }

                Text(systemInfo.machineModel)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "laptopcomputer")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var thermalStatus: String {
        guard !monitor.sensors.isEmpty else { return "Good" }
        let maxTemp = monitor.sensors.map(\.temperature).max() ?? 0
        if maxTemp >= 90 { return "Hot" }
        if maxTemp >= 75 { return "Warm" }
        return "Good"
    }

    private var thermalStatusColor: Color {
        guard !monitor.sensors.isEmpty else { return .green }
        let maxTemp = monitor.sensors.map(\.temperature).max() ?? 0
        if maxTemp >= 90 { return .red }
        if maxTemp >= 75 { return .orange }
        return .green
    }

    // MARK: - System Info Cards

    private var systemInfoCards: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            InfoCard(
                icon: "cpu",
                title: systemInfo.chipName,
                subtitle: "Processor",
                accent: .teal
            )
            InfoCard(
                icon: "memorychip",
                title: systemInfo.ramAmount,
                subtitle: "Memory",
                accent: .green,
                onTap: onMemoryTap
            )
            InfoCard(
                icon: "internaldrive",
                title: systemInfo.diskUsage,
                subtitle: "Disk Available",
                accent: .blue,
                onTap: onDiskTap
            )
            InfoCard(
                icon: "battery.100",
                title: "\(batteryInfo.currentCharge)%",
                subtitle: batteryInfo.isCharging ? "Charging" : "Battery",
                accent: .yellow,
                onTap: onBatteryTap
            )
            InfoCard(
                icon: "cpu",
                title: String(format: "%.0f%%", cpuInfo.totalUsage),
                subtitle: "CPU",
                accent: .teal,
                onTap: onCpuTap
            )
        }
    }

    // MARK: - Fans

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: "Fans")

            ForEach(monitor.fans) { fan in
                FanRowView(fan: fan, helper: helper, monitor: monitor)
            }

            if monitor.fans.isEmpty {
                HStack {
                    Image(systemName: "fan.slash")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.4))
                    Text("No fans detected")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Temperatures

    private var temperaturesSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: "Temperatures")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(monitor.sensors) { sensor in
                    TemperatureRowView(sensor: sensor, settings: settings)
                }
            }
        }
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("SMC Error")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("ChillMac")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Spacer()

            Button(action: { settings.useFahrenheit.toggle() }) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
                Text(settings.useFahrenheit ? "°F" : "°C")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.25))
    }
}

// MARK: - Supporting Views

struct CardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
            .tracking(1.2)
            .padding(.leading, 4)
            .padding(.top, 4)
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var accent: Color = .blue
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    private var isClickable: Bool { onTap != nil }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { cardContent }
                    .buttonStyle(.plain)
                    .onHover { isHovered = $0 }
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if isClickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.3))
            }
        }
        .padding(14)
        .background(Color.white.opacity(isClickable ? (isHovered ? 0.14 : 0.10) : 0.07))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isClickable ? accent.opacity(isHovered ? 0.6 : 0.4) : Color.clear, lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        CardSectionHeader(title: title)
    }
}
