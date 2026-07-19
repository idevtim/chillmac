import Foundation

enum DisplaySleepFanPolicy {
    /// Whether screen sleep / lock should leave fans under app control.
    /// `keepClosedOnPower` only applies when on AC; `keepOnScreenSleep` is power-agnostic.
    static func shouldKeepFansThroughDisplaySleep(
        keepClosedOnPower: Bool,
        keepOnScreenSleep: Bool,
        onAC: Bool
    ) -> Bool {
        if keepClosedOnPower && onAC { return true }
        return keepOnScreenSleep
    }

    /// Whether `NSWorkspace.willSleepNotification` should force fans back to auto.
    ///
    /// Lid close often posts willSleep after screensDidSleep. This must use the same keep
    /// decision so a keep preference is not undone by resetting fans on willSleep.
    static func shouldResetFansOnSystemWillSleep(
        keepClosedOnPower: Bool,
        keepOnScreenSleep: Bool,
        onAC: Bool
    ) -> Bool {
        !shouldKeepFansThroughDisplaySleep(
            keepClosedOnPower: keepClosedOnPower,
            keepOnScreenSleep: keepOnScreenSleep,
            onAC: onAC
        )
    }
}
