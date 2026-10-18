import SwiftUI

struct CpuDetailView: View {
    @ObservedObject var cpuInfo: CpuInfo
    @ObservedObject var systemInfo: SystemInfo
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme

    /// CpuInfo samples every 2s.
    private static let sampleInterval: Double = 2

    var body: some View {
        DetailPanelScaffold(title: systemInfo.chipName == "..." ? "CPU" : systemInfo.chipName) {
            PanelHero(
                status: status.text,
                statusColor: status.color,
                value: cpuInfo.history.isEmpty ? "—" : "\(Int(cpuInfo.totalUsage.rounded()))%",
                context: "in use",
                trailing: historyCaption
            )

            graphCard
            infoCards
            topConsumersSection
        }
    }

    // MARK: - Status

    private var status: (text: String, color: Color) {
        if cpuInfo.totalUsage < 25 { return ("Light load", theme.teal) }
        if cpuInfo.totalUsage < 70 { return ("Busy", theme.yellow) }
        return ("Working hard", theme.orange)
    }

    private var historyCaption: String? {
        guard cpuInfo.history.count > 1 else { return nil }
        let minutes = max(1, Int((Double(cpuInfo.history.count) * Self.sampleInterval / 60).rounded()))
        return minutes == 1 ? "Last minute" : "Last \(minutes) minutes"
    }

    // MARK: - Graph

    private var graphCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Usage is a delta between two polls, so nothing can be drawn until the second
            // one lands, roughly 4s after the popover first opens.
            if cpuInfo.history.count < 2 {
                PanelLoadingView(message: "Measuring…", minHeight: 72)
            } else {
                CpuGraphView(history: cpuInfo.history, color: theme.teal, fill: theme.soft(theme.teal))
                    .frame(height: 72)
            }

            HStack(spacing: 14) {
                legendItem(color: theme.teal, label: "Apps", value: cpuInfo.userPercent)
                legendItem(color: theme.blue, label: "macOS", value: cpuInfo.systemPercent)
                legendItem(color: theme.track, label: "Idle", value: cpuInfo.idlePercent)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .cardBackground(theme)
    }

    private func legendItem(color: Color, label: String, value: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(theme.textTertiary)
            Text(cpuInfo.history.isEmpty ? "—" : "\(Int(value.rounded()))%")
                .fontWeight(.semibold)
                .foregroundColor(theme.textPrimary)
        }
        .font(.system(size: 12))
    }

    // MARK: - Info Cards

    private var infoCards: some View {
        HStack(spacing: 12) {
            miniCard(
                title: "Temperature",
                value: avgCpuTemp > 0 ? settings.formatTemperature(avgCpuTemp) : "—",
                color: avgCpuTemp > 0 ? theme.tempColor(avgCpuTemp) : theme.textSecondary
            )
            miniCard(title: "On since restart", value: systemInfo.uptime, color: theme.textPrimary)
        }
    }

    private func miniCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(theme.textTertiary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardBackground(theme)
    }

    private var cpuTempSensors: [TemperatureSensor] {
        monitor.sensors.filter { ["TCDX", "TCMb", "TCMz", "TCHP"].contains($0.id) }
    }

    private var avgCpuTemp: Double {
        let sensors = cpuTempSensors
        guard !sensors.isEmpty else { return 0 }
        return sensors.map(\.temperature).reduce(0, +) / Double(sensors.count)
    }

    // MARK: - Top Consumers

    private var topConsumersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: "Using the most")

            VStack(spacing: 0) {
                if cpuInfo.topProcesses.isEmpty {
                    PanelLoadingView(message: "Sampling processes…")
                }
                let top = cpuInfo.topProcesses.map(\.cpuPercent).max() ?? 0
                ForEach(cpuInfo.topProcesses) { proc in
                    TopConsumerRow(
                        icon: proc.icon,
                        name: proc.name,
                        fraction: top > 0 ? proc.cpuPercent / top : 0,
                        value: String(format: "%.1f%%", proc.cpuPercent),
                        color: theme.teal
                    )
                }
            }
            .padding(.vertical, 4)
            .cardBackground(theme)
        }
    }
}

// MARK: - Supporting Views

struct CpuGraphView: View {
    let history: [Double]
    let color: Color
    let fill: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .bottomLeading) {
                if history.count >= 2 {
                    fillPath(data: history, w: w, h: h)
                        .fill(LinearGradient(colors: [fill, fill.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    smoothPath(data: history, w: w, h: h)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(data: [Double], w: CGFloat, h: CGFloat) -> [CGPoint] {
        let step = w / CGFloat(max(data.count - 1, 1))
        return data.enumerated().map { (i, val) in
            CGPoint(x: step * CGFloat(i), y: h - (CGFloat(val) / 100 * h))
        }
    }

    /// Catmull-Rom spline through data points
    private func smoothPath(data: [Double], w: CGFloat, h: CGFloat) -> Path {
        let pts = points(data: data, w: w, h: h)
        return Path { path in
            guard pts.count >= 2 else { return }
            path.move(to: pts[0])
            for i in 0..<(pts.count - 1) {
                let p0 = pts[max(i - 1, 0)]
                let p1 = pts[i]
                let p2 = pts[min(i + 1, pts.count - 1)]
                let p3 = pts[min(i + 2, pts.count - 1)]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
    }

    /// Smooth filled area under the curve
    private func fillPath(data: [Double], w: CGFloat, h: CGFloat) -> Path {
        let pts = points(data: data, w: w, h: h)
        return Path { path in
            guard pts.count >= 2 else { return }
            path.move(to: CGPoint(x: pts[0].x, y: h))
            path.addLine(to: pts[0])
            for i in 0..<(pts.count - 1) {
                let p0 = pts[max(i - 1, 0)]
                let p1 = pts[i]
                let p2 = pts[min(i + 1, pts.count - 1)]
                let p3 = pts[min(i + 2, pts.count - 1)]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
            path.addLine(to: CGPoint(x: pts.last!.x, y: h))
            path.closeSubpath()
        }
    }
}
