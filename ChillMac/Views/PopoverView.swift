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
    var onTemperatureTap: (() -> Void)?

    @State private var appeared = false
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme {
        AppTheme.forScheme(settings.preferredColorScheme ?? colorScheme)
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient

            if showingSettings {
                SettingsView(settings: settings) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingSettings = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 420, height: 640)
        .environment(\.theme, theme)
        .preferredColorScheme(settings.preferredColorScheme)
        .onAppear {
            appeared = true
        }
        .onDisappear {
            appeared = false
        }
    }

    private var mainContent: some View {
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

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("System Temp:")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Text(thermalStatus)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(thermalStatusColor)
                }

                Text(systemInfo.machineModel)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
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
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.3), value: appeared)
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

    private var maxTempDisplay: String {
        guard !monitor.sensors.isEmpty,
              let maxTemp = monitor.sensors.map(\.temperature).max() else {
            return "--"
        }
        return settings.formatTemperature(maxTemp)
    }

    // MARK: - System Info Cards

    private var systemInfoCards: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        let cards: [(icon: String, title: String, subtitle: String, accent: Color, onTap: (() -> Void)?)] = [
            ("cpu", systemInfo.chipName, "Processor", .teal, nil),
            ("memorychip", systemInfo.ramAmount, "Memory", .green, onMemoryTap),
            ("internaldrive", systemInfo.diskUsage, "Disk Available", .blue, onDiskTap),
            ("battery.100", "\(batteryInfo.currentCharge)%", batteryInfo.isCharging ? "Charging" : "Battery", .yellow, onBatteryTap),
            ("cpu", String(format: "%.0f%%", cpuInfo.totalUsage), "CPU", .teal, onCpuTap),
            ("thermometer.medium", maxTempDisplay, "Temperatures", thermalStatusColor, onTemperatureTap),
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                InfoCard(
                    icon: card.icon,
                    title: card.title,
                    subtitle: card.subtitle,
                    accent: card.accent,
                    onTap: card.onTap
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.3).delay(0.05 + Double(index) * 0.05), value: appeared)
            }
        }
    }

    // MARK: - Fans

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: "Fans")
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.35), value: appeared)

            ForEach(Array(monitor.fans.enumerated()), id: \.element.id) { index, fan in
                FanRowView(fan: fan, helper: helper, monitor: monitor)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.3).delay(0.4 + Double(index) * 0.05), value: appeared)
            }

            if monitor.fans.isEmpty {
                HStack {
                    Image(systemName: "fan.slash")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textQuaternary)
                    Text("No fans detected")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textQuaternary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(theme.cardBgSecondary)
                .cornerRadius(12)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.4), value: appeared)
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
                .foregroundColor(theme.textPrimary)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(theme.textSecondary)
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
                    .foregroundColor(theme.textTertiary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("ChillMac")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textQuaternary)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSettings = true
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(theme.footerBg)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.15), value: appeared)
    }
}

// MARK: - Supporting Views

struct CardSectionHeader: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(theme.textTertiary)
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
    @Environment(\.theme) private var theme

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
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()

            if isClickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered ? theme.textSecondary : theme.textSubtle)
            }
        }
        .padding(14)
        .background(isClickable ? (isHovered ? theme.cardBgHover : theme.cardBgClickable) : theme.cardBg)
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
