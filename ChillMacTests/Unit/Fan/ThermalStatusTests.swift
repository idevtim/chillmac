import Testing
@testable import ChillMac

@Suite("ThermalStatus", .tags(.unit, .fan))
struct ThermalStatusTests {
    @Test("boundaries match popover Good/Warm/Hot")
    func boundaries() {
        #expect(ThermalStatus.from(peakCelsius: 0) == .unknown)
        #expect(ThermalStatus.from(peakCelsius: 74.9) == .good)
        #expect(ThermalStatus.from(peakCelsius: 75) == .warm)
        #expect(ThermalStatus.from(peakCelsius: 89.9) == .warm)
        #expect(ThermalStatus.from(peakCelsius: 90) == .hot)
    }

    @Test("menu bar only speaks when Warm or Hot")
    func menuBarVisibility() {
        #expect(!ThermalStatus.good.showsMenuBarTemperature)
        #expect(!ThermalStatus.unknown.showsMenuBarTemperature)
        #expect(ThermalStatus.warm.showsMenuBarTemperature)
        #expect(ThermalStatus.hot.showsMenuBarTemperature)
    }

    @Test("menu bar text is compact integer degrees")
    func menuBarText() {
        #expect(ThermalStatus.menuBarTemperatureText(celsius: 78.4, useFahrenheit: false) == "78°")
        #expect(ThermalStatus.menuBarTemperatureText(celsius: 78.4, useFahrenheit: true) == "173°")
    }
}
