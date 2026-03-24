import Foundation

class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        NSLog("HelperDelegate: incoming XPC connection from pid %d", newConnection.processIdentifier)

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()

        NSLog("HelperDelegate: accepted connection")
        return true
    }
}
