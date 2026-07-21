import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var fanMonitor: FanMonitor
    let systemInfo: SystemInfo

    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("General") {
                    Toggle(isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )) {
                        Label("Launch at Login", systemImage: "sunrise")
                    }

                    Toggle("Show Temp in Menu Bar", isOn: $settings.showMenuBarTemp)

                    Picker("Temperature", selection: $settings.useFahrenheit) {
                        Text("°C").tag(false)
                        Text("°F").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Picker("Appearance", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Cool") {
                    LabeledContent("Default mode") {
                        Text(settings.coolMode.label)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Keep Cool When Closed on AC", isOn: $settings.keepFansClosedOnPower)
                }

                Section("Battery Saver") {
                    Toggle("Enable Battery Saver", isOn: $settings.batterySaverEnabled)
                    if settings.batterySaverEnabled {
                        HStack {
                            Text("Threshold")
                            Spacer()
                            Text("\(settings.batterySaverThreshold)%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.batterySaverThreshold) },
                                set: { settings.batterySaverThreshold = Int($0) }
                            ),
                            in: 5...50,
                            step: 5
                        )
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fan control helper")
                        Text("Not needed for Native. Required for Max & Ultra.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Status") {
                        Text(helperStatusLabel)
                            .foregroundStyle(fanMonitor.helperReady ? .green : .orange)
                    }
                    Button("Manage in Login Items…") {
                        HelperInstaller.openLoginItemsSettings()
                    }
                } header: {
                    Text("Helper")
                }

                Section("Updates") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Current Version")
                            Text("v\(updateChecker.currentVersion)")
                                .foregroundStyle(.secondary)
                                .font(DesignSystem.TypeScale.caption)
                        }
                        Spacer()
                        Button("Check") { updateChecker.performCheck() }
                            .disabled(updateChecker.isChecking)
                    }
                    if updateChecker.updateAvailable, let version = updateChecker.latestVersion {
                        HStack {
                            Text("v\(version) Available")
                            Spacer()
                            if let url = updateChecker.downloadURL ?? updateChecker.releaseURL {
                                Button("Download") { NSWorkspace.shared.open(url) }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                        }
                    } else if updateChecker.hasChecked && !updateChecker.updateAvailable {
                        Label("You're up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        Toggle("Force Cool on Battery", isOn: $settings.forcePerformanceOnBattery)
                        Toggle("Keep Fans on Screen Sleep", isOn: $settings.keepFansOnScreenSleep)
                        Toggle("Show Scrollbars", isOn: $settings.showScrollIndicators)
                        Toggle("Show FPS", isOn: $settings.showFPS)
                    }
                }

                Section("Diagnostics") {
                    Button("Export Diagnostics…") {
                        DiagnosticExporter.export(
                            logger: DiagnosticLogger.shared,
                            systemInfo: systemInfo
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(DesignSystem.TypeScale.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.bottom, DesignSystem.Space.md)
        }
        .frame(minWidth: 360, idealWidth: 380, minHeight: 420)
        .onAppear { updateChecker.performCheck() }
    }

    private var helperStatusLabel: String {
        fanMonitor.helperReady ? "Ready" : "Not ready"
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { settings.appearanceMode },
            set: { settings.setAppearanceMode($0) }
        )
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(
        settings: AppSettings.shared,
        updateChecker: PreviewSupport.updateChecker,
        fanMonitor: PreviewSupport.fanMonitor,
        systemInfo: PreviewSupport.systemInfo
    )
    .previewHost(scheme: .dark)
}
#endif
