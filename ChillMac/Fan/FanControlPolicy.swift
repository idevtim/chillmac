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
            // Skip no-op writes — subscript assignment on @Published dictionaries
            // republishes every time and trips "Publishing changes from within view updates".
            if lastSentRPM[fanId] != rpm { lastSentRPM[fanId] = rpm }
            if targetOverrides[fanId] != rpm { targetOverrides[fanId] = rpm }
            if manualOverrides[fanId] != true { manualOverrides[fanId] = true }
        } else {
            // Do not cache a fake target — allow retries next poll
            if manualOverrides[fanId] != false { manualOverrides[fanId] = false }
            if targetOverrides[fanId] != nil { targetOverrides.removeValue(forKey: fanId) }
            if lastSentRPM[fanId] != nil { lastSentRPM.removeValue(forKey: fanId) }
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
