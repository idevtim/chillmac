import Foundation
import IOKit

class HelperService: NSObject, HelperProtocol {
    private static var hasSetTestMode = false
    private static let logFile = "/tmp/ChillMacHelper.log"

    /// Serialises every SMC access in the daemon. XPC delivers each client connection's
    /// messages on its own queue and `HelperDelegate` hands out a fresh `HelperService` per
    /// connection, so the shared connection and `hasSetTestMode` need one owner.
    private static let smcQueue = DispatchQueue(label: "com.idevtim.ChillMac.Helper.smc")

    /// One long-lived SMC connection instead of an IOServiceOpen/Close pair per command.
    /// Performance mode issues a write per fan every 2 seconds for the machine's whole
    /// uptime, and reopening the driver each time was the bulk of that cost.
    /// Must only be touched on `smcQueue`.
    private static var sharedSMC: SMCConnection?

    /// Runs `body` on `smcQueue` with the shared connection, opening one on first use.
    /// A throwing body drops the connection so the next command reopens it — otherwise a
    /// single bad state in the driver would poison fan control until the daemon restarted.
    private static func withSMC<T>(_ body: (SMCConnection) throws -> T) throws -> T {
        try smcQueue.sync {
            if sharedSMC == nil {
                sharedSMC = try SMCConnection()
            }
            guard let smc = sharedSMC else { throw SMCError.failedToOpen }
            do {
                return try body(smc)
            } catch {
                sharedSMC = nil
                smc.close()
                throw error
            }
        }
    }

    private static func log(_ message: String) {
        // File logging disabled — uncomment to re-enable
        // let timestamp = ISO8601DateFormatter().string(from: Date())
        // let line = "[\(timestamp)] \(message)\n"
        // if let data = line.data(using: .utf8) {
        //     if FileManager.default.fileExists(atPath: logFile) {
        //         if let handle = FileHandle(forWritingAtPath: logFile) {
        //             handle.seekToEndOfFile()
        //             handle.write(data)
        //             handle.closeFile()
        //         }
        //     } else {
        //         FileManager.default.createFile(atPath: logFile, contents: data)
        //     }
        // }
    }

    func setFanSpeed(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void) {
        HelperService.log("setFanSpeed fan=\(fanIndex) rpm=\(rpm)")
        do {
            try HelperService.withSMC { smc in
                #if arch(arm64)
                try HelperService.enableTestModeIfNeededLocked(smc: smc)
                try smc.writeFanModeKey(index: fanIndex, forced: true)
                #else
                try HelperService.setIntelForcedMode(smc: smc, fanIndex: fanIndex, forced: true)
                #endif

                try smc.writeFanSpeed(index: fanIndex, rpm: Double(rpm))
            }
            reply(true, nil)
        } catch {
            HelperService.log("  FAILED: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func setFanMode(fanIndex: Int, isAuto: Bool, reply: @escaping (Bool, String?) -> Void) {
        HelperService.log("setFanMode fan=\(fanIndex) auto=\(isAuto)")
        do {
            try HelperService.withSMC { smc in
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
                    try HelperService.setIntelForcedMode(smc: smc, fanIndex: fanIndex, forced: false)
                    #endif
                } else {
                    #if arch(arm64)
                    try HelperService.enableTestModeIfNeededLocked(smc: smc)
                    try smc.writeFanModeKey(index: fanIndex, forced: true)
                    #else
                    try HelperService.setIntelForcedMode(smc: smc, fanIndex: fanIndex, forced: true)
                    #endif
                }
            }
            reply(true, nil)
        } catch {
            HelperService.log("  FAILED: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(kHelperVersion)
    }

    func memoryFootprint(reply: @escaping (UInt64) -> Void) {
        reply(ProcessMemory.footprintBytes() ?? 0)
    }

    func dumpFanKeys(reply: @escaping (String) -> Void) {
        // Also scan for all temperature keys
        scanTemperatureKeys()

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

    private func scanTemperatureKeys() {
        do {
            let smc = try SMCConnection()
            defer { smc.close() }

            let keyCount = try smc.getKeyCount()
            HelperService.log("Scanning \(keyCount) SMC keys for temperature sensors...")

            var tempKeys: [(key: String, value: Double, size: UInt32, type: String)] = []

            for i in 0..<keyCount {
                guard let keyName = try? smc.getKeyAtIndex(i) else { continue }
                guard keyName.hasPrefix("T") else { continue }
                guard let info = try? smc.getKeyInfo(keyName) else { continue }
                guard let output = try? smc.readKey(keyName) else { continue }

                let typeStr = fourCharCodeToString(info.dataType)
                var temp: Double = 0

                if info.dataSize >= 4 {
                    temp = decodeFloat32(output.bytes.0, output.bytes.1, output.bytes.2, output.bytes.3)
                } else {
                    temp = decodeSP78(output.bytes.0, output.bytes.1)
                }

                if temp > 0 && temp < 150 {
                    tempKeys.append((keyName, temp, info.dataSize, typeStr))
                }
            }

            var result = "Found \(tempKeys.count) temperature keys:\n"
            for tk in tempKeys {
                result += "  \(tk.key): \(String(format: "%.1f", tk.value))°C (size=\(tk.size) type='\(tk.type)')\n"
            }
            HelperService.log(result)
        } catch {
            HelperService.log("Temperature scan failed: \(error)")
        }
    }

    #if !arch(arm64)
    /// Puts an Intel fan into (or out of) forced mode.
    ///
    /// Two different mechanisms exist and which one works depends on the machine. Pre-T2
    /// Intel Macs use the legacy `FS!` force bitmask. T2 Macs (2018 and later) do not honour
    /// `FS!` at all and instead use the per-fan `F{i}Md` key, the same one Apple Silicon
    /// uses. Writing only `FS!` is why manual control and Performance Mode silently did
    /// nothing on T2 hardware: the write reported success, the firmware ignored it, and the
    /// following `F{i}Tg` target write was discarded because the fan was never forced.
    ///
    /// So write both and succeed if either lands. Requiring both would swap the bug from one
    /// generation to the other, since neither machine has the other's key.
    private static func setIntelForcedMode(smc: SMCConnection, fanIndex: Int, forced: Bool) throws {
        var succeeded = false
        var lastError: Error?

        // Pre-T2 path.
        do {
            try smc.writeForceMode(fanIndex: fanIndex, forced: forced)
            succeeded = true
        } catch {
            lastError = error
        }

        // T2 path.
        do {
            try smc.writeFanModeKey(index: fanIndex, forced: forced)
            succeeded = true
        } catch {
            lastError = error
        }

        if !succeeded, let lastError {
            log("  no usable fan mode key on this Mac: \(lastError)")
            throw lastError
        }
    }
    #endif

    #if arch(arm64)
    /// Must be called from inside `withSMC` — it reads and writes `hasSetTestMode`,
    /// which is owned by `smcQueue`.
    private static func enableTestModeIfNeededLocked(smc: SMCConnection) throws {
        guard !hasSetTestMode else { return }
        log("  enabling test mode (Ftst=1)")
        try smc.writeTestMode(enabled: true)
        hasSetTestMode = true
        log("  test mode enabled")
    }
    #endif

    /// Called from a signal handler, so it deliberately opens its own connection rather than
    /// going through `withSMC` — `smcQueue.sync` would deadlock if the signal landed while a
    /// command was in flight on that queue.
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
