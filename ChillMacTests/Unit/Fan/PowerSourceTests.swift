import IOKit.ps
import Testing
@testable import ChillMac

@Suite("PowerSource", .serialized, .tags(.unit, .fan))
struct PowerSourceTests {
    @Test("isOnAC is true when providing type is AC Power")
    func onAC() {
        let previous = PowerSource.providingType
        defer { PowerSource.providingType = previous }

        PowerSource.providingType = { kIOPSACPowerValue as String }
        #expect(PowerSource.isOnAC)
    }

    @Test("isOnAC is false when providing type is Battery Power")
    func onBattery() {
        let previous = PowerSource.providingType
        defer { PowerSource.providingType = previous }

        PowerSource.providingType = { kIOPSBatteryPowerValue as String }
        #expect(!PowerSource.isOnAC)
    }

    @Test("isOnAC is false when providing type is nil")
    func nilProvidingType() {
        let previous = PowerSource.providingType
        defer { PowerSource.providingType = previous }

        PowerSource.providingType = { nil }
        #expect(!PowerSource.isOnAC)
    }
}
