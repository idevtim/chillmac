import Testing
@testable import ChillMac

@Suite("PerformanceCurve", .tags(.unit, .fan))
struct PerformanceCurveTests {
    @Test("Ultra intent idle has zero floor")
    func ultraIdleNoFloor() {
        #expect(PerformanceCurve.minFloor(intent: .ultra, engaged: false) == 0)
    }

    @Test("Ultra intent engaged has soft floor only")
    func ultraEngagedSoftFloor() {
        let floor = PerformanceCurve.minFloor(intent: .ultra, engaged: true)
        #expect(floor == 0.25)
        #expect(floor < 0.70)
    }

    @Test("Ultra curve reaches 100% by ~60C when engaged")
    func ultraHotFull() {
        #expect(PerformanceCurve.speedPercent(intent: .ultra, temperature: 60) == 1.0)
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
        ("medium", CoolIntent.max),
        ("high", CoolIntent.max),
        ("quiet", CoolIntent.native),
        ("native", CoolIntent.native),
        ("balanced", CoolIntent.max),
        ("performance", CoolIntent.ultra),
        ("max", CoolIntent.max),
        ("ultra", CoolIntent.ultra),
    ])
    func migratesLegacy(raw: String, expected: CoolIntent) {
        #expect(CoolIntent.migrated(fromLegacyRaw: raw) == expected)
    }

    @Test(arguments: [
        ("low", CoolIntent.native),
        ("medium", CoolIntent.max),
        ("high", CoolIntent.max),
        ("max", CoolIntent.ultra),
        ("ultra", CoolIntent.ultra),
    ])
    func migratesLegacyPerformanceLevel(raw: String, expected: CoolIntent) {
        #expect(CoolIntent.fromLegacyPerformanceLevel(raw) == expected)
    }

    @Test("labels are Native / Max / Ultra")
    func labels() {
        #expect(CoolIntent.native.label == "Native")
        #expect(CoolIntent.max.label == "Max")
        #expect(CoolIntent.ultra.label == "Ultra")
    }
}
