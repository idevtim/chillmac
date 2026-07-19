import SwiftUI
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

    @Test("Good emphasis stays calm; Warm/Hot use hue")
    func emphasisColor() {
        #expect(ThermalStatus.good.emphasisColor == Color.secondary)
        #expect(ThermalStatus.warm.emphasisColor == Color.orange)
        #expect(ThermalStatus.hot.emphasisColor == Color.red)
    }
}
