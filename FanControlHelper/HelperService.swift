import Foundation
import IOKit

class HelperService: NSObject, HelperProtocol {
    private static var hasSetTestMode = false

    func setFanSpeed(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void) {
        do {
            let smc = try SMCConnection()
            defer { smc.close() }

            // On Apple Silicon, enable test mode to bypass thermalmonitord
            #if arch(arm64)
            try enableTestModeIfNeeded(smc: smc)
            #endif

            // Set force mode for this fan
            try smc.writeForceMode(fanIndex: fanIndex, forced: true)

            // Write target speed
            try smc.writeFanSpeed(index: fanIndex, rpm: Double(rpm))

            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func setFanMode(fanIndex: Int, isAuto: Bool, reply: @escaping (Bool, String?) -> Void) {
        do {
            let smc = try SMCConnection()
            defer { smc.close() }

            if isAuto {
                // Return to automatic control
                try smc.writeForceMode(fanIndex: fanIndex, forced: false)

                #if arch(arm64)
                // Check if any fans are still in manual mode before disabling test mode
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
                }
                #endif
            } else {
                #if arch(arm64)
                try enableTestModeIfNeeded(smc: smc)
                #endif
                try smc.writeForceMode(fanIndex: fanIndex, forced: true)
            }

            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(kHelperVersion)
    }

    // MARK: - Apple Silicon Test Mode

    #if arch(arm64)
    private func enableTestModeIfNeeded(smc: SMCConnection) throws {
        if !HelperService.hasSetTestMode {
            try smc.writeTestMode(enabled: true)
            HelperService.hasSetTestMode = true
        }
    }
    #endif

    static func cleanupOnExit() {
        #if arch(arm64)
        if hasSetTestMode {
            if let smc = try? SMCConnection() {
                try? smc.writeTestMode(enabled: false)
                // Reset all fans to auto
                if let fanCount = try? smc.readFanCount() {
                    for i in 0..<fanCount {
                        try? smc.writeForceMode(fanIndex: i, forced: false)
                    }
                }
                smc.close()
            }
        }
        #endif
    }
}
