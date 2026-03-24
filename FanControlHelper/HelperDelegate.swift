import Foundation

class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // Verify the connecting process is our main app
        guard verifyCallerCodeSignature(connection: newConnection) else {
            NSLog("Rejected XPC connection from unverified caller (pid: \(newConnection.processIdentifier))")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()
        return true
    }

    private func verifyCallerCodeSignature(connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        var code: SecCode?

        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let callerCode = code else {
            return false
        }

        // Verify the caller is signed by the same team
        // In development (ad-hoc signing), we allow any local connection
        let requirement = "identifier \"com.timothymurphy.MacFanControl\" and anchor apple generic"
        var requirementRef: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &requirementRef) == errSecSuccess,
              let req = requirementRef else {
            // If we can't create the requirement, allow in debug builds
            #if DEBUG
            return true
            #else
            return false
            #endif
        }

        let result = SecCodeCheckValidity(callerCode, [], req)
        if result != errSecSuccess {
            #if DEBUG
            // Allow ad-hoc signed apps during development
            NSLog("Code signature check returned \(result), allowing in DEBUG mode")
            return true
            #else
            return false
            #endif
        }

        return true
    }
}
