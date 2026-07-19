import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker
    let systemInfo: SystemInfo
    let fanMonitor: FanMonitor
    let cpuInfo: CpuInfo
    let memoryInfo: MemoryInfo
    let batteryInfo: BatteryInfo
    let onDismiss: () -> Void

    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(DesignSystem.TypeScale.title)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Space.xl)
            .padding(.top, 18)
            .padding(.bottom, DesignSystem.Space.md)

            Form {
                Section("General") {
                    Toggle(isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )) {
                        Label("Launch at Login", systemImage: "sunrise")
                    }
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

                Section("Appearance") {
                    Picker("Appearance", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Temperature") {
                    Picker("Unit", selection: $settings.useFahrenheit) {
                        Text("°C").tag(false)
                        Text("°F").tag(true)
                    }
                    .pickerStyle(.segmented)
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

                Section("Display") {
                    Toggle("Show Temp in Menu Bar", isOn: $settings.showMenuBarTemp)
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        Toggle("Force Cool on Battery", isOn: $settings.forcePerformanceOnBattery)
                        Toggle("Keep Fans on Screen Sleep", isOn: $settings.keepFansOnScreenSleep)
                        Toggle("Keep Fans When Closed on Power", isOn: $settings.keepFansClosedOnPower)
                        Toggle("Show Scrollbars", isOn: $settings.showScrollIndicators)
                        Toggle("Show FPS", isOn: $settings.showFPS)
                        Button("Reset Window Height") {
                            settings.popoverHeight = Double(AppSettings.popoverDefaultHeight)
                            settings.detailPanelHeight = Double(AppSettings.detailPanelDefaultHeight)
                            NotificationCenter.default.post(name: .popoverHeightChanged, object: nil, userInfo: [
                                "height": CGFloat(AppSettings.popoverDefaultHeight)
                            ])
                            NotificationCenter.default.post(name: .detailPanelHeightReset, object: nil)
                        }
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
        .onAppear { updateChecker.performCheck() }
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
        systemInfo: PreviewSupport.systemInfo,
        fanMonitor: PreviewSupport.fanMonitor,
        cpuInfo: PreviewSupport.cpuInfo,
        memoryInfo: PreviewSupport.memoryInfo,
        batteryInfo: PreviewSupport.batteryInfo,
        onDismiss: {}
    )
    .previewHost(scheme: .dark)
}
#endif
