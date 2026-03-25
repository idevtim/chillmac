import SwiftUI

struct MemoryDetailView: View {
    @ObservedObject var memoryInfo: MemoryInfo
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.backgroundGradient

            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Memory")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Donut chart + breakdown — no card background, edge-to-edge
                        donutSection

                        // Pressure & Swap cards — equal height
                        pressureSwapCards

                        // Top consumers with app icons
                        topConsumersSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 370, height: 560)
    }

    // MARK: - Donut Chart

    private var usedMemory: UInt64 {
        memoryInfo.activeMemory + memoryInfo.wiredMemory + memoryInfo.compressedMemory
    }

    private var donutSection: some View {
        HStack(spacing: 14) {
            // Donut chart — pad by half the stroke width so it doesn't clip
            ZStack {
                Circle()
                    .stroke(theme.ringTrack, lineWidth: 20)

                Circle()
                    .trim(from: 0, to: arcEnd(for: .compressed))
                    .stroke(Color.teal, style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0, to: arcEnd(for: .wired))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0, to: arcEnd(for: .active))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(MemoryInfo.formatBytes(memoryInfo.availableMemory))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Text("of \(Int(memoryInfo.totalMemory / 1_073_741_824)) GB available")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(12)
            .frame(width: 160, height: 160)

            VStack(alignment: .leading, spacing: 14) {
                LegendRow(color: .green, label: "Active", value: MemoryInfo.formatBytes(memoryInfo.activeMemory))
                LegendRow(color: .blue, label: "Wired", value: MemoryInfo.formatBytes(memoryInfo.wiredMemory))
                LegendRow(color: .teal, label: "Compressed", value: MemoryInfo.formatBytes(memoryInfo.compressedMemory))
            }
        }
        .padding(.vertical, 4)
    }

    private enum MemoryType { case active, wired, compressed }

    private func arcEnd(for type: MemoryType) -> CGFloat {
        let total = Double(memoryInfo.totalMemory)
        guard total > 0 else { return 0 }
        switch type {
        case .active:
            return CGFloat(Double(memoryInfo.activeMemory) / total)
        case .wired:
            return CGFloat(Double(memoryInfo.activeMemory + memoryInfo.wiredMemory) / total)
        case .compressed:
            return CGFloat(Double(usedMemory) / total)
        }
    }

    // MARK: - Pressure & Swap (equal height)

    private var pressureSwapCards: some View {
        HStack(alignment: .top, spacing: 12) {
            // Pressure card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 14))
                        .foregroundColor(pressureColor)
                    Text("Pressure")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                }

                Text(String(format: "%.0f%%", memoryInfo.pressurePercent))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(pressureColor)

                Text(pressureDescription)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textQuaternary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxHeight: .infinity)
            .background(theme.cardBg)
            .cornerRadius(12)

            // Swap card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 14))
                        .foregroundColor(.cyan)
                    Text("Swap File")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                }

                Text(MemoryInfo.formatBytes(memoryInfo.swapUsed))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)

                Text("Virtual memory on disk")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textQuaternary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxHeight: .infinity)
            .background(theme.cardBg)
            .cornerRadius(12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var pressureColor: Color {
        if memoryInfo.pressurePercent >= 80 { return .red }
        if memoryInfo.pressurePercent >= 60 { return .orange }
        return .green
    }

    private var pressureDescription: String {
        if memoryInfo.pressurePercent >= 80 { return "Memory is under heavy load." }
        if memoryInfo.pressurePercent >= 60 { return "Moderate memory usage." }
        return "Your Mac is ready for more tasks."
    }

    // MARK: - Top Consumers

    private var topConsumersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP CONSUMERS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)
                .padding(.top, 4)

            VStack(spacing: 0) {
                // Header row
                HStack {
                    Text("Application")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textQuaternary)
                    Spacer()
                    Text("Usage")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textQuaternary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ForEach(memoryInfo.topProcesses) { proc in
                    HStack(spacing: 10) {
                        // Real app icon or fallback
                        if let icon = proc.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(5)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green.opacity(0.5))
                                .frame(width: 24, height: 24)
                        }

                        Text(proc.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(MemoryInfo.formatBytes(proc.memoryBytes))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
            .background(theme.cardBgSecondary)
            .cornerRadius(12)
        }
    }
}

// MARK: - Legend Row

private struct LegendRow: View {
    let color: Color
    let label: String
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
            }
        }
    }
}
