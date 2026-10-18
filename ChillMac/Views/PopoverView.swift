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
    @ObservedObject var updateController: UpdateController
    let helper: HelperConnection
    var onMemoryTap: (() -> Void)?
    var onDiskTap: (() -> Void)?
    var onBatteryTap: (() -> Void)?
    var onCpuTap: (() -> Void)?
    var onTemperatureTap: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    var onShowWelcome: (() -> Void)?

    @State private var appeared = false
    @State private var showingSettings = false
    @State private var liveHeight: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 0
    @State private var activePanelID: String?
    @State private var badgeHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme {
        AppTheme.forScheme(settings.preferredColorScheme ?? colorScheme)
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient

            if showingSettings {
                SettingsView(
                    settings: settings,
                    updateController: updateController,
                    systemInfo: systemInfo,
                    fanMonitor: monitor,
                    cpuInfo: cpuInfo,
                    memoryInfo: memoryInfo,
                    batteryInfo: batteryInfo,
                    onShowWelcome: onShowWelcome
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
        .environment(\.theme, theme)
        .preferredColorScheme(settings.preferredColorScheme)
        // Every content section is gated on `appeared`, so whatever sets it has to be
        // something that cannot be missed. `.popoverDidShow` alone could be: the controller
        // posts it synchronously right after `popover.show(...)`, and if SwiftUI has not
        // mounted this view yet there is no subscriber to receive it, leaving the whole
        // popover at opacity 0 over the gradient forever. `.onAppear` fires on mount by
        // definition, so it cannot lose that race.
        .onAppear { revealContent() }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidShow)) { _ in
            showingSettings = false
            revealContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            appeared = false
            activePanelID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .detailPanelChanged)) { notification in
            activePanelID = notification.userInfo?["panelID"] as? String
        }
    }

    /// Runs the staggered fade-in. Safe to call more than once per open: both triggers fire
    /// when the notification arrives in time, and re-entering during the 50ms window just
    /// restarts a window that has not visibly begun.
    private func revealContent() {
        guard !appeared else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            appeared = true
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerSection

            if let error = monitor.smcError {
                errorSection(error)
            } else {
                ScrollView(.vertical, showsIndicators: settings.showScrollIndicators) {
                    VStack(alignment: .leading, spacing: 14) {
                        if updateController.updateAvailable, let version = updateController.latestVersion {
                            UpdateBannerView(version: version) { onInstallUpdate?() }
                                .opacity(appeared ? 1 : 0)
                                .animation(.easeOut(duration: 0.3), value: appeared)
                        }

                        vitalsCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.easeOut(duration: 0.3).delay(0.05), value: appeared)

                        coolingSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

            footerSection
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(machineLine)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)

                Text(statusTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(theme.textPrimary)

                Text(statusSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            temperatureBadge
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.3), value: appeared)
    }

    /// "MacBook Pro · Apple M3 Max". Stands in for the old Processor card.
    private var machineLine: String {
        [systemInfo.machineModel, systemInfo.chipName]
            .filter { $0 != "..." && !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var peakTemperature: Double? {
        monitor.sensors.map(\.temperature).max()
    }

    /// Shared with the menu bar via `ThermalStatus`, so "warm" means the same in both places.
    private var thermalStatus: ThermalStatus {
        ThermalStatus.forTemperature(peakTemperature ?? 0)
    }

    private var statusTitle: String {
        switch thermalStatus {
        case .good: return "Running cool"
        case .warm: return "Getting warm"
        case .hot: return "Running hot"
        }
    }

    private var statusSubtitle: String {
        guard monitor.helperReady else { return "macOS is handling the fans." }
        let level = settings.performanceLevel
        switch (thermalStatus, settings.coolingMode) {
        case (.good, _):
            return "Nothing to do — fans are quiet."
        case (.warm, .smart):
            return "Smart cooling is on it."
        case (.warm, .manual):
            return "Fans are holding the speed you set."
        case (.warm, .auto):
            return "Smart cooling can bring it down."
        case (.hot, .smart) where level == .high || level == .max:
            return "Fans are working hard to cool it down."
        case (.hot, _):
            return "Try Smart cooling on Cool or Max."
        }
    }

    private var temperatureBadge: some View {
        let color = theme.tempColor(peakTemperature ?? 0)
        return Button(action: { onTemperatureTap?() }) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 20))
                    Text(peakTemperature.map(settings.formatBadgeTemperature) ?? "--")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
                .foregroundColor(color)

                HStack(spacing: 2) {
                    Text("Hottest sensor")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11))
                .foregroundColor(theme.textTertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(activePanelID == "temperature" || badgeHovered ? theme.cardBgHover : theme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { badgeHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: badgeHovered)
    }

    // MARK: - Vitals

    private var vitalsCard: some View {
        let usedMemory = memoryInfo.activeMemory + memoryInfo.wiredMemory + memoryInfo.compressedMemory
        let totalMemory = memoryInfo.totalMemory
        let diskTotal = systemInfo.diskTotalBytes
        let diskUsed = diskTotal - systemInfo.diskAvailableBytes

        let rows: [VitalRow.Model] = [
            .init(id: "cpu", icon: "cpu", label: "CPU", color: theme.teal,
                  fraction: cpuInfo.totalUsage / 100,
                  value: "\(Int(cpuInfo.totalUsage.rounded()))% busy", onTap: onCpuTap),
            .init(id: "memory", icon: "memorychip", label: "Memory", color: theme.green,
                  fraction: totalMemory > 0 ? Double(usedMemory) / Double(totalMemory) : 0,
                  value: "\(Self.wholeGB(usedMemory)) of \(Self.wholeGB(totalMemory)) GB", onTap: onMemoryTap),
            .init(id: "battery", icon: "battery.100", label: "Battery", color: theme.yellow,
                  fraction: Double(batteryInfo.currentCharge) / 100,
                  value: "\(batteryInfo.currentCharge)% · \(batteryState)", onTap: onBatteryTap),
            .init(id: "disk", icon: "internaldrive", label: "Disk", color: theme.blue,
                  fraction: diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0,
                  value: diskTotal > 0 ? "\(SystemInfo.formatDiskBytes(systemInfo.diskAvailableBytes)) free" : "…",
                  onTap: onDiskTap),
        ]

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { CardDivider() }
                VitalRow(model: row, isActive: activePanelID == row.id)
            }
        }
        .padding(.vertical, 4)
        .cardBackground(theme)
    }

    private var batteryState: String {
        if batteryInfo.isCharging { return "charging" }
        if batteryInfo.isPluggedIn { return batteryInfo.currentCharge >= 100 ? "charged" : "plugged in" }
        return "on battery"
    }

    private static func wholeGB(_ bytes: UInt64) -> Int {
        Int((Double(bytes) / 1_073_741_824).rounded())
    }

    // MARK: - Cooling

    private var coolingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: "Cooling")
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.1), value: appeared)

            Group {
                if monitor.helperReady {
                    CoolingCard(monitor: monitor, settings: settings)
                } else {
                    VStack(spacing: 12) {
                        HelperStatusCard(
                            state: monitor.helperState,
                            isBusy: monitor.helperBusy,
                            onInstall: { monitor.installHelper() },
                            onOpenLoginItems: { HelperInstaller.openLoginItemsSettings() },
                            isCollapsed: $settings.helperInviteCollapsed
                        )
                        readOnlyFans
                    }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.easeOut(duration: 0.3).delay(0.15), value: appeared)
        }
    }

    /// Fans while macOS owns them: name, "macOS", RPM. Nothing to adjust.
    private var readOnlyFans: some View {
        VStack(spacing: 0) {
            if monitor.fans.isEmpty {
                FanListPlaceholder(monitor: monitor)
            }
            ForEach(Array(monitor.fans.enumerated()), id: \.element.id) { index, fan in
                if index > 0 { CardDivider() }
                FanRowView(fan: fan, monitor: monitor, mode: nil)
            }
        }
        .cardBackground(theme)
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("SMC Error")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.textPrimary)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            // Drag handle to resize popover
            resizeHandle

            HStack {
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                }
                .buttonStyle(.plain)

                Spacer()

                if settings.showFPS {
                    Text("\(fpsMonitor.fps) FPS")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textQuaternary)
                } else {
                    HStack(spacing: 6) {
                        FanMarkView(size: 16)
                        Text("ChillMac")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textQuaternary)
                    }
                }

                Spacer()

                Button(action: {
                    NotificationCenter.default.post(name: .detailPanelHeightReset, object: nil)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingSettings = true
                    }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textTertiary)

                        if updateController.updateAvailable {
                            Circle()
                                .fill(Color.teal)
                                .frame(width: 7, height: 7)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(theme.footerBg)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.15), value: appeared)
    }

    private var resizeHandle: some View {
        Capsule()
            .fill(theme.textQuaternary.opacity(0.5))
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

// MARK: - Supporting Views

struct CardSectionHeader: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(theme.textTertiary)
            .tracking(1.2)
            .padding(.leading, 4)
            .padding(.top, 4)
    }
}

/// One line of the vitals card: icon, label, bar, value, chevron. Opens a detail panel.
struct VitalRow: View {
    struct Model: Identifiable {
        let id: String
        let icon: String
        let label: String
        let color: Color
        let fraction: Double
        let value: String
        let onTap: (() -> Void)?
    }

    let model: Model
    var isActive = false

    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: { model.onTap?() }) {
            HStack(spacing: 12) {
                Image(systemName: model.icon)
                    .font(.system(size: 17))
                    .foregroundColor(model.color)
                    .frame(width: 22)

                Text(model.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .frame(width: 72, alignment: .leading)

                ProgressBar(fraction: model.fraction, color: model.color)

                Text(model.value)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 108, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered || isActive ? theme.textSecondary : theme.textQuaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isActive || isHovered ? theme.cardBgHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        CardSectionHeader(title: title)
    }
}
