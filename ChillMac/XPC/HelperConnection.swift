import Foundation

final class HelperConnection {
    /// Guards `_connection`. Recursive so an inline invalidation callback can't deadlock us.
    private let lock = NSRecursiveLock()
    private var _connection: NSXPCConnection?

    /// Returns a proxy, creating the underlying connection on first use.
    /// Safe to call from any thread — `poll()` drives this from `smcQueue` while the UI
    /// drives it from main.
    func connect(completionOnError: ((Bool, String?) -> Void)? = nil) -> HelperProtocol? {
        lock.lock()
        defer { lock.unlock() }

        if let conn = _connection {
            return proxy(for: conn, completionOnError: completionOnError)
        }

        let conn = NSXPCConnection(
            machServiceName: kHelperMachServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            NSLog("HelperConnection: XPC connection invalidated")
            self?.clear(conn)
        }
        conn.interruptionHandler = {
            NSLog("HelperConnection: XPC connection interrupted")
        }
        conn.resume()
        _connection = conn
        return proxy(for: conn, completionOnError: completionOnError)
    }

    private func proxy(
        for conn: NSXPCConnection,
        completionOnError: ((Bool, String?) -> Void)? = nil
    ) -> HelperProtocol? {
        conn.remoteObjectProxyWithErrorHandler { error in
            NSLog("HelperConnection: XPC proxy error: %@", error.localizedDescription)
            completionOnError?(false, error.localizedDescription)
        } as? HelperProtocol
    }

    /// Drop `conn` only if it is still the live connection — a late invalidation from a
    /// replaced connection must not tear down the one that succeeded it.
    private func clear(_ conn: NSXPCConnection) {
        lock.lock()
        defer { lock.unlock() }
        if _connection === conn {
            _connection = nil
        }
    }

    func setFanSpeed(fanIndex: Int, rpm: Int, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = connect(completionOnError: completion) else {
            NSLog("HelperConnection: connect() returned nil")
            completion(false, "Failed to connect to helper")
            return
        }
        helper.setFanSpeed(fanIndex: fanIndex, rpm: rpm, reply: completion)
    }

    func setFanMode(fanIndex: Int, isAuto: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = connect(completionOnError: completion) else {
            NSLog("HelperConnection: connect() returned nil")
            completion(false, "Failed to connect to helper")
            return
        }
        helper.setFanMode(fanIndex: fanIndex, isAuto: isAuto, reply: completion)
    }

    /// Resident footprint of the helper daemon, in bytes. Replies 0 when unavailable —
    /// the helper runs as root, so the app cannot read this itself.
    func memoryFootprint(completion: @escaping (UInt64) -> Void) {
        guard let helper = connect() else {
            completion(0)
            return
        }
        helper.memoryFootprint(reply: completion)
    }

    func disconnect() {
        lock.lock()
        let conn = _connection
        _connection = nil
        lock.unlock()
        conn?.invalidate()
    }
}
