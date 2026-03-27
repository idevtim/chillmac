import Foundation

let kHelperMachServiceName = "com.idevtim.ChillMac.Helper"
let kHelperVersion = "8.1"

@objc protocol HelperProtocol {
    func setFanSpeed(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void)
    func setFanMode(fanIndex: Int, isAuto: Bool, reply: @escaping (Bool, String?) -> Void)
    func getVersion(reply: @escaping (String) -> Void)
    func dumpFanKeys(reply: @escaping (String) -> Void)
}
