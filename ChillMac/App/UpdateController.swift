import AppKit
import Sparkle

/// Owns the Sparkle updater and republishes its state for SwiftUI.
///
/// Sparkle handles the whole update loop — scheduled checks against the appcast, download,
/// EdDSA signature check, bundle swap, relaunch. This wrapper exists for two reasons: to
/// expose `updateAvailable` to the popover badge, and to pull the update window forward,
/// which an `LSUIElement` app has to ask for explicitly.
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {

    /// True once a check has found a newer version. Drives the popover badge.
    @Published private(set) var updateAvailable = false
    /// Version string of the available update, if any.
    @Published private(set) var latestVersion: String?
    @Published private(set) var isChecking = false
    /// True after at least one check has finished, so the UI can distinguish
    /// "up to date" from "hasn't looked yet".
    @Published private(set) var hasChecked = false

    private var controller: SPUStandardUpdaterController!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Whether Sparkle is ready to run a user-initiated check.
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    override init() {
        super.init()
        // startingUpdater: true begins the scheduled background checks immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// User-initiated check — always shows UI, including "you're up to date".
    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        isChecking = true
        activateForUpdateUI()
        controller.updater.checkForUpdates()
    }

    /// Silent check that refreshes `updateAvailable` without showing any Sparkle UI.
    /// Used when the settings pane appears — a visible "you're up to date" alert every
    /// time someone opens settings would be obnoxious.
    func refreshUpdateStatus() {
        guard canCheckForUpdates else { return }
        isChecking = true
        controller.updater.checkForUpdateInformation()
    }

    /// Brings the app forward so Sparkle's window isn't buried behind other apps.
    /// Menu bar apps have no Dock icon to click, so without this the update prompt can
    /// appear with no way for the user to find it.
    private func activateForUpdateUI() {
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.latestVersion = item.displayVersionString
            self.updateAvailable = true
            self.hasChecked = true
            self.isChecking = false
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async {
            self.updateAvailable = false
            self.latestVersion = nil
            self.hasChecked = true
            self.isChecking = false
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        DispatchQueue.main.async {
            self.isChecking = false
            // A failed cycle (offline, malformed feed) must not be reported as "up to date".
            if error == nil { self.hasChecked = true }
        }
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        DispatchQueue.main.async { self.isChecking = false }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Sparkle is about to show something. Make sure the app is frontmost first.
    func standardUserDriverWillShowModalAlert() {
        activateForUpdateUI()
    }
}
