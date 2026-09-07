import Foundation

let kHelperMachServiceName = "com.idevtim.ChillMac.Helper"
// 1.3.0 enforces a code signing requirement on incoming XPC connections. The bump is what
// makes existing installs pick it up: `HelperInstaller.checkHelperStatus` compares against
// this string, and without a change the already-registered 1.2.0 daemon — which accepts
// connections from any process on the machine — keeps running untouched.
let kHelperVersion = "1.3.0"

@objc protocol HelperProtocol {
    func setFanSpeed(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void)
    func setFanMode(fanIndex: Int, isAuto: Bool, reply: @escaping (Bool, String?) -> Void)
    func getVersion(reply: @escaping (String) -> Void)
    func dumpFanKeys(reply: @escaping (String) -> Void)
    /// Physical memory footprint of the helper process in bytes, 0 if unreadable.
    /// The app can't measure this itself — the daemon runs as root.
    func memoryFootprint(reply: @escaping (UInt64) -> Void)
}
