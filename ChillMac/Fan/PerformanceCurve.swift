import Foundation

/// Pure temperature → fan-speed math for each `PerformanceLevel`.
/// Single source of truth — `FanMonitor` only applies the results.
enum PerformanceCurve {
    /// Minimum fan speed % (above minRPM) while performance mode is engaged.
    static func minFloor(level: PerformanceLevel) -> Double {
        switch level {
        case .low: return 0.0      // sits at exactly minRPM — inaudible, but never auto
        case .medium: return 0.10
        case .high: return 0.25
        case .max: return 0.50     // proactive baseline; never need to spin up from cold
        case .ultra: return 0.70   // pure performance — cool early, hold clocks
        }
    }

    /// Max RPM increase per 2s poll cycle. Lower = gentler audible ramp-up.
    static func rampUpRate(level: PerformanceLevel) -> Double {
        switch level {
        case .low: return 400
        case .medium: return 700
        case .high: return 1200
        case .max: return 2000
        case .ultra: return 3500
        }
    }

    /// Max RPM decrease per 2s poll cycle. Always slower than ramp-up.
    static func rampDownRate(level: PerformanceLevel) -> Double {
        switch level {
        case .low: return 150
        case .medium: return 250
        case .high: return 400
        case .max: return 500
        case .ultra: return 800
        }
    }

    /// EMA factor for temperature smoothing — lower = heavier smoothing, slower reactivity.
    static func smoothingFactor(level: PerformanceLevel) -> Double {
        switch level {
        case .low: return 0.15
        case .medium: return 0.25
        case .high: return 0.35
        case .max: return 0.50
        case .ultra: return 0.70
        }
    }

    /// Maps a (smoothed) peak zone temperature to a fan speed % between the level's
    /// floor and 100%. Curves are continuous so there are no audible cliffs.
    static func speedPercent(level: PerformanceLevel, temperature temp: Double) -> Double {
        switch level {
        case .low:
            // Floor = minRPM (inaudible). Only intervenes once the chassis is genuinely hot.
            switch temp {
            case ...70: return 0.0
            case 70..<85:  return        (temp - 70) / 15.0 * 0.30  // 0 → 30%
            case 85..<95:  return 0.30 + (temp - 85) / 10.0 * 0.30  // 30 → 60%
            case 95..<105: return 0.60 + (temp - 95) / 10.0 * 0.20  // 60 → 80%
            default: return 0.80
            }
        case .medium:
            // Floor = 10%. Quiet idle, responsive once load shows up.
            switch temp {
            case ...55: return 0.10
            case 55..<70: return 0.10 + (temp - 55) / 15.0 * 0.25   // 10 → 35%
            case 70..<82: return 0.35 + (temp - 70) / 12.0 * 0.30   // 35 → 65%
            case 82..<92: return 0.65 + (temp - 82) / 10.0 * 0.25   // 65 → 90%
            default: return min(0.90 + (temp - 92) / 8.0 * 0.10, 1.0)
            }
        case .high:
            // Floor = 25%. Aggressive — keeps the chassis cool well before thermal pressure.
            switch temp {
            case ...45: return 0.25
            case 45..<58: return 0.25 + (temp - 45) / 13.0 * 0.25   // 25 → 50%
            case 58..<70: return 0.50 + (temp - 58) / 12.0 * 0.25   // 50 → 75%
            case 70..<82: return 0.75 + (temp - 70) / 12.0 * 0.20   // 75 → 95%
            default: return 1.0
            }
        case .max:
            // Smart max: high baseline (50%) so cooling is preemptive, ramps to 100% well
            // before throttle territory. NOT constant-100% — that's pointless noise & wear
            // when there's thermal headroom.
            switch temp {
            case ...40: return 0.50
            case 40..<55: return 0.50 + (temp - 40) / 15.0 * 0.20   // 50 → 70%
            case 55..<68: return 0.70 + (temp - 55) / 13.0 * 0.30   // 70 → 100%
            default: return 1.0
            }
        case .ultra:
            // Pure performance: higher floor (70%), 100% by ~60°C — still temp-responsive,
            // not constant blast.
            switch temp {
            case ...35: return 0.70
            case 35..<48: return 0.70 + (temp - 35) / 13.0 * 0.15   // 70 → 85%
            case 48..<60: return 0.85 + (temp - 48) / 12.0 * 0.15   // 85 → 100%
            default: return 1.0
            }
        }
    }
}
