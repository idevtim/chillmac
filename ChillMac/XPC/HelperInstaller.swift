import Foundation
import ServiceManagement

enum HelperInstaller {

    enum HelperStatus {
        case runningCorrectVersion
        case runningWrongVersion
        case notRunning
    }

    // MARK: - Registration (SMAppService)

    /// Whether the daemon is registered with launchd via SMAppService.
    static func isRegistered() -> Bool {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper3.plist")
        let status = service.status
        NSLog("HelperInstaller: SMAppService status = \(status.rawValue)")
        return status == .enabled
    }

    /// Register the daemon. This is the only path that may prompt for authorization.
    static func register() -> Bool {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper3.plist")
        do {
            try service.register()
            NSLog("HelperInstaller: registered successfully — status=\(service.status.rawValue)")
            return true
        } catch {
            NSLog("HelperInstaller: registration failed — \(error) status=\(service.status.rawValue)")
            // Code 1 / disabled BTM entry — send the user to Login Items to re-enable.
            if service.status == .requiresApproval || service.status == .notRegistered {
                openLoginItemsSettings()
            }
            return false
        }
    }

    /// Unregister the daemon so a new version can be registered.
    static func unregister() {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper3.plist")
        do {
            try service.unregister()
            NSLog("HelperInstaller: unregistered successfully")
        } catch {
            NSLog("HelperInstaller: unregister failed — \(error)")
        }
    }

    /// Drop then re-register. Required when the helper binary or BundleProgram path changes.
    static func reregister() -> Bool {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper3.plist")
        let done = DispatchSemaphore(value: 0)
        service.unregister { error in
            if let error {
                NSLog("HelperInstaller: async unregister failed — \(error)")
            } else {
                NSLog("HelperInstaller: async unregister completed")
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        Thread.sleep(forTimeInterval: 0.25)
        return register()
    }


    /// Open Login Items / Background approvals when the daemon is waiting on admin consent.
    static func openApprovalSettingsIfNeeded() {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper3.plist")
        if service.status == .requiresApproval {
            NSLog("HelperInstaller: daemon requires approval — opening System Settings")
            openLoginItemsSettings()
        }
    }

    /// Always open System Settings → Login Items (Settings Helper row).
    static func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: - Version check (XPC)

    static func checkHelperStatus() -> HelperStatus {
        let connection = NSXPCConnection(
            machServiceName: kHelperMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()

        var status: HelperStatus = .notRunning
        let semaphore = DispatchSemaphore(value: 0)

        if let helper = connection.remoteObjectProxyWithErrorHandler({ _ in
            semaphore.signal()
        }) as? HelperProtocol {
            helper.getVersion { version in
                if version == kHelperVersion {
                    status = .runningCorrectVersion
                } else {
                    NSLog("HelperInstaller: installed version '%@' != expected '%@', needs update", version, kHelperVersion)
                    status = .runningWrongVersion
                }
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 2)
        connection.invalidate()
        return status
    }
}
