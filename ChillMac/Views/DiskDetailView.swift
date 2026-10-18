import SwiftUI

struct DiskDetailView: View {
    @ObservedObject var systemInfo: SystemInfo
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme

    var body: some View {
        DetailPanelScaffold(title: volumeName) {
            PanelHero(
                status: status.text,
                statusColor: status.color,
                value: systemInfo.diskTotalBytes > 0 ? SystemInfo.formatDiskBytes(systemInfo.diskAvailableBytes) : "—",
                context: systemInfo.diskTotalBytes > 0 ? "free of \(SystemInfo.formatDiskBytes(systemInfo.diskTotalBytes))" : ""
            )

            if categoriesLoaded {
                stackedBar
                    .padding(.horizontal, 4)
                categoryList
            } else {
                PanelLoadingView(message: "Calculating disk usage…", minHeight: 80)
            }

            VStack(spacing: 0) {
                PanelValueRow(
                    icon: "thermometer.medium",
                    iconColor: diskTempColor,
                    title: "SSD temperature",
                    value: avgDiskTemp > 0 ? "\(diskTempLabel) · \(settings.formatTemperature(avgDiskTemp))" : "No data",
                    valueColor: avgDiskTemp > 0 ? diskTempColor : nil
                )
            }
            .cardBackground(theme)

            if categoriesLoaded && !systemInfo.deniedFolders.isEmpty {
                limitedAccessNotice
            }
        }
    }

    /// Name of the startup volume, "Macintosh HD" on almost every Mac.
    private var volumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
    }

    // MARK: - Status

    private var freeFraction: Double {
        guard systemInfo.diskTotalBytes > 0 else { return 1 }
        return Double(systemInfo.diskAvailableBytes) / Double(systemInfo.diskTotalBytes)
    }

    private var status: (text: String, color: Color) {
        if freeFraction < 0.15 { return ("Running low", theme.orange) }
        return ("Lots of room left", theme.blue)
    }

    // MARK: - Categories

    private var categoriesLoaded: Bool {
        !systemInfo.diskCategories.isEmpty
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let total = Double(max(systemInfo.diskTotalBytes, 1))
            let visible = systemInfo.diskCategories.filter { $0.bytes > 0 && !$0.denied }
            let usable = max(geo.size.width - CGFloat(visible.count) * 2, 0)
            HStack(spacing: 2) {
                ForEach(visible) { cat in
                    Rectangle()
                        .fill(Color(nsColor: cat.color))
                        .frame(width: usable * CGFloat(Double(cat.bytes) / total))
                }
                Spacer(minLength: 0)
            }
            .background(theme.track)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .frame(height: 14)
    }

    private var categoryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(systemInfo.diskCategories.enumerated()), id: \.element.id) { index, cat in
                if index > 0 { CardDivider() }
                HStack(spacing: 10) {
                    Circle()
                        .fill(cat.denied ? theme.track : Color(nsColor: cat.color))
                        .frame(width: 8, height: 8)
                    Text(cat.name)
                        .font(.system(size: 13))
                        .foregroundColor(cat.denied ? theme.textQuaternary : theme.textPrimary)
                    Spacer()
                    if cat.denied {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textQuaternary)
                    }
                    Text(cat.denied ? "Not counted" : SystemInfo.formatDiskBytes(cat.bytes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(cat.denied ? theme.textQuaternary : theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
        .cardBackground(theme)
    }

    // MARK: - Limited Access

    private var limitedAccessNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundColor(theme.textTertiary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Some folders aren’t counted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text("macOS needs your permission before ChillMac can measure \(systemInfo.deniedFolders.sorted().joined(separator: ", ")).")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow access…", action: openPrivacySettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.teal)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.textQuaternary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Disk Temperature

    private var diskTempSensors: [TemperatureSensor] {
        // SSD sensor keys: TH0x (max), TH0a, TH0b
        monitor.sensors.filter { ["TH0x", "TH0a", "TH0b"].contains($0.id) }
    }

    private var avgDiskTemp: Double {
        let sensors = diskTempSensors
        guard !sensors.isEmpty else { return 0 }
        return sensors.map(\.temperature).reduce(0, +) / Double(sensors.count)
    }

    private var diskTempColor: Color {
        if avgDiskTemp >= 55 { return theme.red }
        if avgDiskTemp >= 45 { return theme.orange }
        return theme.green
    }

    private var diskTempLabel: String {
        if avgDiskTemp >= 55 { return "Hot" }
        if avgDiskTemp >= 45 { return "Warm" }
        return "Normal"
    }
}
