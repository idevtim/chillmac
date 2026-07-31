import Foundation

struct FanInfo: Identifiable, Equatable {
    let id: Int
    var name: String
    var currentRPM: Double
    var minRPM: Double
    var maxRPM: Double
    var targetRPM: Double
    var isManualMode: Bool

    // MARK: - Read Provenance
    //
    // The UI needs plain numbers, so failed/skipped SMC reads still surface as 0/false
    // here. These flags record which values were actually measured this cycle so
    // diagnostics can log the rest as null instead of passing a placeholder off as a
    // reading — a stopped fan and an unreadable fan are not the same thing.

    /// False when the SMC read for `currentRPM` failed.
    var currentRPMValid: Bool = true
    /// False when `targetRPM` came from the app's override cache rather than SMC.
    var targetRPMValid: Bool = true
    /// False when `isManualMode` came from the app's override cache rather than SMC.
    var isManualModeValid: Bool = true
}
