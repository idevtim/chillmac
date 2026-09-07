import SwiftUI

/// Good / Warm / Hot, derived from the hottest sensor on the machine.
///
/// Shared by the popover header and the menu bar so the two can never disagree about what
/// "Warm" means. Previously the thresholds lived only in `PopoverView`, and putting a second
/// copy in the status item would have been one edit away from the header saying Good while
/// the menu bar showed a temperature.
enum ThermalStatus {
    case good
    case warm
    case hot

    /// Matches the popover header wording.
    var label: String {
        switch self {
        case .good: return "Good"
        case .warm: return "Warm"
        case .hot: return "Hot"
        }
    }

    static func forTemperature(_ celsius: Double) -> ThermalStatus {
        if celsius >= 90 { return .hot }
        if celsius >= 75 { return .warm }
        return .good
    }

    /// Semantic colour for the popover. The menu bar deliberately does not use this: status
    /// items are expected to be template images that adapt to the wallpaper and to Dark Mode,
    /// and `contentTintColor` on an `NSStatusBarButton` does not reliably survive either.
    func color(isLight: Bool) -> Color {
        switch self {
        case .hot: return .red
        case .warm: return isLight ? Color(red: 0.80, green: 0.45, blue: 0.0) : .orange
        case .good: return .green
        }
    }
}
