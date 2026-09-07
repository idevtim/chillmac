import CoreVideo
import Foundation
import QuartzCore

final class DisplayFPSMonitor: ObservableObject {
    @Published var fps: Int = 0

    private var displayLink: CVDisplayLink?
    private var frameCount: Int = 0
    private var lastSampleTime: CFTimeInterval = 0

    /// Heap-allocated so the display-link callback always locks the same memory. Taking
    /// `&self.lock` on a stored property lets Swift hand the callback a temporary copy,
    /// which silently stops being a lock at all.
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)

    /// The retained reference handed to CoreVideo, released once the link is fully stopped.
    /// The callback runs on CoreVideo's own thread and can still be in flight when the last
    /// Swift reference goes away, so it must own a strong reference of its own.
    private var callbackRef: Unmanaged<DisplayFPSMonitor>?

    init() {
        lock.initialize(to: os_unfair_lock())
    }

    func startMonitoring() {
        guard displayLink == nil else { return }

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }

        lastSampleTime = CACurrentMediaTime()
        frameCount = 0

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let monitor = Unmanaged<DisplayFPSMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            os_unfair_lock_lock(monitor.lock)
            monitor.frameCount += 1

            let now = CACurrentMediaTime()
            let elapsed = now - monitor.lastSampleTime
            if elapsed >= 1.0 {
                let measured = Int(Double(monitor.frameCount) / elapsed + 0.5)
                monitor.lastSampleTime = now
                monitor.frameCount = 0
                os_unfair_lock_unlock(monitor.lock)
                DispatchQueue.main.async {
                    if monitor.fps != measured { monitor.fps = measured }
                }
            } else {
                os_unfair_lock_unlock(monitor.lock)
            }

            return kCVReturnSuccess
        }

        let retained = Unmanaged.passRetained(self)
        callbackRef = retained
        CVDisplayLinkSetOutputCallback(displayLink, callback, retained.toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    func stopMonitoring() {
        if let displayLink {
            // Stop, then clear the callback: CVDisplayLinkStop waits for an in-flight
            // callback to return, and clearing afterwards guarantees no new one starts.
            CVDisplayLinkStop(displayLink)
            CVDisplayLinkSetOutputCallback(displayLink, nil, nil)
        }
        displayLink = nil
        callbackRef?.release()
        callbackRef = nil
        if fps != 0 { fps = 0 }
    }

    deinit {
        // No stopMonitoring() here: while a link is running it holds a strong reference via
        // `callbackRef`, so deinit can only be reached once monitoring has already stopped.
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
}
