import Foundation

/// Commits or clears local fan-target caches based on helper XPC reply.
enum FanTargetCommit {
    static func apply(
        ok: Bool,
        fanId: Int,
        rpm: Double,
        manualOverrides: inout [Int: Bool],
        targetOverrides: inout [Int: Double],
        lastSentRPM: inout [Int: Double]
    ) {
        if ok {
            lastSentRPM[fanId] = rpm
            targetOverrides[fanId] = rpm
            manualOverrides[fanId] = true
        } else {
            // Do not cache a fake target — allow retries next poll
            manualOverrides[fanId] = false
            targetOverrides.removeValue(forKey: fanId)
            lastSentRPM.removeValue(forKey: fanId)
        }
    }
}

/// UI / control gating for Performance Mode vs live helper availability.
enum PerformanceControl {
    static func isActivelyControlling(performanceMode: Bool, helperReady: Bool) -> Bool {
        performanceMode && helperReady
    }
}

/// Whether the app may advertise fan-write capability.
enum HelperReadiness {
    static func isReady(_ status: HelperInstaller.HelperStatus) -> Bool {
        status == .runningCorrectVersion
    }
}
