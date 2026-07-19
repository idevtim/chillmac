import Testing
@testable import ChillMac

@Suite("PerformanceCurve", .tags(.unit, .fan))
struct PerformanceCurveTests {
    @Test("Ultra at cool temp holds high floor, not full blast")
    func ultraCoolNotFullBlast() {
        let p = PerformanceCurve.speedPercent(level: .ultra, temperature: 30)
        #expect(p == 0.70)
        #expect(p < 1.0)
    }

    @Test("Ultra reaches 100% by ~60C")
    func ultraHotFull() {
        #expect(PerformanceCurve.speedPercent(level: .ultra, temperature: 60) == 1.0)
    }

    @Test("Max at 30C stays ~0.50 — Ultra is more aggressive")
    func maxRegressionCool() {
        let maxP = PerformanceCurve.speedPercent(level: .max, temperature: 30)
        let ultraP = PerformanceCurve.speedPercent(level: .ultra, temperature: 30)
        #expect(abs(maxP - 0.50) < 0.001)
        #expect(ultraP > maxP)
    }

    @Test("Ultra floor is 0.70")
    func ultraFloor() {
        #expect(PerformanceCurve.minFloor(level: .ultra) == 0.70)
    }
}
