import Testing
@testable import ChillMac

@Suite("ThermalStatus", .tags(.unit, .fan))
struct ThermalStatusTests {
    @Test("thresholds match Good / Warm / Hot")
    func thresholds() {
        #expect(ThermalStatus.from(peakCelsius: 74) == .good)
        #expect(ThermalStatus.from(peakCelsius: 75) == .warm)
        #expect(ThermalStatus.from(peakCelsius: 90) == .hot)
    }

    @Test("menu bar only when Warm or Hot")
    func menuBar() {
        #expect(!ThermalStatus.good.showsMenuBarTemperature)
        #expect(ThermalStatus.warm.showsMenuBarTemperature)
        #expect(ThermalStatus.hot.showsMenuBarTemperature)
    }
}
