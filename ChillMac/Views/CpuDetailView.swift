import SwiftUI

struct CpuDetailView: View {
    @ObservedObject var cpuInfo: CpuInfo
    @ObservedObject var systemInfo: SystemInfo
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme
    @State private var panelHeight: CGFloat = CGFloat(AppSettings.shared.detailPanelHeight)

    var body: some View {
        ZStack {
            theme.backgroundGradient

            VStack(alignment: .leading, spacing: 0) {
                Text(systemInfo.chipName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: settings.showScrollIndicators) {
                    VStack(spacing: 16) {
                        graphSection
                        infoCards
                        topConsumersSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                PanelResizeHandle(panelHeight: $panelHeight) {
                    AppSettings.shared.detailPanelHeight = Double(panelHeight)
                }
            }
        }
        .frame(width: 370, height: panelHeight)
    }

    // MARK: - Graph + Breakdown

    private var graphSection: some View {
        HStack(alignment: .top, spacing: 14) {
            // Line chart
            VStack(alignment: .leading, spacing: 4) {
                CpuGraphView(history: cpuInfo.history, userHistory: cpuInfo.userHistory, systemHistory: cpuInfo.systemHistory)
                    .frame(height: 100)
            }
            .frame(maxWidth: .infinity)

            // Breakdown
            VStack(alignment: .leading, spacing: 12) {
                UsageRow(
                    color: .teal,
                    value: String(format: "%.1f %%", 100 - cpuInfo.totalUsage),
                    label: "Available"
                )
                UsageRow(
                    color: .blue,
                    value: String(format: "%.1f %%", cpuInfo.userPercent),
                    label: "User"
                )
                UsageRow(
                    color: .orange,
                    value: String(format: "%.1f %%", cpuInfo.systemPercent),
                    label: "System"
                )
            }
            .frame(width: 100)
        }
        .padding(16)
        .background(theme.cardBg)
        .cornerRadius(14)
    }

    // MARK: - Info Cards

    private var infoCards: some View {
        HStack(alignment: .top, spacing: 12) {
            // Uptime
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(.mint)
                    Text("Uptime")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                }

                Text(systemInfo.uptime)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.mint)

                Text(uptimeDescription)
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

            // CPU Temperature
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 14))
                        .foregroundColor(cpuTempColor)
                    Text("CPU Temp")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                }

                Text(settings.formatTemperature(avgCpuTemp))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(cpuTempColor)

                Text(cpuTempDescription)
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

    private var uptimeDescription: String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86400
        if days >= 7 { return "Consider restarting." }
        if days >= 1 { return "System running normally." }
        return "Recently started."
    }

    private var cpuTempSensors: [TemperatureSensor] {
        monitor.sensors.filter { ["TCDX", "TCMb", "TCMz", "TCHP"].contains($0.id) }
    }

    private var avgCpuTemp: Double {
        let sensors = cpuTempSensors
        guard !sensors.isEmpty else { return 0 }
        return sensors.map(\.temperature).reduce(0, +) / Double(sensors.count)
    }

    private var cpuTempColor: Color {
        if avgCpuTemp >= 90 { return .red }
        if avgCpuTemp >= 70 { return .orange }
        return .green
    }

    private var cpuTempDescription: String {
        guard avgCpuTemp > 0 else { return "No data available." }
        if avgCpuTemp >= 90 { return "CPU is running hot." }
        if avgCpuTemp >= 70 { return "Warm but within range." }
        return "Within normal range."
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
                HStack {
                    Text("Application")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textQuaternary)
                    Spacer()
                    Text("CPU %")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textQuaternary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ForEach(cpuInfo.topProcesses) { proc in
                    HStack(spacing: 10) {
                        if let icon = proc.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(5)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.teal.opacity(0.5))
                                .frame(width: 24, height: 24)
                        }

                        Text(proc.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(String(format: "%.1f", proc.cpuPercent))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.teal)
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

// MARK: - Supporting Views

private struct UsageRow: View {
    let color: Color
    let value: String
    let label: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
            }
        }
    }
}

struct CpuGraphView: View {
    let history: [Double]
    let userHistory: [Double]
    let systemHistory: [Double]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .bottomLeading) {
                // Grid lines
                ForEach(0..<4) { i in
                    let y = h * CGFloat(i) / 3
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(theme.gridLine, lineWidth: 0.5)
                }

                // User fill + line
                if userHistory.count >= 2 {
                    fillPath(data: userHistory, w: w, h: h)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    smoothPath(data: userHistory, w: w, h: h)
                        .stroke(Color.blue, lineWidth: 1.5)
                }

                // System fill + line
                if systemHistory.count >= 2 {
                    fillPath(data: systemHistory, w: w, h: h)
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .orange.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    smoothPath(data: systemHistory, w: w, h: h)
                        .stroke(Color.orange, lineWidth: 1.5)
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
