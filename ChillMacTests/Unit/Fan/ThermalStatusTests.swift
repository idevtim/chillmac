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

    @Test("zone track maps 30–100°C like the Cool prototype")
    func zoneTrack() {
        #expect(abs(ThermalStatus.zoneTrackPosition(peakCelsius: 30) - 0) < 0.001)
        #expect(abs(ThermalStatus.zoneTrackPosition(peakCelsius: 75) - 0.55) < 0.001)
        #expect(abs(ThermalStatus.zoneTrackPosition(peakCelsius: 90) - 0.75) < 0.001)
        #expect(abs(ThermalStatus.zoneTrackPosition(peakCelsius: 100) - 1.0) < 0.001)
    }

    @Test("severity suffix only when Fair+")
    func severitySuffix() {
        #expect(ThermalStatus.severitySuffix(thermalState: .nominal) == nil)
        #expect(ThermalStatus.severitySuffix(thermalState: .fair) == "Limited")
        #expect(ThermalStatus.severitySuffix(thermalState: .serious) == "Throttled")
        #expect(ThermalStatus.severitySuffix(thermalState: .critical) == "Throttled")
    }
}
