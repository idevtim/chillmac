import Foundation

struct FanInfo: Identifiable {
    let id: Int
    var name: String
    var currentRPM: Double
    var minRPM: Double
    var maxRPM: Double
    var targetRPM: Double
    var isManualMode: Bool
}
