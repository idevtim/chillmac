import ServiceManagement
import SwiftUI

enum PerformanceLevel: String, CaseIterable {
    case low
    case medium
    case high
    case max

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    var description: String {
        switch self {
        case .low: return "Whisper baseline, slow ramp"
        case .medium: return "Balanced baseline and ramp"
        case .high: return "Aggressive baseline, fast ramp"
        case .max: return "Smart max — full speed before throttle"
        }
    }

    var icon: String {
        switch self {
        case .low: return "wind"
        case .medium: return "fan"
        case .high: return "fan.fill"
        case .max: return "flame.fill"
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
        case .off: return "Off"
        case .whenWarm: return "When Warm"
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

    @AppStorage("useFahrenheit") var useFahrenheit = false
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .dark
    @AppStorage("performanceMode") var performanceMode = false
    @AppStorage("performanceLevel") var performanceLevel: PerformanceLevel = .high
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

    func formatTemperature(_ celsius: Double) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return String(format: "%.1f°F", f)
        }
        return String(format: "%.1f°C", celsius)
    }
}
