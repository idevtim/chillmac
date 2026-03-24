import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    let helper: HelperConnection

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
                        // Temperature sensors
                        if !monitor.sensors.isEmpty {
                            SectionHeader(title: "Temperatures")
                            ForEach(monitor.sensors) { sensor in
                                TemperatureRowView(sensor: sensor, settings: settings)
                            }
                            Divider()
                                .padding(.vertical, 4)
                        }

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

                // Temperature unit toggle
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
        .frame(width: 320, height: 400)
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
