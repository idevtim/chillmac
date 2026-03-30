import Foundation

struct TemperatureSensor: Identifiable, Equatable {
    let id: String
    let label: String
    var temperature: Double
}
