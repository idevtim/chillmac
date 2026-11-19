import Foundation
import ServiceManagement

enum HelperInstaller {

    private static let plistName = "com.idevtim.ChillMac.Helper.plist"
    private static var service: SMAppService { SMAppService.daemon(plistName: plistName) }

    /// What the app can actually do with the helper right now.
    ///
    /// `SMAppService.Status` has four cases and the difference between them is the whole
    /// story for the user. Collapsing them into "registered or not" is what made a Mac
    /// sitting at `.requiresApproval` look identical to one that was never registered: the
    /// app kept calling `register()` on an already-registered service, launchd kept throwing
    /// "already registered", the error was logged and dropped, and the user was never told
    /// that the one thing standing between them and fan control was a switch in Login Items.
    enum HelperState: Equatable {
        /// Not determined yet. The state at launch, before the first probe answers.
        case checking
        /// Registered, approved, responding over XPC, and the expected version.
        case running
        /// Registered, but the user has not enabled it under Login Items & Extensions.
        case needsApproval
        /// Never registered, or the registration is gone.
        case needsInstall
        /// Installed, but an older build than this app expects.
        case needsUpdate
        /// Approved and enabled, yet XPC gets no answer.
        case unresponsive

        /// Whether fan control can actually be performed.
        var canControlFans: Bool { self == .running }
    }

    // MARK: - Observation

    /// Reads the current state without changing anything. Blocking: probes the daemon over
    /// XPC, so call it off the main thread.
    static func currentState() -> HelperState {
        let status = service.status
        switch status {
        case .enabled:
            // `.enabled` means registered and eligible, not necessarily alive. The only way
            // to know the daemon is actually there is to ask it something.
            guard let version = probeVersion() else { return .unresponsive }
            return version == kHelperVersion ? .running : .needsUpdate
        case .requiresApproval:
            return .needsApproval
        case .notRegistered, .notFound:
            return .needsInstall
        @unknown default:
            NSLog("HelperInstaller: unknown SMAppService status \(status.rawValue)")
            return .needsInstall
        }
    }

    // MARK: - Installation

    /// What came of an install attempt. `failure` is the reason to show the user when the
    /// attempt did not get the helper running or awaiting approval; nil otherwise.
    struct InstallResult {
        let state: HelperState
        let failure: String?
    }

    /// Why the daemon cannot be registered from where this copy of the app is running, or nil.
    ///
    /// SMAppService records the daemon by its path inside this bundle. A downloaded app that
    /// was opened without being moved runs from a randomized, read-only App Translocation
    /// path, and one opened straight from the disk image runs from a volume that disappears
    /// on eject. Registering from either fails or points launchd at a path that is about to
    /// vanish, and until now the failure was only logged, so pressing Install did nothing.
    static var locationProblem: String? {
        let url = Bundle.main.bundleURL
        if url.path.contains("/AppTranslocation/") {
            return "macOS is running ChillMac from a temporary, read-only copy, so the helper can't be installed. Move ChillMac to your Applications folder, then open it from there."
        }
        if (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return "ChillMac is running from the disk image. Drag it to your Applications folder, eject the disk image, then open ChillMac from Applications."
        }
        return nil
    }

    /// Raw `SMAppService` status, for diagnostics.
    static var serviceStatusDescription: String {
        switch service.status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown(\(service.status.rawValue))"
        }
    }

    /// Registers the daemon, replacing any existing registration first so a version bump or
    /// a broken install is actually superseded. Blocking; returns the resulting state and,
    /// when registration was refused, macOS's reason.
    static func install() -> InstallResult {
        if let problem = locationProblem {
            NSLog("HelperInstaller: not registering from \(Bundle.main.bundlePath) — \(problem)")
            return InstallResult(state: currentState(), failure: problem)
        }

        let status = service.status
        if status == .enabled || status == .requiresApproval {
            // register() on a live registration throws "already registered" and changes
            // nothing, so an in-place update has to unregister first.
            unregister()
        }

        var failure: String?
        do {
            try service.register()
            NSLog("HelperInstaller: registered successfully")
        } catch {
            let nsError = error as NSError
            NSLog("HelperInstaller: registration failed — \(error)")
            failure = "macOS refused to install the helper: \(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
            // Fall through: the status read below is more trustworthy than the throw. A
            // first registration reports failure on some systems while still leaving the
            // service awaiting approval, which is a state the user can act on.
        }

        return InstallResult(state: currentState(), failure: failure)
    }

    /// Unregister the daemon so a new version can be registered.
    static func unregister() {
        do {
            try service.unregister()
            NSLog("HelperInstaller: unregistered successfully")
        } catch {
            NSLog("HelperInstaller: unregister failed — \(error)")
        }
    }

    /// Opens System Settings directly to Login Items & Extensions. Apple provides this
    /// precisely so an app can hand the user to the switch it needs them to flip.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Version probe (XPC)

    /// Asks the daemon its version. Nil means it did not answer within the timeout, which is
    /// the observable difference between "registered" and "running".
    private static func probeVersion() -> String? {
        let connection = NSXPCConnection(
            machServiceName: kHelperMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        HelperConnection.pinToHelperSignature(connection)
        connection.resume()

        // `version` is written from the XPC reply queue and read here after the wait, and on
        // a timeout a late reply can still land. A lock makes both the handoff and that
        // straggler well-defined instead of a data race on a captured variable.
        let lock = NSLock()
        var version: String?
        let semaphore = DispatchSemaphore(value: 0)

        if let helper = connection.remoteObjectProxyWithErrorHandler({ _ in
            semaphore.signal()
        }) as? HelperProtocol {
            helper.getVersion { reported in
                lock.lock()
                version = reported
                lock.unlock()
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 2)
        connection.invalidate()
        lock.lock()
        defer { lock.unlock() }
        return version
    }
}
