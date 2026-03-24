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

    // Temperature sensors — Apple Silicon (M-series) keys
    static let temperatureKeys: [(key: String, label: String)] = [
        // CPU
        ("Tp09", "CPU Efficiency Core 1"),
        ("Tp0T", "CPU Efficiency Core 2"),
        ("Tp01", "CPU Performance Core 1"),
        ("Tp05", "CPU Performance Core 2"),
        ("Tp0D", "CPU Performance Core 3"),
        ("Tp0H", "CPU Performance Core 4"),
        ("Tp0L", "CPU Performance Core 5"),
        ("Tp0P", "CPU Performance Core 6"),
        ("Tp0X", "CPU Performance Core 7"),
        ("Tp0b", "CPU Performance Core 8"),
        ("TCDX", "CPU Die (Max)"),
        ("TCMb", "CPU Die (Avg)"),
        ("TCMz", "CPU Die (Peak)"),
        ("TCHP", "CPU Hotspot"),

        // GPU
        ("TPDX", "GPU Die (Max)"),
        ("TPMP", "GPU Power"),
        ("TPSP", "GPU SoC"),

        // Memory / DRAM
        ("TRDX", "DRAM (Max)"),
        ("TRD0", "DRAM Module 0"),
        ("TMVR", "Memory VR"),

        // SSD / Storage
        ("TH0x", "SSD (Max)"),
        ("TH0a", "SSD A"),
        ("TH0b", "SSD B"),

        // Die / Enclosure
        ("TDVx", "Die VRM (Max)"),
        ("TDTP", "Die Top"),
        ("TDBP", "Die Bottom"),
        ("TDCR", "Die Center"),

        // Battery
        ("TB0T", "Battery 1"),
        ("TB1T", "Battery 2"),
        ("TB2T", "Battery 3"),

        // Ambient / Enclosure
        ("TAOL", "Ambient"),
        ("TDEL", "Enclosure Left"),
        ("TDER", "Enclosure Right"),
        ("TDeL", "Display Left"),
        ("TDeR", "Display Right"),
        ("Ts0P", "Palm Rest"),

        // Intel fallback keys (for compatibility)
        ("TC0P", "CPU Proximity"),
        ("TC0D", "CPU Die"),
        ("TG0P", "GPU Proximity"),
        ("TG0D", "GPU Die"),
        ("Tm0P", "Memory Proximity"),
        ("TN0P", "Northbridge"),
        ("TA0P", "Ambient"),
    ]
}
