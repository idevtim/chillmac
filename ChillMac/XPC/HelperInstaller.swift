import Foundation
import ServiceManagement

enum HelperInstaller {
    static func installHelper() -> Bool {
        if #available(macOS 13.0, *) {
            return installWithSMAppService()
        } else {
            return installWithSMJobBless()
        }
    }

    @available(macOS 13.0, *)
    private static func installWithSMAppService() -> Bool {
        let service = SMAppService.daemon(plistName: "com.idevtim.ChillMac.Helper.plist")
        do {
            try service.register()
            return true
        } catch {
            NSLog("SMAppService registration failed: \(error)")
            // Fall back to SMJobBless
            return installWithSMJobBless()
        }
    }

    private static func installWithSMJobBless() -> Bool {
        var authRef: AuthorizationRef?
        let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]

        let status = AuthorizationCreate(nil, nil, flags, &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            NSLog("Authorization failed: \(status)")
            return false
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            kHelperMachServiceName as CFString,
            auth,
            &error
        )

        if !success {
            let cfError = error?.takeRetainedValue()
            NSLog("SMJobBless failed: \(cfError?.localizedDescription ?? "unknown")")
        }

        return success
    }

    static func isHelperInstalled() -> Bool {
        let connection = NSXPCConnection(
            machServiceName: kHelperMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()

        var matchesVersion = false
        let semaphore = DispatchSemaphore(value: 0)

        if let helper = connection.remoteObjectProxyWithErrorHandler({ _ in
            semaphore.signal()
        }) as? HelperProtocol {
            helper.getVersion { version in
                matchesVersion = (version == kHelperVersion)
                if !matchesVersion {
                    NSLog("HelperInstaller: installed version '%@' != expected '%@', needs update", version, kHelperVersion)
                }
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 2)
        connection.invalidate()
        return matchesVersion
    }
}
