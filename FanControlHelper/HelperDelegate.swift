import Foundation

class HelperDelegate: NSObject, NSXPCListenerDelegate {

    /// Whether the listener was able to install a code signing requirement. When it was,
    /// XPC has already rejected anything that fails it before this delegate is consulted,
    /// so reaching `shouldAcceptNewConnection` means the peer is authenticated.
    private let clientsAreAuthenticated: Bool

    init(clientsAreAuthenticated: Bool) {
        self.clientsAreAuthenticated = clientsAreAuthenticated
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        if !clientsAreAuthenticated {
            // No requirement is installed, so this connection is unverified. Only reachable
            // in development, where ad-hoc signing makes authentication impossible by
            // construction. A release build always has a requirement, and XPC applies it
            // before this delegate runs.
            #if DEBUG
            NSLog("HelperDelegate: DEBUG build — accepting unverified connection from pid %d",
                  newConnection.processIdentifier)
            #else
            NSLog("HelperDelegate: rejecting unverified connection from pid %d",
                  newConnection.processIdentifier)
            return false
            #endif
        }

        NSLog("HelperDelegate: incoming XPC connection from pid %d", newConnection.processIdentifier)

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()

        NSLog("HelperDelegate: accepted connection")
        return true
    }
}
