import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var systemInfo: SystemInfo
    let helper: HelperConnection

    var body: some View {
        ZStack {
            // Dark purple gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.08, blue: 0.35),
                    Color(red: 0.10, green: 0.05, blue: 0.25)
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
                        VStack(spacing: 10) {
                            // System info cards
                            systemInfoCards

                            // Fan cards
                            fansSection

                            // Temperature cards
                            if !monitor.sensors.isEmpty {
                                temperaturesSection
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 14)
                    }
                }

                // Footer
                footerSection
            }
        }
        .frame(width: 400, height: 620)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Fan Control:")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text(thermalStatus)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(thermalStatusColor)
                }

                Text(systemInfo.machineModel)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "laptopcomputer")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
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
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            InfoCard(
                icon: "cpu",
                title: systemInfo.chipName,
                subtitle: "Processor",
                accent: .cyan
            )
            InfoCard(
                icon: "memorychip",
                title: systemInfo.ramAmount,
                subtitle: "Memory",
                accent: .purple
            )
            InfoCard(
                icon: "internaldrive",
                title: systemInfo.diskUsage,
                subtitle: "Disk Usage",
                accent: .blue
            )
            InfoCard(
                icon: "clock.arrow.circlepath",
                title: systemInfo.uptime,
                subtitle: "Uptime",
                accent: .teal
            )
        }
    }

    // MARK: - Fans

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardSectionHeader(title: "Fans")

            ForEach(monitor.fans) { fan in
                FanRowView(fan: fan, helper: helper, monitor: monitor)
            }

            if monitor.fans.isEmpty {
                HStack {
                    Image(systemName: "fan.slash")
                        .foregroundColor(.white.opacity(0.4))
                    Text("No fans detected")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Temperatures

    private var temperaturesSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return VStack(alignment: .leading, spacing: 6) {
            CardSectionHeader(title: "Temperatures")

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(monitor.sensors) { sensor in
                    TemperatureRowView(sensor: sensor, settings: settings)
                }
            }
        }
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("SMC Error")
                .font(.headline)
                .foregroundColor(.white)
            Text(error)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Mac Fan Control")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Spacer()

            Button(action: { settings.useFahrenheit.toggle() }) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                Text(settings.useFahrenheit ? "°F" : "°C")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }
}

// MARK: - Supporting Views

struct CardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
            .tracking(1)
            .padding(.leading, 4)
            .padding(.top, 4)
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var accent: Color = .blue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }
}

// Keep SectionHeader for backward compatibility if referenced elsewhere
struct SectionHeader: View {
    let title: String

    var body: some View {
        CardSectionHeader(title: title)
    }
}
