import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var systemInfo: SystemInfo
    let helper: HelperConnection

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "fan")
                    .foregroundColor(.accentColor)
                Text("Mac Fan Control")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if let error = monitor.smcError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("SMC Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // System info
                        SectionHeader(title: "System")
                        SystemInfoView(systemInfo: systemInfo)

                        Divider()
                            .padding(.vertical, 4)

                        // Fans
                        SectionHeader(title: "Fans")
                        ForEach(monitor.fans) { fan in
                            FanRowView(fan: fan, helper: helper, monitor: monitor)
                        }

                        if monitor.fans.isEmpty {
                            Text("No fans detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }

                        // Temperatures in 2-column grid
                        if !monitor.sensors.isEmpty {
                            Divider()
                                .padding(.vertical, 4)

                            SectionHeader(title: "Temperatures")

                            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                                ForEach(monitor.sensors) { sensor in
                                    TemperatureRowView(sensor: sensor, settings: settings)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)

                Spacer()

                Button(settings.useFahrenheit ? "°F" : "°C") {
                    settings.useFahrenheit.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 380, height: 580)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}
