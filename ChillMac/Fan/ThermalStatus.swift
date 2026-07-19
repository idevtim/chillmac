import SwiftUI

/// Shared Good / Warm / Hot vocabulary for Cool menu + menu bar.
enum ThermalStatus: Equatable {
    case unknown
    case good
    case warm
    case hot

    /// Same thresholds as the Cool zone track: Warm ≥ 75°C, Hot ≥ 90°C.
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

    /// Saturated hue only when Warm/Hot — Good stays calm secondary.
    var emphasisColor: Color {
        switch self {
        case .unknown, .good: return Color.secondary
        case .warm: return .orange
        case .hot: return .red
        }
    }

    /// Detail-row mapping still uses semantic ramps (green→orange→red).
    var color: Color {
        switch self {
        case .unknown, .good: return .green
        case .warm: return .orange
        case .hot: return .red
        }
    }

    /// Marker position 0…1 on the Cool zone track (prototype: 30–100°C mapped).
    static func zoneTrackPosition(peakCelsius: Double) -> Double {
        let x = max(30.0, min(100.0, peakCelsius))
        if x <= 75 { return ((x - 30) / 45) * 0.55 }
        if x <= 90 { return 0.55 + ((x - 75) / 15) * 0.20 }
        return 0.75 + ((x - 90) / 10) * 0.25
    }

    /// Appends Limited / Throttled from ProcessInfo thermal state when not nominal.
    static func severitySuffix(thermalState: ProcessInfo.ThermalState) -> String? {
        switch thermalState {
        case .fair: return "Limited"
        case .serious, .critical: return "Throttled"
        default: return nil
        }
    }

    /// Compact monochrome readout for the status item (integer degrees).
    static func menuBarTemperatureText(celsius: Double, useFahrenheit: Bool) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return "\(Int(f.rounded()))°"
        }
        return "\(Int(celsius.rounded()))°"
    }

    static func color(forCelsius celsius: Double) -> Color {
        from(peakCelsius: celsius).color
    }
}
