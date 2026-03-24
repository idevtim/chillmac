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
            self?.connection = nil
        }
        conn.resume()
        self.connection = conn
        return conn.remoteObjectProxyWithErrorHandler { error in
            NSLog("XPC error: \(error)")
        } as? HelperProtocol
    }

    func setFanSpeed(fanIndex: Int, rpm: Int, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = connect() else {
            completion(false, "Failed to connect to helper")
            return
        }
        helper.setFanSpeed(fanIndex: fanIndex, rpm: rpm, reply: completion)
    }

    func setFanMode(fanIndex: Int, isAuto: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = connect() else {
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
