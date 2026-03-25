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
        case .low: return "Gentle cooling, minimal noise"
        case .medium: return "Balanced cooling and noise"
        case .high: return "Aggressive cooling, louder"
        case .max: return "Maximum fans at all times"
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

    func formatTemperature(_ celsius: Double) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return String(format: "%.1f°F", f)
        }
        return String(format: "%.1f°C", celsius)
    }
}
