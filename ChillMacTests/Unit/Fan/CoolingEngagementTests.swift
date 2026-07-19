import Testing
@testable import ChillMac

@Suite("CoolingEngagement", .tags(.unit, .fan))
struct CoolingEngagementTests {
    @Test("cool peak stays idle — Performance intent does not engage")
    func performanceSilentWhenCool() {
        let next = CoolingEngagement.nextState(
            currentlyEngaged: false,
            peakCelsius: 40,
            intent: .performance,
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
            intent: .performance,
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
            intent: .performance,
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
            intent: .performance,
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
            intent: .quiet,
            thermalForceEngage: true,
            secondsInBand: 0
        )
        #expect(next == .engaged)
    }

    @Test("idle means no soft floor")
    func idleNoFloor() {
        #expect(CoolingEngagement.softFloorWhileEngaged(intent: .performance) > 0)
        #expect(PerformanceCurve.minFloor(intent: .performance, engaged: false) == 0)
    }

    @Test("engaged applies soft floor")
    func engagedSoftFloor() {
        #expect(PerformanceCurve.minFloor(intent: .performance, engaged: true) > 0)
    }
}
