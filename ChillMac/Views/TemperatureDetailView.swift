import SwiftUI

struct TemperatureDetailView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @Environment(\.theme) private var theme

    /// Groups the user opened or closed. Static so the choice survives the panel being
    /// rebuilt on every open, for as long as the app runs. Nil until the user first taps,
    /// which is what lets the hottest group open by default.
    private static var sessionExpandedGroups: Set<String>?
    @State private var expandedGroups: Set<String>? = TemperatureDetailView.sessionExpandedGroups

    var body: some View {
        DetailPanelScaffold(title: "Temperatures") {
            Text(intro)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            if monitor.sensors.isEmpty {
                // Sensor keys are discovered by probing the SMC over the first few poll
                // cycles, so the groups fill in progressively.
                if monitor.smcError == nil {
                    PanelLoadingView(message: "Detecting sensors…", minHeight: 120)
                } else {
                    Text("No sensors detected")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textQuaternary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                rangeSection
                groupList
            }
        }
    }

    // MARK: - Summary

    private var temperatures: [Double] { monitor.sensors.map(\.temperature) }
    private var hottest: Double { temperatures.max() ?? 0 }
    private var coolest: Double { temperatures.min() ?? 0 }
    private var average: Double {
        temperatures.isEmpty ? 0 : temperatures.reduce(0, +) / Double(temperatures.count)
    }

    private var intro: String {
        switch ThermalStatus.forTemperature(hottest) {
        case .good:
            return "Everything is in a healthy range. Apple Silicon is designed to run up to ~100°C under load."
        case .warm:
            return "A few sensors are running warm. That is normal under load, and Smart cooling can bring them down."
        case .hot:
            return "Some sensors are running hot. Your Mac may slow itself down to cool off. Try Smart cooling on Cool or Max."
        }
    }

    private var rangeSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            stops: [
                                .init(color: theme.green, location: 0),
                                .init(color: theme.yellow, location: 0.55),
                                .init(color: theme.orange, location: 0.75),
                                .init(color: theme.red, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(height: 8)
                    marker(at: average, width: width)
                    marker(at: hottest, width: width)
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            HStack {
                caption("Coolest", coolest)
                Spacer()
                caption("Avg", average)
                Spacer()
                caption("Hottest", hottest)
            }
        }
        .padding(14)
        .cardBackground(theme)
    }

    private func marker(at celsius: Double, width: CGFloat) -> some View {
        let x = width * CGFloat(min(max(celsius / 100, 0), 1))
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(theme.textPrimary)
            .frame(width: 3, height: 14)
            .offset(x: min(max(x - 1.5, 0), width - 3))
            .animation(.easeInOut(duration: 0.4), value: celsius)
    }

    private func caption(_ label: String, _ celsius: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundColor(theme.textTertiary)
            Text(settings.formatBadgeTemperature(celsius))
                .fontWeight(.semibold)
                .foregroundColor(theme.tempColor(celsius))
        }
        .font(.system(size: 11))
    }

    // MARK: - Groups

    private struct SensorGroup: Identifiable {
        let id: String
        let sensors: [TemperatureSensor]
        var hottest: Double { sensors.map(\.temperature).max() ?? 0 }
    }

    private var groups: [SensorGroup] {
        var remaining = monitor.sensors
        var result: [SensorGroup] = []
        let rules: [(String, (TemperatureSensor) -> Bool)] = [
            ("CPU", { s in s.id.hasPrefix("TC") || s.id.hasPrefix("Tp") || s.label.lowercased().contains("cpu") || s.label.lowercased().contains("processor") }),
            ("GPU", { s in s.id.hasPrefix("TG") || s.id.hasPrefix("Tg") || s.label.lowercased().contains("gpu") }),
            ("Memory", { s in s.id.hasPrefix("TM") || s.id.hasPrefix("Tm") || s.label.lowercased().contains("dram") || s.label.lowercased().contains("memory") }),
            ("Storage", { s in s.id.hasPrefix("TH") || s.id.hasPrefix("Th") || ["ssd", "disk", "nand"].contains { s.label.lowercased().contains($0) } }),
            ("Battery", { s in s.id.hasPrefix("TB") || s.label.lowercased().contains("battery") }),
        ]
        for (name, matches) in rules {
            let members = remaining.filter(matches)
            guard !members.isEmpty else { continue }
            remaining.removeAll(where: matches)
            result.append(SensorGroup(id: name, sensors: members))
        }
        if !remaining.isEmpty {
            result.append(SensorGroup(id: "Other", sensors: remaining))
        }
        return result
    }

    private func isExpanded(_ group: SensorGroup, in all: [SensorGroup]) -> Bool {
        if let expandedGroups { return expandedGroups.contains(group.id) }
        return group.id == all.max(by: { $0.hottest < $1.hottest })?.id
    }

    private func toggle(_ group: SensorGroup, in all: [SensorGroup]) {
        var expanded = expandedGroups ?? Set(all.filter { isExpanded($0, in: all) }.map(\.id))
        if expanded.contains(group.id) {
            expanded.remove(group.id)
        } else {
            expanded.insert(group.id)
        }
        withAnimation(.easeInOut(duration: 0.2)) { expandedGroups = expanded }
        Self.sessionExpandedGroups = expanded
    }

    private var groupList: some View {
        let all = groups
        return VStack(spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.element.id) { index, group in
                if index > 0 { CardDivider() }
                let expanded = isExpanded(group, in: all)
                Button(action: { toggle(group, in: all) }) {
                    HStack(spacing: 10) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.textTertiary)
                            .frame(width: 16)
                        Text(group.id)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        Text(group.sensors.count == 1 ? "1 sensor" : "\(group.sensors.count) sensors")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textQuaternary)
                        Spacer()
                        Text(settings.formatTemperature(group.hottest))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.tempColor(group.hottest))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(spacing: 0) {
                        ForEach(group.sensors) { sensor in
                            sensorRow(sensor, groupName: group.id)
                        }
                    }
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .cardBackground(theme)
    }

    private func sensorRow(_ sensor: TemperatureSensor, groupName: String) -> some View {
        let color = theme.tempColor(sensor.temperature)
        return HStack(spacing: 10) {
            Text(Self.shortLabel(sensor.label, groupName: groupName))
                .font(.system(size: 12))
                .foregroundColor(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            ProgressBar(fraction: sensor.temperature / 100, color: color, height: 4)
                .frame(width: 60)
            Text(settings.formatTemperature(sensor.temperature))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.leading, 42)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
    }

    /// "CPU Performance Core 1" reads as "Performance Core 1" under the CPU heading.
    private static func shortLabel(_ label: String, groupName: String) -> String {
        let prefix = groupName + " "
        guard label.count > prefix.count, label.lowercased().hasPrefix(prefix.lowercased()) else { return label }
        return String(label.dropFirst(prefix.count))
    }
}
