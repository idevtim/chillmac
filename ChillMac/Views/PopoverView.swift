import Combine
import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var systemInfo: SystemInfo
    @ObservedObject var batteryInfo: BatteryInfo
    @ObservedObject var cpuInfo: CpuInfo
    @ObservedObject var memoryInfo: MemoryInfo
    @ObservedObject var fpsMonitor: DisplayFPSMonitor
    @ObservedObject var updateChecker: UpdateChecker
    let helper: HelperConnection
    var onMemoryTap: (() -> Void)?
    var onDiskTap: (() -> Void)?
    var onBatteryTap: (() -> Void)?
    var onCpuTap: (() -> Void)?
    var onTemperatureTap: (() -> Void)?

    @State private var showingSettings = false
    @State private var liveHeight: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 0
    @State private var activePanelID: String?

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)

            if showingSettings {
                SettingsView(
                    settings: settings,
                    updateChecker: updateChecker,
                    systemInfo: systemInfo,
                    fanMonitor: monitor,
                    cpuInfo: cpuInfo,
                    memoryInfo: memoryInfo,
                    batteryInfo: batteryInfo
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingSettings = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 420, height: liveHeight > 0 ? liveHeight : CGFloat(settings.popoverHeight))
        .preferredColorScheme(settings.preferredColorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidShow)) { _ in
            showingSettings = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            activePanelID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .detailPanelChanged)) { notification in
            activePanelID = notification.userInfo?["panelID"] as? String
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let error = monitor.smcError {
                errorSection(error)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    statusHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    Form {
                        coolSection
                        fansSection
                        systemSection
                    }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(settings.showScrollIndicators ? .automatic : .hidden)
                }
            }

            footerSection
        }
    }

    // MARK: - Quiet status (unboxed section header)

    private var statusHeader: some View {
        HStack(spacing: 0) {
            Text(currentThermalStatus.label)
                .foregroundStyle(currentThermalStatus.emphasisColor)
            Text(" · ")
                .foregroundStyle(.tertiary)
            Text(systemInfo.machineModel)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .textCase(nil)
    }

    private var currentThermalStatus: ThermalStatus {
        guard !monitor.sensors.isEmpty,
              let maxTemp = monitor.sensors.map(\.temperature).max() else {
            return .unknown
        }
        return ThermalStatus.from(peakCelsius: maxTemp)
    }

    // MARK: - Cool

    @ViewBuilder
    private var coolSection: some View {
        Section {
            Toggle(isOn: $settings.performanceMode) {
                Text("Cool")
            }
            .disabled(!monitor.helperReady)

            if !monitor.helperReady {
                Text("Approve ChillMac in Login Items, then install the helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Install Helper") { installHelper() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if settings.performanceMode {
                Picker("Intent", selection: coolIntentBinding) {
                    ForEach(CoolIntent.allCases, id: \.self) { intent in
                        Text(intent.label).tag(intent)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if monitor.batterySaverActive {
                    HStack {
                        Text("Battery saver — fans on Auto")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Override") { settings.forcePerformanceOnBattery = true }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                }
            }
        } footer: {
            Text(coolStatusLine)
                .foregroundStyle(.secondary)
        }
    }

    private var coolIntentBinding: Binding<CoolIntent> {
        Binding(
            get: { settings.coolIntent },
            set: { settings.coolIntent = $0 }
        )
    }

    private var coolStatusLine: String {
        if !monitor.helperReady {
            return "Helper required to control fans"
        }
        if !settings.performanceMode {
            return "macOS controls fans"
        }
        if monitor.coolingEngaged {
            return "Cooling · \(settings.formatTemperature(monitor.peakTemperature)) · \(settings.coolIntent.fullLabel)"
        }
        return "Fans on Auto"
    }

    // MARK: - Fans

    @ViewBuilder
    private var fansSection: some View {
        Section("Fans") {
            if monitor.fans.isEmpty {
                Text("No fans detected")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(monitor.fans, id: \.id) { fan in
                    FanRowView(fan: fan, helper: helper, monitor: monitor)
                }
            }
        }
    }

    // MARK: - System (Form rows — Settings kinship)

    @ViewBuilder
    private var systemSection: some View {
        Section("System") {
            systemRow("Memory", value: String(format: "%.0f%%", memoryInfo.pressurePercent), active: activePanelID == "memory", action: onMemoryTap)
            systemRow("CPU", value: String(format: "%.0f%%", cpuInfo.totalUsage), active: activePanelID == "cpu", action: onCpuTap)
            systemRow("Battery", value: "\(batteryInfo.currentCharge)%", active: activePanelID == "battery", action: onBatteryTap)
            systemRow("Disk", value: systemInfo.diskUsage, active: activePanelID == "disk", action: onDiskTap)
            systemRow("Temp", value: maxTempDisplay, active: activePanelID == "temperature", action: onTemperatureTap)
        }
    }

    private func systemRow(_ title: String, value: String, active: Bool, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary)
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .listRowBackground(active ? Color.accentColor.opacity(0.12) : nil)
        .disabled(action == nil)
    }

    private var maxTempDisplay: String {
        guard !monitor.sensors.isEmpty,
              let maxTemp = monitor.sensors.map(\.temperature).max() else {
            return "--"
        }
        return settings.formatTemperature(maxTemp)
    }

    private func installHelper() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = HelperInstaller.register()
            HelperInstaller.openApprovalSettingsIfNeeded()
            Thread.sleep(forTimeInterval: 0.5)
            let status = HelperInstaller.checkHelperStatus()
            let ready = HelperReadiness.isReady(status)
            DispatchQueue.main.async {
                monitor.helperReady = ready
                if ready {
                    monitor.setupSystemObservers()
                }
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: DesignSystem.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("SMC Error")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Space.xxl)
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            resizeHandle
            HStack {
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if settings.showFPS {
                    Text("\(fpsMonitor.fps) FPS")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("ChillMac")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    NotificationCenter.default.post(name: .detailPanelHeightReset, object: nil)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingSettings = true
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                        if updateChecker.updateAvailable {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Space.xl)
            .padding(.vertical, DesignSystem.Space.md)
        }
        .background(.bar)
    }

    private var resizeHandle: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 36, height: 4)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if liveHeight == 0 {
                            liveHeight = CGFloat(settings.popoverHeight)
                            dragStartHeight = liveHeight
                        }
                        let delta = value.location.y - value.startLocation.y
                        let newHeight = min(max(dragStartHeight + delta, AppSettings.popoverMinHeight), AppSettings.popoverMaxHeight)
                        liveHeight = newHeight
                        NotificationCenter.default.post(name: .popoverHeightChanged, object: nil, userInfo: ["height": newHeight])
                    }
                    .onEnded { _ in
                        settings.popoverHeight = Double(liveHeight)
                        liveHeight = 0
                        dragStartHeight = 0
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
    }
}

#if DEBUG
#Preview("Popover Cool") {
    AppSettings.shared.appearanceMode = .dark
    AppSettings.shared.performanceMode = true
    AppSettings.shared.coolIntent = .balanced
    return PopoverView(
        monitor: PreviewSupport.fanMonitorPerformanceActive,
        settings: AppSettings.shared,
        systemInfo: PreviewSupport.systemInfo,
        batteryInfo: PreviewSupport.batteryInfo,
        cpuInfo: PreviewSupport.cpuInfo,
        memoryInfo: PreviewSupport.memoryInfo,
        fpsMonitor: PreviewSupport.fpsMonitor,
        updateChecker: PreviewSupport.updateChecker,
        helper: PreviewSupport.helper
    )
    .previewHost(scheme: .dark)
}
#endif
