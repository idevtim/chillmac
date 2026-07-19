import ServiceManagement
import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var launchAtLogin: Bool = false

    @AppStorage("useFahrenheit") var useFahrenheit = false
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .dark
    /// Cool engaged (Balanced / Performance). Native sets this false.
    @AppStorage("performanceMode") var performanceMode = false
    @AppStorage("coolIntent") private var coolIntentRaw: String = CoolIntent.balanced.rawValue
    @AppStorage("popoverHeight") var popoverHeight: Double = 320
    @AppStorage("showScrollIndicators") var showScrollIndicators = true

    @AppStorage("detailPanelHeight") var detailPanelHeight: Double = 560

    @AppStorage("batterySaverEnabled") var batterySaverEnabled = true
    @AppStorage("batterySaverThreshold") var batterySaverThreshold = 20
    @AppStorage("forcePerformanceOnBattery") var forcePerformanceOnBattery = false
    @AppStorage("keepFansOnScreenSleep") var keepFansOnScreenSleep = false
    @AppStorage("keepFansClosedOnPower") var keepFansClosedOnPower = false
    @AppStorage("showFPS") var showFPS = false
    @AppStorage("showMenuBarTemp") var showMenuBarTemp = true

    static let popoverWidth: CGFloat = 300
    static let popoverMinHeight: CGFloat = 280
    static let popoverMaxHeight: CGFloat = 480
    static let popoverDefaultHeight: CGFloat = 320
    static let detailPanelMinHeight: CGFloat = 350
    static let detailPanelMaxHeight: CGFloat = 800
    static let detailPanelDefaultHeight: CGFloat = 560

    /// Intent used by the engagement curve while Cool is on (Balanced / Performance).
    var coolIntent: CoolIntent {
        get { CoolIntent.migrated(fromLegacyRaw: coolIntentRaw) }
        set { coolIntentRaw = newValue.rawValue }
    }

    /// Single source of truth for the Cool menu: Native · Balanced · Performance.
    var coolMode: CoolIntent {
        guard performanceMode else { return .native }
        let intent = coolIntent
        return intent == .native ? .native : intent
    }

    /// Selects a Cool menu mode, collapsing the old Cool on/off toggle.
    func setCoolMode(_ mode: CoolIntent) {
        switch mode {
        case .native:
            performanceMode = false
            coolIntentRaw = CoolIntent.native.rawValue
        case .balanced, .performance:
            performanceMode = true
            coolIntentRaw = mode.rawValue
        }
        objectWillChange.send()
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch appearanceMode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    private init() {
        migrateCoolIntentIfNeeded()
        migratePopoverSizeIfNeeded()
        syncLaunchAtLogin()
    }

    private func migrateCoolIntentIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "coolIntent") == nil,
           let legacy = defaults.string(forKey: "performanceLevel") {
            coolIntentRaw = CoolIntent.migrated(fromLegacyRaw: legacy).rawValue
        }

        // Quiet / low → Native; Native means macOS owns fans.
        let migrated = CoolIntent.migrated(fromLegacyRaw: coolIntentRaw)
        if coolIntentRaw != migrated.rawValue {
            coolIntentRaw = migrated.rawValue
        }
        if migrated == .native, performanceMode {
            performanceMode = false
        }
    }

    private func migratePopoverSizeIfNeeded() {
        if popoverHeight > Double(Self.popoverMaxHeight)
            || popoverHeight < Double(Self.popoverMinHeight) {
            popoverHeight = Double(Self.popoverDefaultHeight)
        }
    }

    func syncLaunchAtLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled {
            launchAtLogin = enabled
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            NSLog("Launch at login failed: \(error)")
            syncLaunchAtLogin()
        }
    }

    func formatTemperature(_ celsius: Double) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return String(format: "%.1f°F", f)
        }
        return String(format: "%.1f°C", celsius)
    }
}
