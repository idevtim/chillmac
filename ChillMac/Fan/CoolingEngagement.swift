import Foundation

/// Closed cooling intensity — Native / Max / Ultra.
enum CoolIntent: String, CaseIterable {
    case native
    case max
    case ultra

    var label: String {
        switch self {
        case .native: return "Native"
        case .max: return "Max"
        case .ultra: return "Ultra"
        }
    }

    var fullLabel: String {
        label
    }

    var description: String {
        switch self {
        case .native: return "macOS owns fans"
        case .max: return "Silent until needed — responsive when hot"
        case .ultra: return "Earlier cooling — still silent when cool"
        }
    }

    /// Glyph shown in the Cool mode list (Battery-style).
    var modeGlyph: String {
        switch self {
        case .native: return "○"
        case .max: return "◎"
        case .ultra: return "◉"
        }
    }

    /// SF Symbol inside the mode circle (nil = empty outline for Native).
    var modeSystemImage: String? {
        switch self {
        case .native: return nil
        case .max: return "fan"
        case .ultra: return "fan.fill"
        }
    }

    /// One-shot map from the old `performanceLevel` key (max/ultra were both aggressive).
    static func fromLegacyPerformanceLevel(_ raw: String) -> CoolIntent {
        switch raw {
        case "low": return .native
        case "medium", "high": return .max
        case "max", "ultra": return .ultra
        default: return .max
        }
    }

    /// Normalize stored `coolIntent` (and similar) strings, including Cool-menu renames.
    static func migrated(fromLegacyRaw raw: String?) -> CoolIntent {
        switch raw {
        case "low", "quiet": return .native
        case "medium", "high", "balanced", nil: return .max
        case "performance": return .ultra
        case "max": return .max
        case "ultra": return .ultra
        case "native": return .native
        default: return .max
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
        case .max: return 65
        case .ultra: return 55
        }
    }

    static func releaseCelsius(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 60
        case .max: return 55
        case .ultra: return 45
        }
    }

    static func dwellSeconds(intent: CoolIntent) -> TimeInterval {
        switch intent {
        case .native: return 25
        case .max: return 18
        case .ultra: return 12
        }
    }

    /// Soft floor only while engaged — never while idle.
    static func softFloorWhileEngaged(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 0.05
        case .max: return 0.15
        case .ultra: return 0.25
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
