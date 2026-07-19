import Foundation

/// Pure temperature → fan-speed math for each `CoolIntent` while engaged.
/// Idle (not engaged) ⇒ no curve / no floor — macOS auto owns the fans.
enum PerformanceCurve {
    /// Soft floor only while engaged. Idle always returns 0 (no app floor).
    static func minFloor(intent: CoolIntent, engaged: Bool) -> Double {
        guard engaged else { return 0 }
        return CoolingEngagement.softFloorWhileEngaged(intent: intent)
    }

    static func rampUpRate(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 400
        case .balanced: return 1200
        case .performance: return 3500
        }
    }

    static func rampDownRate(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 150
        case .balanced: return 400
        case .performance: return 800
        }
    }

    static func smoothingFactor(intent: CoolIntent) -> Double {
        switch intent {
        case .native: return 0.15
        case .balanced: return 0.35
        case .performance: return 0.70
        }
    }

    /// Maps smoothed peak zone temperature to fan speed % while engaged.
    /// Curves start near the soft floor at cool-for-engaged temps and ramp up.
    static func speedPercent(intent: CoolIntent, temperature temp: Double) -> Double {
        let floor = CoolingEngagement.softFloorWhileEngaged(intent: intent)
        switch intent {
        case .native:
            // Former Quiet curve — kept for Native intent math; Native mode itself leaves fans to macOS.
            switch temp {
            case ...70: return floor
            case 70..<85: return floor + (temp - 70) / 15.0 * (0.30 - floor)
            case 85..<95: return 0.30 + (temp - 85) / 10.0 * 0.30
            case 95..<105: return 0.60 + (temp - 95) / 10.0 * 0.20
            default: return 0.80
            }
        case .balanced:
            switch temp {
            case ...45: return floor
            case 45..<58: return floor + (temp - 45) / 13.0 * (0.50 - floor)
            case 58..<70: return 0.50 + (temp - 58) / 12.0 * 0.25
            case 70..<82: return 0.75 + (temp - 70) / 12.0 * 0.20
            default: return 1.0
            }
        case .performance:
            // Steep when hot (former Ultra hot behavior) — but floor only while engaged.
            switch temp {
            case ...35: return floor
            case 35..<48: return floor + (temp - 35) / 13.0 * (0.85 - floor)
            case 48..<60: return 0.85 + (temp - 48) / 12.0 * 0.15
            default: return 1.0
            }
        }
    }
}
