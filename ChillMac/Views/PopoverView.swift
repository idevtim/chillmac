import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker
    var onOpenSettings: (() -> Void)?

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)

            if let error = monitor.smcError {
                errorSection(error)
            } else {
                coolMenu
            }
        }
        .frame(width: AppSettings.popoverWidth, height: CGFloat(settings.popoverHeight))
        .preferredColorScheme(settings.preferredColorScheme)
    }

    // MARK: - Cool menu (Battery-style)

    private var coolMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            zoneTrack
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            Divider()

            Text("Mode")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(CoolIntent.allCases, id: \.self) { mode in
                modeRow(mode)
            }

            if showsHelperCTA {
                helperCTA
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            if monitor.batterySaverActive, settings.coolMode != .native {
                batterySaverCaption
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Divider()

            footerLink("Settings…", badge: updateChecker.updateAvailable) {
                onOpenSettings?()
            }

            Divider()

            footerLink("Quit ChillMac") {
                NSApp.terminate(nil)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cool")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusSubline)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if showsThrottleCue {
                    throttleCue
                }
                Text(peakTempDisplay)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(currentThermalStatus.emphasisColor)
            }
        }
    }

    private var statusSubline: String {
        var line = currentThermalStatus.label
        if let suffix = ThermalStatus.severitySuffix(thermalState: monitor.processThermalState) {
            line += " · \(suffix)"
        }
        return line
    }

    private var peakTempDisplay: String {
        guard monitor.peakTemperature > 0 else { return "--" }
        return ThermalStatus.menuBarTemperatureText(
            celsius: monitor.peakTemperature,
            useFahrenheit: settings.useFahrenheit
        )
    }

    private var currentThermalStatus: ThermalStatus {
        ThermalStatus.from(peakCelsius: monitor.peakTemperature)
    }

    private var showsThrottleCue: Bool {
        switch monitor.processThermalState {
        case .fair, .serious, .critical: return true
        default: return false
        }
    }

    private var throttleCue: some View {
        let state = monitor.processThermalState
        let filled: Int = {
            switch state {
            case .fair: return 2
            case .serious: return 3
            case .critical: return 4
            default: return 0
            }
        }()
        let label: String = {
            switch state {
            case .fair: return "Fair"
            case .serious: return "Serious"
            case .critical: return "Critical"
            default: return ""
            }
        }()
        let hot = state == .serious || state == .critical

        return HStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(index < filled ? (hot ? Color.red : Color.orange) : Color.primary.opacity(0.12))
                        .frame(width: 3, height: CGFloat([4, 5, 7, 8][index]))
                }
            }
            .frame(height: 8)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hot ? Color.red : Color.orange)
        }
    }

    private var zoneTrack: some View {
        let status = currentThermalStatus
        let position = ThermalStatus.zoneTrackPosition(peakCelsius: monitor.peakTemperature)

        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.green,
                                    Color.green,
                                    Color.orange,
                                    Color.red,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 7)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(status.color, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                        .offset(x: max(0, min(geo.size.width, geo.size.width * position) - 6))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)

            HStack {
                Text("Good")
                Spacer()
                Text("Warm")
                Spacer()
                Text("Hot")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
        }
    }

    private func modeRow(_ mode: CoolIntent) -> some View {
        let selected = settings.coolMode == mode
        return Button {
            selectMode(mode)
        } label: {
            HStack(spacing: 8) {
                Text(mode.modeGlyph)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                    )

                Text(mode.label)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                if mode == .native {
                    Text(mode.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var showsHelperCTA: Bool {
        settings.coolMode != .native && !monitor.helperReady
    }

    private var helperCTA: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Approve ChillMac in Login Items, then install the helper.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Install Helper") { installHelper() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var batterySaverCaption: some View {
        HStack {
            Text("Battery saver — fans on Auto")
                .foregroundStyle(.orange)
            Spacer()
            Button("Override") { settings.forcePerformanceOnBattery = true }
                .buttonStyle(.link)
        }
        .font(.caption)
    }

    private func footerLink(_ title: String, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                if badge {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectMode(_ mode: CoolIntent) {
        if mode != .native, !monitor.helperReady {
            settings.setCoolMode(mode)
            return
        }
        settings.setCoolMode(mode)
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
}

#if DEBUG
#Preview("Popover Cool") {
    AppSettings.shared.appearanceMode = .dark
    AppSettings.shared.setCoolMode(.balanced)
    return PopoverView(
        monitor: PreviewSupport.fanMonitorPerformanceActive,
        settings: AppSettings.shared,
        updateChecker: PreviewSupport.updateChecker,
        onOpenSettings: {}
    )
    .previewHost(scheme: .dark)
}
#endif
