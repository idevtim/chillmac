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

    // MARK: - Legacy helper

    /// Where ChillMac before 1.8.1 installed its helper through SMJobBless.
    private static let legacyHelperPaths = [
        "/Library/LaunchDaemons/\(kHelperMachServiceName).plist",
        "/Library/PrivilegedHelperTools/\(kHelperMachServiceName)",
    ]

    /// Whether a helper installed by ChillMac before 1.8.1 is still on disk.
    ///
    /// It uses the same launchd label as the current helper, and while launchd has it loaded
    /// macOS refuses to register ours with "Operation not permitted". Nothing removes it on
    /// update, so anyone who installed an early version and kept updating ends up unable
    /// to set up fan control. Both paths are world-readable, so no privileges are needed.
    static var legacyHelperInstalled: Bool {
        legacyHelperPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Unloads and deletes the pre-1.8.1 helper. Asks for an administrator password through
    /// the standard macOS prompt. Blocking; returns nil on success or the reason it failed.
    static func removeLegacyHelper() -> String? {
        let paths = legacyHelperPaths.map { "'\($0)'" }.joined(separator: " ")
        // bootout fails harmlessly when the job is not loaded, so it must not stop the rm.
        let shell = "/bin/launchctl bootout system/\(kHelperMachServiceName) 2>/dev/null; /bin/rm -f \(paths)"
        let script = "do shell script \"\(shell)\" with prompt \"ChillMac needs to remove an old fan helper left by an earlier version.\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return "Couldn't remove the old helper: \(error.localizedDescription)"
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog("HelperInstaller: legacy helper removal failed — \(message)")
            if message.contains("-128") { return "The old helper wasn't removed because the password prompt was canceled." }
            return "Couldn't remove the old helper. \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        if legacyHelperInstalled { return "The old helper is still on disk after removal." }
        NSLog("HelperInstaller: removed legacy helper")
        return nil
    }

    static let legacyHelperMessage = "A fan helper from an older version of ChillMac is still installed and is blocking the new one. Remove it to continue."

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
        if legacyHelperInstalled {
            return InstallResult(state: currentState(), failure: legacyHelperMessage)
        }

        let status = service.status
        if status == .enabled || status == .requiresApproval {
            // register() on a live registration throws "already registered" and changes
            // nothing, so an in-place update has to unregister first.
            unregister()
            waitForUnregistration()
        }

        var failure: String?
        if let error = registerRetryingWhileBusy() {
            let nsError = error as NSError
            NSLog("HelperInstaller: registration failed — \(error)")
            failure = "macOS refused to install the helper: \(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
            // Fall through: the status read below is more trustworthy than the throw. A
            // first registration reports failure on some systems while still leaving the
            // service awaiting approval, which is a state the user can act on.
        } else {
            NSLog("HelperInstaller: registered successfully")
        }

        return InstallResult(state: currentState(), failure: failure)
    }

    /// `unregister()` returns before launchd has finished tearing the job down. Until it
    /// has, the status still reads as registered and a new `register()` is refused.
    private static func waitForUnregistration(timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = service.status
            if status == .notRegistered || status == .notFound { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        NSLog("HelperInstaller: registration still present %.0fs after unregister", timeout)
    }

    /// Registers, retrying while macOS answers "Operation not permitted".
    ///
    /// That refusal is transient right after an unregister: macOS is still removing the old
    /// registration and rejects the new one, then accepts the identical request a few
    /// seconds later. Reinstall used to surface it as a hard failure that a second click
    /// fixed. Anything else is returned at once, and so is a refusal that leaves the service
    /// registered or awaiting approval, since that is success as far as the user goes.
    private static func registerRetryingWhileBusy() -> Error? {
        let pauses: [TimeInterval] = [1, 2, 3, 4]
        var attempt = 0
        while true {
            do {
                try service.register()
                return nil
            } catch {
                let nsError = error as NSError
                let isBusy = nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1
                let status = service.status
                if status == .enabled || status == .requiresApproval { return nil }
                guard isBusy, attempt < pauses.count else { return error }
                NSLog("HelperInstaller: register refused (attempt \(attempt + 1)), retrying in \(pauses[attempt])s")
                Thread.sleep(forTimeInterval: pauses[attempt])
                attempt += 1
            }
        }
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
