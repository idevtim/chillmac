import Foundation
import IOKit.ps

enum PowerSource {
    /// Injectable seam for unit tests. Production default reads IOPS providing type.
    static var providingType: () -> String? = {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        else { return nil }
        return type
    }

    static var isOnAC: Bool {
        providingType() == kIOPSACPowerValue
    }
}
