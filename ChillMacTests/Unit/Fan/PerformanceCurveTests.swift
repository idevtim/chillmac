import Testing
@testable import ChillMac

@Suite("PerformanceCurve", .tags(.unit, .fan))
struct PerformanceCurveTests {
    @Test("Max at cool temp holds 50% floor")
    func maxCoolFloor() {
        #expect(abs(PerformanceCurve.speedPercent(level: .max, temperature: 30) - 0.50) < 0.001)
    }

    @Test("Max reaches 100% by ~68C")
    func maxHotFull() {
        #expect(PerformanceCurve.speedPercent(level: .max, temperature: 68) == 1.0)
    }

    @Test("Max floor is 0.50")
    func maxFloor() {
        #expect(PerformanceCurve.minFloor(level: .max) == 0.50)
    }
}
