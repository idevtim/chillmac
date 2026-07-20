import Cocoa
import Combine
import SwiftUI

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let statusMenu: NSMenu
    private var settingsSub: AnyCancellable?
    private var statusItemSubs = Set<AnyCancellable>()
    private var lastStatusItemSignature: String?

    private var settingsWindow: NSWindow?

    private let systemInfo: SystemInfo
    private let fanMonitor: FanMonitor
    private let updateChecker: UpdateChecker

    init(fanMonitor: FanMonitor, systemInfo: SystemInfo, updateChecker: UpdateChecker) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = NSMenu()
        self.systemInfo = systemInfo
        self.fanMonitor = fanMonitor
        self.updateChecker = updateChecker

        super.init()

        statusMenu.delegate = self
        statusItem.menu = statusMenu

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
        }
        updateStatusItem()

        settingsSub = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.settingsWindow?.contentView?.appearance = AppSettings.shared.nsAppearance
                self.updateStatusItem()
            }
        }

        fanMonitor.$peakTemperature
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &statusItemSubs)
    }

    /// Template fan always; compact temp title only when setting is on and status is Warm/Hot.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let peak = fanMonitor.peakTemperature
        let thermal = ThermalStatus.from(peakCelsius: peak)
        let settings = AppSettings.shared
        let showTemp = settings.showMenuBarTemp && thermal.showsMenuBarTemperature
        let title = showTemp
            ? ThermalStatus.menuBarTemperatureText(celsius: peak, useFahrenheit: settings.useFahrenheit)
            : ""
        let signature = "\(showTemp)|\(title)|\(settings.useFahrenheit)|\(thermal.label)"
        guard signature != lastStatusItemSignature else { return }
        lastStatusItemSignature = signature

        let image = NSImage(systemSymbolName: "fan", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.title = title
        button.imagePosition = showTemp ? .imageLeft : .imageOnly
        button.toolTip = showTemp ? "\(AppBrand.displayName) — \(thermal.label) \(title)" : AppBrand.displayName
        button.setAccessibilityLabel(showTemp ? "\(AppBrand.displayName), \(thermal.label), \(title)" : AppBrand.displayName)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        AppSettings.shared.syncLaunchAtLogin()
        CoolStatusMenuBuilder.rebuild(
            menu: menu,
            monitor: fanMonitor,
            settings: AppSettings.shared,
            updateAvailable: updateChecker.updateAvailable,
            actions: .init(
                target: self,
                selectMode: #selector(selectCoolMode(_:)),
                openSettings: #selector(openSettings(_:)),
                quit: #selector(quitApp(_:)),
                installHelper: #selector(installHelper(_:)),
                overrideBatterySaver: #selector(overrideBatterySaver(_:))
            )
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        fanMonitor.isMenuVisible = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuDidClose(_ menu: NSMenu) {
        fanMonitor.isMenuVisible = false
    }

    // MARK: - Menu actions

    @objc private func selectCoolMode(_ sender: NSMenuItem) {
        guard let mode = CoolStatusMenuBuilder.intent(forTag: sender.tag) else { return }
        AppSettings.shared.setCoolMode(mode)
    }

    @objc private func openSettings(_ sender: Any?) {
        showSettingsWindow()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func installHelper(_ sender: Any?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = HelperInstaller.register()
            HelperInstaller.openApprovalSettingsIfNeeded()
            Thread.sleep(forTimeInterval: 0.5)
            let status = HelperInstaller.checkHelperStatus()
            let ready = HelperReadiness.isReady(status)
            DispatchQueue.main.async {
                guard let self else { return }
                self.fanMonitor.helperReady = ready
                if ready {
                    self.fanMonitor.setupSystemObservers()
                }
            }
        }
    }

    @objc private func overrideBatterySaver(_ sender: Any?) {
        AppSettings.shared.forcePerformanceOnBattery = true
    }

    // MARK: - Settings window

    func showSettingsWindow() {
        if settingsWindow == nil {
            let root = SettingsView(
                settings: AppSettings.shared,
                updateChecker: updateChecker,
                fanMonitor: fanMonitor,
                systemInfo: systemInfo
            )
            let hosting = NSHostingController(rootView: AppearanceHost(content: root))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "\(AppBrand.displayName) Settings"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 380, height: 560))
            window.center()
            settingsWindow = window
        }

        settingsWindow?.contentView?.appearance = AppSettings.shared.nsAppearance
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
