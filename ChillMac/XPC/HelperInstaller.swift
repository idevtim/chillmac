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
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper.plist")
        let status = service.status
        NSLog("HelperInstaller: SMAppService status = \(status.rawValue)")
        return status == .enabled
    }

    /// Register the daemon. This is the only path that may prompt for authorization.
    static func register() -> Bool {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper.plist")
        do {
            try service.register()
            NSLog("HelperInstaller: registered successfully")
            return true
        } catch {
            NSLog("HelperInstaller: registration failed — \(error)")
            return false
        }
    }

    /// Unregister the daemon so a new version can be registered.
    static func unregister() {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper.plist")
        do {
            try service.unregister()
            NSLog("HelperInstaller: unregistered successfully")
        } catch {
            NSLog("HelperInstaller: unregister failed — \(error)")
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
