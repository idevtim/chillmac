import CoreVideo
import Foundation
import QuartzCore

final class DisplayFPSMonitor: ObservableObject {
    @Published var fps: Int = 0

    private var displayLink: CVDisplayLink?
    private var frameCount: Int = 0
    private var lock = os_unfair_lock()
    private var lastSampleTime: CFTimeInterval = 0

    func startMonitoring() {
        guard displayLink == nil else { return }

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }

        lastSampleTime = CACurrentMediaTime()
        frameCount = 0

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let monitor = Unmanaged<DisplayFPSMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            os_unfair_lock_lock(&monitor.lock)
            monitor.frameCount += 1

            let now = CACurrentMediaTime()
            let elapsed = now - monitor.lastSampleTime
            if elapsed >= 1.0 {
                let measured = Int(Double(monitor.frameCount) / elapsed + 0.5)
                monitor.lastSampleTime = now
                monitor.frameCount = 0
                os_unfair_lock_unlock(&monitor.lock)
                DispatchQueue.main.async {
                    monitor.fps = measured
                }
            } else {
                os_unfair_lock_unlock(&monitor.lock)
            }

            return kCVReturnSuccess
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, selfPtr)
        CVDisplayLinkStart(displayLink)
    }

    func stopMonitoring() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
        fps = 0
    }

    deinit {
        stopMonitoring()
    }
}
