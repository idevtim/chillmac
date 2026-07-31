import Testing
@testable import ChillMac

@Suite("PreviewSupport", .serialized, .tags(.unit, .fixtures))
struct PreviewSupportTests {
    @Test("fanMonitor seeds fans and never needs helper for display state")
    func fanMonitorSeeded() {
        let monitor = PreviewSupport.fanMonitor
        #expect(monitor.fans.count >= 1)
        #expect(monitor.helperReady == true)
        #expect(monitor.sensors.count >= 1)
        // Implicit contract: caller must not call startMonitoring in fixtures
    }

    @Test("systemInfo preview sample skips live profiler placeholders")
    func systemInfoPreview() {
        let info = SystemInfo.previewSample
        #expect(!info.chipName.contains("..."))
        #expect(info.diskTotalBytes > 0)
    }

    @Test("all screen fixtures construct without starting monitors")
    func screenFixturesConstruct() {
        _ = PreviewSupport.fanMonitor
        _ = PreviewSupport.cpuInfo
        _ = PreviewSupport.memoryInfo
        _ = PreviewSupport.batteryInfo
        _ = PreviewSupport.systemInfo
        _ = PreviewSupport.fpsMonitor
        _ = PreviewSupport.updateController
        _ = PreviewSupport.helper
    }
}
