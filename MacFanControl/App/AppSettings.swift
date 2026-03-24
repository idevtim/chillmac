import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("useFahrenheit") var useFahrenheit = false

    func formatTemperature(_ celsius: Double) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return String(format: "%.1f°F", f)
        }
        return String(format: "%.1f°C", celsius)
    }
}
