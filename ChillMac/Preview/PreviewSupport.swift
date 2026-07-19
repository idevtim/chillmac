#if DEBUG
import SwiftUI

/// Shared sample data for SwiftUI `#Preview` and unit tests.
/// Factories construct and seed only — never start monitors, XPC, or network.
enum PreviewSupport {
    // MARK: - Sample values

    static let sampleFans: [FanInfo] = [
        FanInfo(
            id: 0,
            name: "Left Fan",
            currentRPM: 2800,
            minRPM: 1200,
            maxRPM: 6000,
            targetRPM: 2800,
            isManualMode: false
        ),
        FanInfo(
            id: 1,
            name: "Right Fan",
            currentRPM: 2650,
            minRPM: 1200,
            maxRPM: 6000,
            targetRPM: 2650,
            isManualMode: true
        ),
    ]

    static let sampleSensors: [TemperatureSensor] = [
        TemperatureSensor(id: "Tp09", label: "CPU Die", temperature: 58.5),
        TemperatureSensor(id: "TG0P", label: "GPU", temperature: 52.0),
        TemperatureSensor(id: "TH0x", label: "SSD", temperature: 41.2),
        TemperatureSensor(id: "TB0T", label: "Battery", temperature: 33.8),
    ]

    private static let sampleCpuHistory: [Double] = [
        12, 18, 22, 35, 48, 42, 38, 55, 62, 58,
        45, 40, 33, 28, 25, 30, 44, 50, 47, 36,
        28, 22, 18, 15,
    ]

    // MARK: - Factories

    static var fanMonitor: FanMonitor {
        let monitor = FanMonitor()
        monitor.helperReady = true
        monitor.fans = sampleFans
        monitor.sensors = sampleSensors
        monitor.peakTemperature = 58.5
        monitor.peakTemperatureLabel = "CPU Die"
        monitor.peakCpuTemperature = 58.5
        monitor.peakGpuTemperature = 52.0
        monitor.peakSsdTemperature = 41.2
        return monitor
    }

    /// Fan monitor seeded like Performance Mode Max under load (matches expanded Fans card).
    static var fanMonitorPerformanceActive: FanMonitor {
        let monitor = fanMonitor
        monitor.peakTemperature = 92.2
        monitor.peakTemperatureLabel = "CPU Die"
        monitor.peakCpuTemperature = 92.2
        monitor.performanceCurvePercent = 100
        monitor.coolingEngaged = true
        return monitor
    }

    /// Fan monitor seeded for Cool Performance under mild load (~55°C → engaged curve).
    static var fanMonitorUltra: FanMonitor {
        let peak: Double = 55
        let monitor = fanMonitor
        monitor.peakTemperature = peak
        monitor.peakTemperatureLabel = "CPU Die"
        monitor.peakCpuTemperature = peak
        monitor.peakGpuTemperature = 48.0
        monitor.peakSsdTemperature = 38.0
        monitor.coolingEngaged = true
        monitor.sensors = [
            TemperatureSensor(id: "Tp09", label: "CPU Die", temperature: peak),
            TemperatureSensor(id: "TG0P", label: "GPU", temperature: 48.0),
            TemperatureSensor(id: "TH0x", label: "SSD", temperature: 38.0),
            TemperatureSensor(id: "TB0T", label: "Battery", temperature: 32.0),
        ]
        monitor.performanceCurvePercent =
            PerformanceCurve.speedPercent(intent: .performance, temperature: peak) * 100
        return monitor
    }

    /// Posts the same notification StatusBarController sends when the popover opens,
    /// so `@State appeared` fades content in during canvas previews.
    static func triggerPopoverAppeared() {
        NotificationCenter.default.post(name: .popoverDidShow, object: nil)
    }

    static var cpuInfo: CpuInfo {
        let info = CpuInfo()
        info.userPercent = 28
        info.systemPercent = 12
        info.idlePercent = 60
        info.totalUsage = 40
        info.history = sampleCpuHistory
        info.userHistory = sampleCpuHistory.map { $0 * 0.7 }
        info.systemHistory = sampleCpuHistory.map { $0 * 0.3 }
        info.topProcesses = [
            .init(name: "Xcode", cpuPercent: 42.5, icon: nil),
            .init(name: "Safari", cpuPercent: 18.2, icon: nil),
            .init(name: "Finder", cpuPercent: 4.1, icon: nil),
        ]
        return info
    }

    static var memoryInfo: MemoryInfo {
        let info = MemoryInfo()
        let total = info.totalMemory
        info.activeMemory = UInt64(Double(total) * 0.35)
        info.wiredMemory = UInt64(Double(total) * 0.15)
        info.compressedMemory = UInt64(Double(total) * 0.10)
        info.availableMemory = total - info.activeMemory - info.wiredMemory - info.compressedMemory
        info.pressurePercent = 60
        info.swapUsed = 512 * 1_048_576
        info.topProcesses = [
            .init(name: "Xcode", memoryBytes: 2_147_483_648, icon: nil),
            .init(name: "Safari", memoryBytes: 805_306_368, icon: nil),
            .init(name: "Finder", memoryBytes: 268_435_456, icon: nil),
        ]
        return info
    }

    static var batteryInfo: BatteryInfo {
        let info = BatteryInfo()
        info.currentCharge = 72
        info.maxCapacity = 4800
        info.designCapacity = 5200
        info.cycleCount = 312
        info.healthPercent = 92
        info.temperature = 31.5
        info.isCharging = false
        info.isPluggedIn = true
        info.timeRemaining = "4h 22m"
        info.condition = "Normal"
        return info
    }

    static var systemInfo: SystemInfo {
        SystemInfo.previewSample
    }

    static var fpsMonitor: DisplayFPSMonitor {
        let monitor = DisplayFPSMonitor()
        monitor.fps = 120
        return monitor
    }

    static var updateChecker: UpdateChecker {
        let checker = UpdateChecker()
        checker.hasChecked = true
        checker.updateAvailable = false
        checker.latestVersion = checker.currentVersion
        return checker
    }

    static var helper: HelperConnection {
        HelperConnection()
    }

    // MARK: - Preview chrome

    enum PreviewFrame {
        case popover
        case detail
    }

    static func previewHost<Content: View>(
        scheme: ColorScheme = .dark,
        frame: PreviewFrame = .popover,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let size: CGSize = {
            switch frame {
            case .popover: return CGSize(width: 420, height: 640)
            case .detail: return CGSize(width: 360, height: 560)
            }
        }()
        return content()
            .preferredColorScheme(scheme)
            .frame(width: size.width, height: size.height)
    }

    
}

extension View {
    func previewHost(scheme: ColorScheme = .dark, frame: PreviewSupport.PreviewFrame = .popover) -> some View {
        PreviewSupport.previewHost(scheme: scheme, frame: frame) { self }
    }
}
#endif
