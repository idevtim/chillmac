import SwiftUI

struct MemoryDetailView: View {
    @ObservedObject var memoryInfo: MemoryInfo
    @Environment(\.theme) private var theme

    var body: some View {
        DetailPanelScaffold(title: "Memory") {
            PanelHero(
                status: status.text,
                statusColor: status.color,
                value: Self.formatGB(memoryInfo.availableMemory),
                context: "free of \(Int(Double(memoryInfo.totalMemory) / 1_073_741_824)) GB"
            )

            VStack(alignment: .leading, spacing: 12) {
                stackedBar
                legend
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                PanelValueRow(
                    icon: "gauge.with.dots.needle.33percent",
                    iconColor: pressureColor,
                    title: "Pressure",
                    value: "\(pressureLabel) · \(Int(memoryInfo.pressurePercent.rounded()))%",
                    valueColor: pressureColor
                )
                CardDivider()
                PanelValueRow(
                    icon: "arrow.up.arrow.down",
                    iconColor: theme.teal,
                    title: "Overflow to disk",
                    caption: "Swap — slower than memory",
                    value: MemoryInfo.formatBytes(memoryInfo.swapUsed)
                )
            }
            .cardBackground(theme)

            topConsumersSection
        }
    }

    // MARK: - Status

    private var status: (text: String, color: Color) {
        if memoryInfo.pressurePercent > 90 { return ("Out of memory", theme.red) }
        if memoryInfo.pressurePercent > 70 { return ("Getting tight", theme.yellow) }
        return ("Plenty to spare", theme.green)
    }

    private var pressureLabel: String {
        if memoryInfo.pressurePercent > 90 { return "High" }
        if memoryInfo.pressurePercent > 70 { return "Elevated" }
        return "Normal"
    }

    private var pressureColor: Color { status.color }

    /// "29.7 GB": one decimal is plenty at panel scale.
    private static func formatGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    // MARK: - Breakdown

    private var segments: [(label: String, bytes: UInt64, color: Color)] {
        [
            ("Used by apps", memoryInfo.activeMemory, theme.green),
            ("Reserved by macOS", memoryInfo.wiredMemory, theme.blue),
            ("Compressed to save space", memoryInfo.compressedMemory, theme.teal),
        ]
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let total = Double(max(memoryInfo.totalMemory, 1))
            let visible = segments.filter { $0.bytes > 0 }
            let gaps = CGFloat(visible.count) * 2
            let usable = max(geo.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(visible, id: \.label) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: usable * CGFloat(Double(segment.bytes) / total))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.track)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .frame(height: 14)
        .animation(.easeInOut(duration: 0.4), value: memoryInfo.activeMemory)
    }

    private var legend: some View {
        let items = segments.map { ($0.label, MemoryInfo.formatBytes($0.bytes), $0.color) }
            + [("Free", MemoryInfo.formatBytes(memoryInfo.availableMemory), theme.track)]
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: 10) {
            ForEach(items, id: \.0) { label, value, color in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Top Consumers

    private var topConsumersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: "Using the most")

            VStack(spacing: 0) {
                if memoryInfo.topProcesses.isEmpty {
                    PanelLoadingView(message: "Sampling processes…")
                }
                let top = Double(memoryInfo.topProcesses.map(\.memoryBytes).max() ?? 0)
                ForEach(memoryInfo.topProcesses) { proc in
                    TopConsumerRow(
                        icon: proc.icon,
                        name: proc.name,
                        fraction: top > 0 ? Double(proc.memoryBytes) / top : 0,
                        value: MemoryInfo.formatBytes(proc.memoryBytes),
                        color: theme.green
                    )
                }
            }
            .padding(.vertical, 4)
            .cardBackground(theme)
        }
    }
}
