import Foundation
import IOKit.ps

/// Where the Mac is drawing power from right now.
enum PowerSource {

    struct Snapshot {
        let isOnAC: Bool
        /// Percent, 0-100. 100 when there is no battery to report one.
        let charge: Int
    }

    /// Nil when IOPowerSources reports nothing, which is the normal answer on a Mac with no
    /// battery at all. Callers treat that as "on AC", because a desktop always is.
    static func current() -> Snapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let info = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else { return nil }

        return Snapshot(
            isOnAC: (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
            charge: info[kIOPSCurrentCapacityKey] as? Int ?? 100
        )
    }

    /// True when running on wall power, and on any machine that has no battery.
    static var isOnAC: Bool {
        current()?.isOnAC ?? true
    }
}
