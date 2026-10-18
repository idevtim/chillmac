import ServiceManagement
import SwiftUI

enum PerformanceLevel: String, CaseIterable {
    case low
    case medium
    case high
    case max

    var label: String {
        switch self {
        case .low: return "Quiet"
        case .medium: return "Balanced"
        case .high: return "Cool"
        case .max: return "Max"
        }
    }

    var description: String {
        switch self {
        case .low: return "Near-silent. Ramps up gently above 65°C."
        case .medium: return "A soft hum that keeps temps in the 50s–60s."
        case .high: return "Spins up early and fast. Great for long renders."
        case .max: return "Full speed before your Mac would slow itself down."
        }
    }

    var icon: String {
        switch self {
        case .low: return "wind"
        case .medium: return "fan"
        case .high: return "snowflake"
        case .max: return "flame.fill"
        }
    }
}

/// Who drives the fans. One control in the popover replaces what used to be a Performance
/// Mode toggle plus a separate Auto/Manual switch on every fan, which could disagree.
enum CoolingMode: String, CaseIterable {
    /// macOS runs the fans.
    case auto
    /// The performance curve runs the fans (`performanceMode`).
    case smart
    /// Every fan holds a speed the user picked.
    case manual

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .smart: return "Smart"
        case .manual: return "Manual"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "arrow.triangle.2.circlepath"
        case .smart: return "bolt.fill"
        case .manual: return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .auto: return "macOS runs the fans. Quietest option, but your Mac may run warmer under load."
        case .smart: return "ChillMac speeds fans up as temperatures rise, then backs off when things cool down."
        case .manual: return "You pick a fixed speed for each fan. It stays put until you change it."
        }
    }
}

/// How the menu bar reports temperature alongside the fan icon.
enum MenuBarTemperatureMode: String, CaseIterable {
    /// Fan icon only. The default: the menu bar is shared space, so ChillMac does not
    /// take more of it than asked.
    case off
    /// Stays quiet while the Mac is thermally Good, appears once it is Warm or Hot.
    case whenWarm
    /// Always shown.
    case always

    var label: String {
        switch self {
        case .off: return "Never"
        case .whenWarm: return "When warm"
        case .always: return "Always"
        }
    }

    var explanation: String {
        switch self {
        case .off: return "Fan icon only"
        case .whenWarm: return "Only once the Mac is warm or hot"
        case .always: return "Always show the hottest sensor"
        }
    }
}

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
    /// "Not now" on the fan control invitation. Session only: the offer comes back next launch.
    @Published var helperInviteCollapsed = false

    @AppStorage("useFahrenheit") var useFahrenheit = false
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .dark
    @AppStorage("performanceMode") var performanceMode = false
    @AppStorage("performanceLevel") var performanceLevel: PerformanceLevel = .high
    /// Kept in step with `performanceMode` by `FanMonitor.setCoolingMode`, which is the only
    /// thing that should change either.
    @AppStorage("coolingMode") var coolingMode: CoolingMode = .auto
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("popoverHeight") var popoverHeight: Double = 640
    @AppStorage("showScrollIndicators") var showScrollIndicators = true

    @AppStorage("detailPanelHeight") var detailPanelHeight: Double = 560

    // Battery saver — disable performance mode when battery is low
    @AppStorage("batterySaverEnabled") var batterySaverEnabled = true
    @AppStorage("batterySaverThreshold") var batterySaverThreshold = 20  // percent
    @AppStorage("forcePerformanceOnBattery") var forcePerformanceOnBattery = false
    @AppStorage("keepFansOnScreenSleep") var keepFansOnScreenSleep = false
    @AppStorage("showFPS") var showFPS = false
    @AppStorage("menuBarTemperature") var menuBarTemperature: MenuBarTemperatureMode = .off

    /// On AC, keep fans under app control through display sleep, lock and system sleep, so
    /// closing the lid in clamshell does not hand them back to macOS. Off by default: it
    /// leaves fans in manual mode across events where macOS would otherwise take over.
    @AppStorage("keepFansClosedOnPower") var keepFansClosedOnPower = false

    /// Height the main page last fitted to, so the next open starts at that size instead of
    /// the full height and then visibly shrinking. Not persisted and not published.
    var fittedPopoverHeight: CGFloat?

    static let popoverMinHeight: CGFloat = 400
    static let popoverMaxHeight: CGFloat = 900
    static let popoverDefaultHeight: CGFloat = 640
    static let detailPanelMinHeight: CGFloat = 350
    static let detailPanelMaxHeight: CGFloat = 800
    static let detailPanelDefaultHeight: CGFloat = 560

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

    // Manually notify SwiftUI observers after appearance changes.
    // @AppStorage sends objectWillChange *before* the value is written,
    // so SwiftUI can read the stale value. This ensures a second update fires
    // after UserDefaults has committed the new value.
    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    private init() {
        // `coolingMode` is newer than `performanceMode`, so an existing install has only the
        // latter. Smart follows it either way. Manual does not survive a relaunch: fans
        // always start on auto and the manual targets were never persisted.
        if performanceMode {
            coolingMode = .smart
        } else if coolingMode != .auto {
            coolingMode = .auto
        }
        syncLaunchAtLogin()
    }

    /// Reconciles the published flag with launchd's actual view of the login item.
    ///
    /// Called on every popover open. `SMAppService.mainApp.status` round-trips to launchd,
    /// so it stays off the main thread, and the result is only assigned when it differs —
    /// an unconditional write published a change on every open, which `StatusBarController`
    /// observes and turns into popover reconfiguration work.
    func syncLaunchAtLogin() {
        DispatchQueue.global(qos: .utility).async {
            let enabled = (SMAppService.mainApp.status == .enabled)
            DispatchQueue.main.async {
                if self.launchAtLogin != enabled { self.launchAtLogin = enabled }
            }
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

    /// Compact form for the status item, e.g. "78°". No unit letter and no decimal: the
    /// menu bar is shared space and the popover carries the precise reading.
    func formatMenuBarTemperature(_ celsius: Double) -> String {
        let value = useFahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius
        return "\(Int(value.rounded()))°"
    }

    /// Popover headline, e.g. "52.5°". The unit is left to the Settings toggle.
    func formatBadgeTemperature(_ celsius: Double) -> String {
        let value = useFahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius
        return String(format: "%.1f°", value)
    }

    func formatTemperature(_ celsius: Double) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return String(format: "%.1f°F", f)
        }
        return String(format: "%.1f°C", celsius)
    }
}
