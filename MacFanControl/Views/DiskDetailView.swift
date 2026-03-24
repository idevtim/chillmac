import SwiftUI

struct DiskDetailView: View {
    @ObservedObject var systemInfo: SystemInfo

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
                Text("Macintosh HD")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        donutSection
                        healthCards
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 370, height: 560)
    }

    // MARK: - Donut Chart

    private var usedBytes: Int64 {
        systemInfo.diskTotalBytes - systemInfo.diskAvailableBytes
    }

    private var donutSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 20)

                // Draw category arcs
                ForEach(Array(arcSegments.enumerated()), id: \.offset) { _, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 2) {
                    Text(SystemInfo.formatDiskBytes(systemInfo.diskAvailableBytes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("of \(SystemInfo.formatDiskBytes(systemInfo.diskTotalBytes)) available")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(12)
            .frame(width: 160, height: 160)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(systemInfo.diskCategories) { cat in
                    DiskLegendRow(
                        color: Color(nsColor: cat.color),
                        label: cat.name,
                        value: SystemInfo.formatDiskBytes(cat.bytes)
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private struct ArcSegment {
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }

    private var arcSegments: [ArcSegment] {
        let total = Double(systemInfo.diskTotalBytes)
        guard total > 0 else { return [] }

        var segments: [ArcSegment] = []
        var cumulative: CGFloat = 0

        for cat in systemInfo.diskCategories {
            let fraction = CGFloat(Double(cat.bytes) / total)
            let end = cumulative + fraction
            segments.append(ArcSegment(start: cumulative, end: end, color: Color(nsColor: cat.color)))
            cumulative = end
        }

        return segments
    }

    // MARK: - Health & Usage Cards

    private var healthCards: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Usage")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(usagePercent)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(usageColor)
                }

                Text(usageDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.07))
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Capacity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(SystemInfo.formatDiskBytes(systemInfo.diskTotalBytes))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }

                Text("Total disk capacity")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
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

    private var usagePercent: String {
        guard systemInfo.diskTotalBytes > 0 else { return "0%" }
        let pct = Double(usedBytes) / Double(systemInfo.diskTotalBytes) * 100
        return String(format: "%.0f%%", pct)
    }

    private var usageColor: Color {
        guard systemInfo.diskTotalBytes > 0 else { return .green }
        let pct = Double(usedBytes) / Double(systemInfo.diskTotalBytes) * 100
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }

    private var usageDescription: String {
        guard systemInfo.diskTotalBytes > 0 else { return "Checking disk..." }
        let pct = Double(usedBytes) / Double(systemInfo.diskTotalBytes) * 100
        if pct >= 90 { return "Disk space is critically low." }
        if pct >= 75 { return "Consider freeing up some space." }
        return "Plenty of storage available."
    }
}

// MARK: - Legend Row

private struct DiskLegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
}
