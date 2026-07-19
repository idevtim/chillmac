import Testing
@testable import ChillMac

@Suite("PerformanceCurve", .tags(.unit, .fan))
struct PerformanceCurveTests {
    @Test("Performance intent idle has zero floor")
    func performanceIdleNoFloor() {
        #expect(PerformanceCurve.minFloor(intent: .performance, engaged: false) == 0)
    }

    @Test("Performance intent engaged has soft floor only")
    func performanceEngagedSoftFloor() {
        let floor = PerformanceCurve.minFloor(intent: .performance, engaged: true)
        #expect(floor == 0.25)
        #expect(floor < 0.70)
    }

    @Test("Performance curve reaches 100% by ~60C when engaged")
    func performanceHotFull() {
        #expect(PerformanceCurve.speedPercent(intent: .performance, temperature: 60) == 1.0)
    }

    @Test("Native curve is gentle at warm temps")
    func nativeGentle() {
        let p = PerformanceCurve.speedPercent(intent: .native, temperature: 75)
        #expect(p < 0.40)
    }
}

@Suite("CoolIntent", .tags(.unit, .fan))
struct CoolIntentTests {
    @Test(arguments: [
        ("low", CoolIntent.native),
        ("medium", CoolIntent.balanced),
        ("high", CoolIntent.balanced),
        ("max", CoolIntent.performance),
        ("ultra", CoolIntent.performance),
        ("quiet", CoolIntent.native),
        ("native", CoolIntent.native),
        ("balanced", CoolIntent.balanced),
        ("performance", CoolIntent.performance),
    ])
    func migratesLegacy(raw: String, expected: CoolIntent) {
        #expect(CoolIntent.migrated(fromLegacyRaw: raw) == expected)
    }

    @Test("labels are Native / Balanced / Performance")
    func labels() {
        #expect(CoolIntent.native.label == "Native")
        #expect(CoolIntent.balanced.label == "Balanced")
        #expect(CoolIntent.performance.label == "Performance")
    }
}
