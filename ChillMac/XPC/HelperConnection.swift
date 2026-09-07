import Foundation

final class HelperConnection {
    /// Guards `_connection`. Recursive so an inline invalidation callback can't deadlock us.
    private let lock = NSRecursiveLock()
    private var _connection: NSXPCConnection?

    /// Returns a proxy, creating the underlying connection on first use.
    /// Safe to call from any thread — `poll()` drives this from `smcQueue` while the UI
    /// drives it from main.
    func connect() -> HelperProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return proxy(for: liveConnection())
    }

    /// The live connection, created on first use. Must be called with `lock` held.
    private func liveConnection() -> NSXPCConnection {
        if let conn = _connection {
            return conn
        }

        let conn = NSXPCConnection(
            machServiceName: kHelperMachServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        // Authenticate the daemon before talking to it. Must be set before `resume`, and
        // exactly once per connection.
        HelperConnection.pinToHelperSignature(conn)
        conn.invalidationHandler = { [weak self] in
            NSLog("HelperConnection: XPC connection invalidated")
            self?.clear(conn)
        }
        conn.interruptionHandler = {
            NSLog("HelperConnection: XPC connection interrupted")
        }
        conn.resume()
        _connection = conn
        return conn
    }

    /// Sets every fan back to auto and waits briefly for the helper to confirm.
    ///
    /// Called from `applicationWillTerminate`, so the wait is bounded on purpose. An earlier
    /// version used `synchronousRemoteObjectProxy`, which blocks the main thread with no
    /// timeout: when the daemon cannot start, nothing ever replies and the app becomes
    /// unquittable except through Force Quit. Getting the fans back to auto matters, but not
    /// enough to trade away the ability to quit.
    ///
    /// Each fan settles exactly once, on whichever comes first, the reply or the proxy's
    /// error handler, so a dead connection returns immediately instead of burning the
    /// whole timeout.
    func setFansToAutoAndWait(fanCount: Int, timeout: TimeInterval = 1.5) {
        guard fanCount > 0 else { return }

        lock.lock()
        let conn = liveConnection()
        lock.unlock()

        let group = DispatchGroup()
        let settleLock = NSLock()
        var settled = Set<Int>()

        func settle(_ index: Int) {
            settleLock.lock()
            let isFirst = settled.insert(index).inserted
            settleLock.unlock()
            if isFirst { group.leave() }
        }

        for i in 0..<fanCount {
            group.enter()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                NSLog("HelperConnection: fan %d reset at quit failed: %@", i, error.localizedDescription)
                settle(i)
            }) as? HelperProtocol else {
                settle(i)
                continue
            }
            proxy.setFanMode(fanIndex: i, isAuto: true) { _, _ in settle(i) }
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            NSLog("HelperConnection: fan reset at quit timed out after %.1fs", timeout)
        }
    }

    /// Requires the daemon on the other end to be the helper this build shipped with.
    /// Shared with `HelperInstaller`, which opens its own connection for the version probe.
    /// A build with no team identity (local ad-hoc signing) has nothing to pin against and
    /// connects unpinned — the helper does the same, and refuses everyone outside DEBUG.
    static func pinToHelperSignature(_ connection: NSXPCConnection) {
        switch XPCSecurity.policy(forIdentifier: XPCSecurity.helperIdentifier) {
        case .require(let requirement):
            connection.setCodeSigningRequirement(requirement)
        case .cannotVerify:
            NSLog("HelperConnection: no team identifier on this build; helper identity unverified")
        }
    }

    private func proxy(for conn: NSXPCConnection) -> HelperProtocol? {
        conn.remoteObjectProxyWithErrorHandler { error in
            NSLog("HelperConnection: XPC proxy error: %@", error.localizedDescription)
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
        guard let helper = connect() else {
            NSLog("HelperConnection: connect() returned nil")
            completion(false, "Failed to connect to helper")
            return
        }
        helper.setFanSpeed(fanIndex: fanIndex, rpm: rpm, reply: completion)
    }

    func setFanMode(fanIndex: Int, isAuto: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = connect() else {
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
