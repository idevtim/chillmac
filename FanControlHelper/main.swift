import Foundation

let listener = NSXPCListener(machServiceName: kHelperMachServiceName)

// Pin the listener to ChillMac itself before it starts accepting anything. Connections that
// fail the requirement are rejected by XPC before the delegate is ever consulted, so this is
// the real gate; HelperDelegate only has to handle the case where no requirement exists.
let clientsAreAuthenticated: Bool
switch XPCSecurity.policy(forIdentifier: XPCSecurity.appIdentifier) {
case .require(let requirement):
    listener.setConnectionCodeSigningRequirement(requirement)
    NSLog("Helper: client requirement installed — %@", requirement)
    clientsAreAuthenticated = true
case .cannotVerify:
    NSLog("Helper: no team identifier on this binary; callers cannot be authenticated")
    clientsAreAuthenticated = false
}

let delegate = HelperDelegate(clientsAreAuthenticated: clientsAreAuthenticated)
listener.delegate = delegate
listener.resume()

// Install signal handlers to clean up test mode on termination
signal(SIGTERM) { _ in
    HelperService.cleanupOnExit()
    exit(0)
}
signal(SIGINT) { _ in
    HelperService.cleanupOnExit()
    exit(0)
}

RunLoop.current.run()
