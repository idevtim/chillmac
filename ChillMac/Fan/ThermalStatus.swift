import Foundation

/// Shared Good / Warm / Hot vocabulary for popover + menu bar.
enum ThermalStatus: Equatable {
    case unknown
    case good
    case warm
    case hot

    /// Same thresholds as the popover header: Warm ≥ 75°C, Hot ≥ 90°C.
    static func from(peakCelsius: Double) -> ThermalStatus {
        guard peakCelsius > 0 else { return .unknown }
        if peakCelsius >= 90 { return .hot }
        if peakCelsius >= 75 { return .warm }
        return .good
    }

    var label: String {
        switch self {
        case .unknown, .good: return "Good"
        case .warm: return "Warm"
        case .hot: return "Hot"
        }
    }

    /// Menu bar stays quiet unless the machine is Warm or Hot.
    var showsMenuBarTemperature: Bool {
        self == .warm || self == .hot
    }

    /// Compact monochrome readout for the status item (integer degrees).
    static func menuBarTemperatureText(celsius: Double, useFahrenheit: Bool) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return "\(Int(f.rounded()))°"
        }
        return "\(Int(celsius.rounded()))°"
    }
}
