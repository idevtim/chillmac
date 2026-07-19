import Foundation

/// Closed cooling intensity — Native / Balanced / Performance.
enum CoolIntent: String, CaseIterable {
    case native
    case balanced
    case performance

    var label: String {
        switch self {
        case .native: return "Native"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }

    var fullLabel: String {
        label
    }

    var description: String {
        switch self {
        case .native: return "macOS owns fans"
        case .balanced: return "Silent until needed — responsive when hot"
        case .performance: return "Earlier cooling — still silent when cool"
        }
    }

    /// Glyph shown in the Cool mode list (Battery-style).
    var modeGlyph: String {
        switch self {
        case .native: return "○"
        case .balanced: return "◎"
        case .performance: return "◉"
        }
    }

    /// Migrate legacy PerformanceLevel / Quiet raw values stored in UserDefaults.
    static func migrated(fromLegacyRaw raw: String?) -> CoolIntent {
        switch raw {
        case "low", "quiet": return .native
        case "medium", "high", nil: return .balanced
        case "max", "ultra": return .performance
        case "native": return .native
        case "balanced": return .balanced
        case "performance": return .performance
        default: return .balanced
        }
    }
}

/// Idle (macOS auto) vs engaged (app curve) with hysteresis.
enum CoolingEngagementState: Equatable {
    case idle
    case engaged
}

enum CoolingEngagement {
    static func engageCelsius(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 70
        case .balanced: return 65
        case .performance: return 55
        }
    }

    static func releaseCelsius(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 60
        case .balanced: return 55
        case .performance: return 45
        }
    }

    static func dwellSeconds(intent: CoolIntent) -> TimeInterval {
        switch intent {
        case .native: return 25
        case .balanced: return 18
        case .performance: return 12
        }
    }

    /// Soft floor only while engaged — never while idle.
    static func softFloorWhileEngaged(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 0.05
        case .balanced: return 0.15
        case .performance: return 0.25
        }
    }

    static func nextState(
        currentlyEngaged: Bool,
        peakCelsius: Double,
        intent: CoolIntent,
        thermalForceEngage: Bool,
        secondsInBand: TimeInterval
    ) -> CoolingEngagementState {
        if thermalForceEngage {
            return .engaged
        }

        let engage = engageCelsius(intent: intent)
        let release = releaseCelsius(intent: intent)
        let dwell = dwellSeconds(intent: intent)

        if currentlyEngaged {
            if peakCelsius <= release && secondsInBand >= dwell {
                return .idle
            }
            return .engaged
        } else {
            if peakCelsius >= engage && secondsInBand >= min(dwell, 10) {
                return .engaged
            }
            // Fast engage once clearly above threshold (dwell for engage is shorter path)
            if peakCelsius >= engage {
                return .engaged
            }
            return .idle
        }
    }
}
