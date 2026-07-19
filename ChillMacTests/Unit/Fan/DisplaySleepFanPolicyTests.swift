import Testing
@testable import ChillMac

@Suite("DisplaySleepFanPolicy", .tags(.unit, .fan))
struct DisplaySleepFanPolicyTests {
    @Test(arguments: [
        // keepClosedOnPower, keepOnScreenSleep, onAC, expectKeep
        (false, false, false, false),
        (false, false, true, false),
        (false, true, false, true),
        (false, true, true, true),
        (true, false, true, true),
        (true, false, false, false),
        (true, true, false, true),
        (true, true, true, true),
    ])
    func truthTable(
        keepClosedOnPower: Bool,
        keepOnScreenSleep: Bool,
        onAC: Bool,
        expectKeep: Bool
    ) {
        let result = DisplaySleepFanPolicy.shouldKeepFansThroughDisplaySleep(
            keepClosedOnPower: keepClosedOnPower,
            keepOnScreenSleep: keepOnScreenSleep,
            onAC: onAC
        )
        #expect(result == expectKeep)
    }

    // MARK: - willSleep regression (lid close)

    @Test("willSleep does not reset when keepClosedOnPower and on AC")
    func willSleepKeepsClosedOnPowerAC() {
        let shouldReset = DisplaySleepFanPolicy.shouldResetFansOnSystemWillSleep(
            keepClosedOnPower: true,
            keepOnScreenSleep: false,
            onAC: true
        )
        #expect(!shouldReset)
    }

    @Test("willSleep resets on battery even with keepClosedOnPower")
    func willSleepResetsClosedOnPowerBattery() {
        let shouldReset = DisplaySleepFanPolicy.shouldResetFansOnSystemWillSleep(
            keepClosedOnPower: true,
            keepOnScreenSleep: false,
            onAC: false
        )
        #expect(shouldReset)
    }

    @Test("willSleep does not reset when keepOnScreenSleep")
    func willSleepKeepsOnScreenSleep() {
        let shouldReset = DisplaySleepFanPolicy.shouldResetFansOnSystemWillSleep(
            keepClosedOnPower: false,
            keepOnScreenSleep: true,
            onAC: false
        )
        #expect(!shouldReset)
    }

    @Test("willSleep resets when both keep settings are off")
    func willSleepResetsWhenKeepOff() {
        let shouldReset = DisplaySleepFanPolicy.shouldResetFansOnSystemWillSleep(
            keepClosedOnPower: false,
            keepOnScreenSleep: false,
            onAC: true
        )
        #expect(shouldReset)
    }

    @Test(arguments: [
        (false, false, false),
        (false, false, true),
        (false, true, false),
        (false, true, true),
        (true, false, true),
        (true, false, false),
        (true, true, false),
        (true, true, true),
    ])
    func willSleepResetIsInverseOfKeep(
        keepClosedOnPower: Bool,
        keepOnScreenSleep: Bool,
        onAC: Bool
    ) {
        let keep = DisplaySleepFanPolicy.shouldKeepFansThroughDisplaySleep(
            keepClosedOnPower: keepClosedOnPower,
            keepOnScreenSleep: keepOnScreenSleep,
            onAC: onAC
        )
        let shouldReset = DisplaySleepFanPolicy.shouldResetFansOnSystemWillSleep(
            keepClosedOnPower: keepClosedOnPower,
            keepOnScreenSleep: keepOnScreenSleep,
            onAC: onAC
        )
        #expect(shouldReset == !keep)
    }
}
