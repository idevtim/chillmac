import Testing
@testable import ChillMac

@Suite("CoolingEngagement", .tags(.unit, .fan))
struct CoolingEngagementTests {
    @Test("cool peak stays idle — Ultra intent does not engage")
    func ultraSilentWhenCool() {
        let next = CoolingEngagement.nextState(
            currentlyEngaged: false,
            peakCelsius: 40,
            intent: .ultra,
            thermalForceEngage: false,
            secondsInBand: 30
        )
        #expect(next == .idle)
    }

    @Test("crossing engage threshold engages")
    func crossesEngage() {
        let next = CoolingEngagement.nextState(
            currentlyEngaged: false,
            peakCelsius: 56,
            intent: .ultra,
            thermalForceEngage: false,
            secondsInBand: 15
        )
        #expect(next == .engaged)
    }

    @Test("below release with dwell returns to idle")
    func releaseWithDwell() {
        let next = CoolingEngagement.nextState(
            currentlyEngaged: true,
            peakCelsius: 40,
            intent: .ultra,
            thermalForceEngage: false,
            secondsInBand: 15
        )
        #expect(next == .idle)
    }

    @Test("below release without dwell stays engaged")
    func releaseNeedsDwell() {
        let next = CoolingEngagement.nextState(
            currentlyEngaged: true,
            peakCelsius: 40,
            intent: .ultra,
            thermalForceEngage: false,
            secondsInBand: 2
        )
        #expect(next == .engaged)
    }

    @Test("serious thermal state forces engage even when cool")
    func thermalForceEngage() {
        let next = CoolingEngagement.nextState(
            currentlyEngaged: false,
            peakCelsius: 30,
            intent: .native,
            thermalForceEngage: true,
            secondsInBand: 0
        )
        #expect(next == .engaged)
    }

    @Test("idle means no soft floor")
    func idleNoFloor() {
        #expect(CoolingEngagement.softFloorWhileEngaged(intent: .ultra) > 0)
        #expect(PerformanceCurve.minFloor(intent: .ultra, engaged: false) == 0)
    }

    @Test("engaged applies soft floor")
    func engagedSoftFloor() {
        #expect(PerformanceCurve.minFloor(intent: .ultra, engaged: true) > 0)
    }
}
