import SwiftUI

struct TemperatureDetailView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings

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
                Text("Temperatures")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Summary card
                        summaryCard

                        // Sensor groups
                        if !cpuSensors.isEmpty {
                            sensorGroup(title: "CPU", sensors: cpuSensors)
                        }
                        if !gpuSensors.isEmpty {
                            sensorGroup(title: "GPU", sensors: gpuSensors)
                        }
                        if !memorySensors.isEmpty {
                            sensorGroup(title: "Memory", sensors: memorySensors)
                        }
                        if !storageSensors.isEmpty {
                            sensorGroup(title: "Storage", sensors: storageSensors)
                        }
                        if !otherSensors.isEmpty {
                            sensorGroup(title: "Other", sensors: otherSensors)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 370, height: 560)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 16) {
            // Max temp
            VStack(spacing: 4) {
                Text("Hottest")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                if let hottest = monitor.sensors.max(by: { $0.temperature < $1.temperature }) {
                    Text(settings.formatTemperature(hottest.temperature))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(colorForTemp(hottest.temperature))
                    Text(hottest.label)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
                .background(Color.white.opacity(0.15))
                .frame(height: 50)

            // Average temp
            VStack(spacing: 4) {
                Text("Average")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                Text(settings.formatTemperature(averageTemp))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(colorForTemp(averageTemp))
                Text("\(monitor.sensors.count) sensors")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Divider()
                .background(Color.white.opacity(0.15))
                .frame(height: 50)

            // Coolest temp
            VStack(spacing: 4) {
                Text("Coolest")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                if let coolest = monitor.sensors.min(by: { $0.temperature < $1.temperature }) {
                    Text(settings.formatTemperature(coolest.temperature))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(colorForTemp(coolest.temperature))
                    Text(coolest.label)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color.white.opacity(0.07))
        .cornerRadius(14)
    }

    // MARK: - Sensor Groups

    private func sensorGroup(title: String, sensors: [TemperatureSensor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.2)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(sensors.enumerated()), id: \.element.id) { index, sensor in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(colorForTemp(sensor.temperature))
                            .frame(width: 8, height: 8)

                        Text(sensor.label)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)

                        Spacer()

                        // Temperature bar
                        GeometryReader { geo in
                            let fraction = min(sensor.temperature / 110, 1.0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForTemp(sensor.temperature).opacity(0.3))
                                .frame(width: geo.size.width)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(colorForTemp(sensor.temperature))
                                        .frame(width: geo.size.width * fraction)
                                }
                        }
                        .frame(width: 60, height: 6)

                        Text(settings.formatTemperature(sensor.temperature))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(colorForTemp(sensor.temperature))
                            .frame(width: 55, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if index < sensors.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
        }
    }

    // MARK: - Sensor Classification

    private var cpuSensors: [TemperatureSensor] {
        monitor.sensors.filter { s in
            let id = s.id
            let label = s.label.lowercased()
            return id.hasPrefix("TC") || id.hasPrefix("Tp") || label.contains("cpu") || label.contains("processor")
        }
    }

    private var gpuSensors: [TemperatureSensor] {
        monitor.sensors.filter { s in
            let id = s.id
            let label = s.label.lowercased()
            return id.hasPrefix("TG") || id.hasPrefix("Tg") || label.contains("gpu")
        }
    }

    private var memorySensors: [TemperatureSensor] {
        monitor.sensors.filter { s in
            let id = s.id
            let label = s.label.lowercased()
            return id.hasPrefix("TM") || id.hasPrefix("Tm") || label.contains("dram") || label.contains("memory")
        }
    }

    private var storageSensors: [TemperatureSensor] {
        monitor.sensors.filter { s in
            let id = s.id
            let label = s.label.lowercased()
            return id.hasPrefix("TH") || id.hasPrefix("Th") || label.contains("ssd") || label.contains("disk") || label.contains("nand")
        }
    }

    private var otherSensors: [TemperatureSensor] {
        let classified = Set(cpuSensors.map(\.id) + gpuSensors.map(\.id) + memorySensors.map(\.id) + storageSensors.map(\.id))
        return monitor.sensors.filter { !classified.contains($0.id) }
    }

    private var averageTemp: Double {
        guard !monitor.sensors.isEmpty else { return 0 }
        return monitor.sensors.map(\.temperature).reduce(0, +) / Double(monitor.sensors.count)
    }

    private func colorForTemp(_ temp: Double) -> Color {
        switch temp {
        case ..<50: return .green
        case 50..<75: return .yellow
        case 75..<90: return .orange
        default: return .red
        }
    }
}
