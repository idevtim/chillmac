import Foundation
import IOKit

class HelperService: NSObject, HelperProtocol {
    private static var hasSetTestMode = false
    private static let logFile = "/tmp/MacFanControlHelper.log"

    private static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data)
            }
        }
    }

    func setFanSpeed(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void) {
        HelperService.log("setFanSpeed fan=\(fanIndex) rpm=\(rpm)")
        do {
            let smc = try SMCConnection()
            defer { smc.close() }

            #if arch(arm64)
            try enableTestModeIfNeeded(smc: smc)
            HelperService.log("  writing F\(fanIndex)Md=1 (manual mode)")
            try smc.writeFanModeKey(index: fanIndex, forced: true)
            #else
            try smc.writeForceMode(fanIndex: fanIndex, forced: true)
            #endif

            // Log key info for debugging encoding
            if let info = try? smc.getKeyInfo(SMCKey.fanTargetSpeed(fanIndex)) {
                let typeStr = fourCharCodeToString(info.dataType)
                HelperService.log("  F\(fanIndex)Tg keyInfo: size=\(info.dataSize) type='\(typeStr)'")
            }
            if let info = try? smc.getKeyInfo(SMCKey.fanMode(fanIndex)) {
                let typeStr = fourCharCodeToString(info.dataType)
                HelperService.log("  F\(fanIndex)Md keyInfo: size=\(info.dataSize) type='\(typeStr)'")
            }
            if let info = try? smc.getKeyInfo(SMCKey.testMode) {
                let typeStr = fourCharCodeToString(info.dataType)
                HelperService.log("  Ftst keyInfo: size=\(info.dataSize) type='\(typeStr)'")
            }

            HelperService.log("  writing F\(fanIndex)Tg=\(rpm)")
            try smc.writeFanSpeed(index: fanIndex, rpm: Double(rpm))

            // Read back to verify writes took effect
            let readBackTarget = (try? smc.readFanTargetSpeed(index: fanIndex)) ?? -1
            let readBackMode = (try? smc.readFanMode(index: fanIndex)) ?? false
            let readBackSpeed = (try? smc.readFanSpeed(index: fanIndex)) ?? -1
            HelperService.log("  readback: target=\(readBackTarget) mode=\(readBackMode ? "manual" : "auto") actual=\(readBackSpeed)")
            reply(true, nil)
        } catch {
            HelperService.log("  FAILED: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func setFanMode(fanIndex: Int, isAuto: Bool, reply: @escaping (Bool, String?) -> Void) {
        HelperService.log("setFanMode fan=\(fanIndex) auto=\(isAuto)")
        do {
            let smc = try SMCConnection()
            defer { smc.close() }

            if isAuto {
                #if arch(arm64)
                try smc.writeFanModeKey(index: fanIndex, forced: false)
                let fanCount = try smc.readFanCount()
                var anyManual = false
                for i in 0..<fanCount {
                    if i != fanIndex, let mode = try? smc.readFanMode(index: i), mode {
                        anyManual = true
                        break
                    }
                }
                if !anyManual {
                    try smc.writeTestMode(enabled: false)
                    HelperService.hasSetTestMode = false
                    HelperService.log("  cleared test mode (all fans auto)")
                }
                #else
                try smc.writeForceMode(fanIndex: fanIndex, forced: false)
                #endif
            } else {
                #if arch(arm64)
                try enableTestModeIfNeeded(smc: smc)
                try smc.writeFanModeKey(index: fanIndex, forced: true)
                #else
                try smc.writeForceMode(fanIndex: fanIndex, forced: true)
                #endif
            }

            HelperService.log("  success")
            reply(true, nil)
        } catch {
            HelperService.log("  FAILED: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(kHelperVersion)
    }

    func dumpFanKeys(reply: @escaping (String) -> Void) {
        var result = ""
        do {
            let smc = try SMCConnection()
            defer { smc.close() }

            let fanCount = try smc.readFanCount()
            result += "Fan count: \(fanCount)\n"

            for i in 0..<fanCount {
                result += "\n--- Fan \(i) ---\n"
                for key in [
                    SMCKey.fanActualSpeed(i),
                    SMCKey.fanMinSpeed(i),
                    SMCKey.fanMaxSpeed(i),
                    SMCKey.fanTargetSpeed(i),
                    SMCKey.fanMode(i)
                ] {
                    do {
                        let info = try smc.getKeyInfo(key)
                        let output = try smc.readKey(key)
                        let b = output.bytes
                        let typeStr = fourCharCodeToString(info.dataType)
                        let rawHex = String(format: "%02X %02X %02X %02X", b.0, b.1, b.2, b.3)
                        let fpe2 = decodeFPE2(b.0, b.1)
                        let flt = decodeFloat32(b.0, b.1, b.2, b.3)
                        result += "  \(key): size=\(info.dataSize) type='\(typeStr)' raw=[\(rawHex)] fpe2=\(fpe2) flt=\(flt)\n"
                    } catch {
                        result += "  \(key): ERROR \(error)\n"
                    }
                }
            }
        } catch {
            result += "ERROR: \(error)\n"
        }
        HelperService.log("dumpFanKeys:\n\(result)")
        reply(result)
    }

    #if arch(arm64)
    private func enableTestModeIfNeeded(smc: SMCConnection) throws {
        if !HelperService.hasSetTestMode {
            HelperService.log("  enabling test mode (Ftst=1)")
            try smc.writeTestMode(enabled: true)
            HelperService.hasSetTestMode = true
            HelperService.log("  test mode enabled")
        }
    }
    #endif

    static func cleanupOnExit() {
        #if arch(arm64)
        if hasSetTestMode {
            log("cleanup: resetting fans to auto")
            if let smc = try? SMCConnection() {
                try? smc.writeTestMode(enabled: false)
                if let fanCount = try? smc.readFanCount() {
                    for i in 0..<fanCount {
                        try? smc.writeFanModeKey(index: i, forced: false)
                    }
                }
                smc.close()
            }
        }
        #endif
    }
}
