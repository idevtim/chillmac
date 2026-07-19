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

    @State private var appeared = false
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
            appeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            appeared = false
            activePanelID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .detailPanelChanged)) { notification in
            activePanelID = notification.userInfo?["panelID"] as? String
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerSection

            if let error = monitor.smcError {
                errorSection(error)
            } else {
                ScrollView(.vertical, showsIndicators: settings.showScrollIndicators) {
                    VStack(spacing: DesignSystem.Space.md) {
                        coolHeroCard
                        fansSection
                        systemGlance
                    }
                    .padding(.horizontal, DesignSystem.Space.lg)
                    .padding(.top, DesignSystem.Space.md)
                    .padding(.bottom, DesignSystem.Space.lg)
                }
            }

            footerSection
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSystem.Space.sm) {
                    Text("System Temp:")
                        .font(DesignSystem.TypeScale.title)
                        .foregroundStyle(.primary)
                    Text(currentThermalStatus.label)
                        .font(DesignSystem.TypeScale.title)
                        .foregroundStyle(currentThermalStatus.color)
                }
                Text(systemInfo.machineModel)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "laptopcomputer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignSystem.Space.xl)
        .padding(.top, 18)
        .padding(.bottom, DesignSystem.Space.md)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: appeared)
    }

    private var currentThermalStatus: ThermalStatus {
        guard !monitor.sensors.isEmpty,
              let maxTemp = monitor.sensors.map(\.temperature).max() else {
            return .unknown
        }
        return ThermalStatus.from(peakCelsius: maxTemp)
    }

    // MARK: - Cool hero

    private var coolHeroCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Space.sm) {
            HStack {
                Text("Cool")
                    .font(DesignSystem.TypeScale.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Toggle(isOn: $settings.performanceMode) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!monitor.helperReady)
            }

            if !monitor.helperReady {
                Text("Helper required to control fans. Approve ChillMac in Login Items, then Install.")
                    .font(DesignSystem.TypeScale.caption)
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

                Text(coolStatusLine)
                    .font(DesignSystem.TypeScale.caption)
                    .foregroundStyle(.secondary)

                if monitor.batterySaverActive {
                    HStack {
                        Image(systemName: "battery.25")
                        Text("Battery saver — fans on Auto")
                            .font(DesignSystem.TypeScale.caption)
                        Spacer()
                        Button("Override") { settings.forcePerformanceOnBattery = true }
                            .buttonStyle(.link)
                    }
                }

                if monitor.coolingEngaged {
                    HStack(spacing: DesignSystem.Space.md) {
                        Label(settings.formatTemperature(monitor.peakTemperature), systemImage: "thermometer.medium")
                            .font(DesignSystem.TypeScale.mono)
                            .foregroundStyle(ThermalStatus.color(forCelsius: monitor.peakTemperature))
                        Text(String(format: "%.0f%%", monitor.performanceCurvePercent))
                            .font(DesignSystem.TypeScale.mono)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                Text("macOS controls fans")
                    .font(DesignSystem.TypeScale.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .chillCard()
        .opacity(appeared ? 1 : 0)
    }

    private var coolIntentBinding: Binding<CoolIntent> {
        Binding(
            get: { settings.coolIntent },
            set: { settings.coolIntent = $0 }
        )
    }

    private var coolStatusLine: String {
        if monitor.coolingEngaged {
            return "Cooling — \(settings.coolIntent.fullLabel)"
        }
        return "\(settings.coolIntent.fullLabel) — fans on Auto"
    }

    // MARK: - Fans

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Space.sm) {
            Text("Fans")
                .chillSectionHeader()

            ForEach(Array(monitor.fans.enumerated()), id: \.element.id) { _, fan in
                FanRowView(fan: fan, helper: helper, monitor: monitor)
            }

            if monitor.fans.isEmpty {
                HStack {
                    Image(systemName: "fan.slash")
                    Text("No fans detected")
                }
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .chillCard()
            }
        }
    }

    // MARK: - System glance

    private var systemGlance: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Space.sm) {
            Text("System")
                .chillSectionHeader()

            HStack(spacing: DesignSystem.Space.sm) {
                glanceChip(
                    title: String(format: "%.0f%%", memoryInfo.pressurePercent),
                    subtitle: "Mem",
                    isActive: activePanelID == "memory",
                    action: onMemoryTap
                )
                glanceChip(
                    title: String(format: "%.0f%%", cpuInfo.totalUsage),
                    subtitle: "CPU",
                    isActive: activePanelID == "cpu",
                    action: onCpuTap
                )
                glanceChip(
                    title: "\(batteryInfo.currentCharge)%",
                    subtitle: "Batt",
                    isActive: activePanelID == "battery",
                    action: onBatteryTap
                )
            }

            HStack(spacing: DesignSystem.Space.sm) {
                glanceChip(
                    title: systemInfo.diskUsage,
                    subtitle: "Disk",
                    isActive: activePanelID == "disk",
                    action: onDiskTap
                )
                glanceChip(
                    title: maxTempDisplay,
                    subtitle: "Temp",
                    isActive: activePanelID == "temperature",
                    action: onTemperatureTap
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func glanceChip(title: String, subtitle: String, isActive: Bool, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.TypeScale.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DesignSystem.TypeScale.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                            .strokeBorder(isActive ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 40))
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
                        Image(systemName: "gearshape.fill")
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
    AppSettings.shared.coolIntent = .performance
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
    .onAppear { PreviewSupport.triggerPopoverAppeared() }
}
#endif
