import Foundation

final class HelperConnection {
    private var connection: NSXPCConnection?

    func connect() -> HelperProtocol? {
        let conn = NSXPCConnection(
            machServiceName: kHelperMachServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            NSLog("HelperConnection: XPC connection invalidated")
            self?.connection = nil
        }
        conn.interruptionHandler = {
            NSLog("HelperConnection: XPC connection interrupted")
        }
        conn.resume()
        self.connection = conn
        return conn.remoteObjectProxyWithErrorHandler { error in
            NSLog("HelperConnection: XPC proxy error: %@", error.localizedDescription)
        } as? HelperProtocol
    }

    func setFanSpeed(fanIndex: Int, rpm: Int, completion: @escaping (Bool, String?) -> Void) {
        NSLog("HelperConnection: requesting setFanSpeed fan=%d rpm=%d", fanIndex, rpm)
        guard let helper = connect() else {
            NSLog("HelperConnection: connect() returned nil")
            completion(false, "Failed to connect to helper")
            return
        }
        helper.setFanSpeed(fanIndex: fanIndex, rpm: rpm, reply: completion)
    }

    func setFanMode(fanIndex: Int, isAuto: Bool, completion: @escaping (Bool, String?) -> Void) {
        NSLog("HelperConnection: requesting setFanMode fan=%d auto=%d", fanIndex, isAuto ? 1 : 0)
        guard let helper = connect() else {
            NSLog("HelperConnection: connect() returned nil")
            completion(false, "Failed to connect to helper")
            return
        }
        helper.setFanMode(fanIndex: fanIndex, isAuto: isAuto, reply: completion)
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
