import Foundation

enum SMCKey {
    static let fanCount = "FNum"

    static func fanActualSpeed(_ index: Int) -> String { "F\(index)Ac" }
    static func fanMinSpeed(_ index: Int) -> String    { "F\(index)Mn" }
    static func fanMaxSpeed(_ index: Int) -> String    { "F\(index)Mx" }
    static func fanTargetSpeed(_ index: Int) -> String { "F\(index)Tg" }
    static func fanMode(_ index: Int) -> String        { "F\(index)Md" }

    /// Bitmask: one bit per fan, 1 = forced mode
    static let forceMode = "FS! "

    /// Apple Silicon: set to 1 to bypass thermalmonitord
    static let testMode = "Ftst"

    // Common temperature sensors
    static let temperatureKeys: [(key: String, label: String)] = [
        ("TC0P", "CPU Proximity"),
        ("TC0D", "CPU Die"),
        ("TC0E", "CPU 1"),
        ("TC1C", "CPU Core 1"),
        ("TC2C", "CPU Core 2"),
        ("TC3C", "CPU Core 3"),
        ("TC4C", "CPU Core 4"),
        ("TG0P", "GPU Proximity"),
        ("TG0D", "GPU Die"),
        ("Tm0P", "Memory Proximity"),
        ("TN0P", "Northbridge"),
        ("TB0T", "Battery"),
        ("Ts0P", "Palm Rest"),
        ("TA0P", "Ambient"),
        ("Tp0P", "Power Supply"),
    ]
}
