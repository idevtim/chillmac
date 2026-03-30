import Foundation
import IOKit

final class SMCConnection {
    private var connection: io_connect_t = 0
    private var isOpen = false
    /// Cache key info (dataSize) per fourCharCode — avoids redundant getKeyInfo IOKit calls
    private var keyInfoCache: [UInt32: UInt32] = [:]

    init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            throw SMCError.driverNotFound
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard result == kIOReturnSuccess else {
            throw SMCError.failedToOpen
        }
        isOpen = true
    }

    deinit {
        close()
    }

    func close() {
        if isOpen {
            IOServiceClose(connection)
            isOpen = false
        }
    }

    // MARK: - Low-level Read

    func readKey(_ key: String) throws -> SMCParamStruct {
        var input = SMCParamStruct()
        let fcc = fourCharCode(key)
        input.key = fcc

        // Check cache for dataSize to skip the getKeyInfo IOKit call
        let dataSize: UInt32
        if let cached = keyInfoCache[fcc] {
            dataSize = cached
        } else {
            input.data8 = SMCSelector.getKeyInfo.rawValue
            var infoOutput = SMCParamStruct()
            let result = callSMC(&input, output: &infoOutput)
            guard result == kIOReturnSuccess else {
                throw SMCError.keyNotFound(key)
            }
            dataSize = infoOutput.keyInfo.dataSize
            keyInfoCache[fcc] = dataSize
        }

        // Read the actual value
        input.keyInfo.dataSize = dataSize
        input.data8 = SMCSelector.readKey.rawValue

        var output = SMCParamStruct()
        let result = callSMC(&input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed(result)
        }
        if output.result == 132 {
            throw SMCError.keyNotFound(key)
        }
        // Preserve the data size for callers that need it
        output.keyInfo.dataSize = dataSize
        return output
    }

    // MARK: - Fan Reads

    func readFanCount() throws -> Int {
        let output = try readKey(SMCKey.fanCount)
        return Int(output.bytes.0)
    }

    func readFanSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanActualSpeed(index))
        return decodeFanValue(output)
    }

    func readFanMinSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanMinSpeed(index))
        return decodeFanValue(output)
    }

    func readFanMaxSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanMaxSpeed(index))
        return decodeFanValue(output)
    }

    func readFanTargetSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanTargetSpeed(index))
        return decodeFanValue(output)
    }

    func readFanMode(index: Int) throws -> Bool {
        let output = try readKey(SMCKey.fanMode(index))
        return output.bytes.0 != 0
    }

    // MARK: - Temperature Reads

    func readTemperature(key: String) throws -> Double {
        let output = try readKey(key)
        // Apple Silicon: 4-byte little-endian float; Intel: 2-byte sp78
        if output.keyInfo.dataSize >= 4 {
            let val = decodeFloat32(output.bytes.0, output.bytes.1, output.bytes.2, output.bytes.3)
            if val > -40 && val < 200 { return val }
        }
        return decodeSP78(output.bytes.0, output.bytes.1)
    }

    // MARK: - Write Operations (requires root)

    func writeKey(_ key: String, bytes: [UInt8]) throws {
        var input = SMCParamStruct()
        let fcc = fourCharCode(key)
        input.key = fcc
        input.data8 = SMCSelector.getKeyInfo.rawValue

        var infoOutput = SMCParamStruct()
        var result = callSMC(&input, output: &infoOutput)
        guard result == kIOReturnSuccess else {
            throw SMCError.keyNotFound(key)
        }
        // Populate cache for future readKey calls
        keyInfoCache[fcc] = infoOutput.keyInfo.dataSize

        input = SMCParamStruct()
        input.key = fcc
        input.data8 = SMCSelector.writeKey.rawValue
        input.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        input.keyInfo.dataType = infoOutput.keyInfo.dataType

        withUnsafeMutablePointer(to: &input.bytes) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            for (i, byte) in bytes.prefix(32).enumerated() {
                raw.storeBytes(of: byte, toByteOffset: i, as: UInt8.self)
            }
        }

        var output = SMCParamStruct()
        result = callSMC(&input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.writeFailed(result)
        }
    }

    /// Get key info (dataSize, dataType) for debugging
    func getKeyInfo(_ key: String) throws -> (dataSize: UInt32, dataType: UInt32) {
        var input = SMCParamStruct()
        input.key = fourCharCode(key)
        input.data8 = SMCSelector.getKeyInfo.rawValue
        var output = SMCParamStruct()
        let result = callSMC(&input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.keyNotFound(key)
        }
        return (output.keyInfo.dataSize, output.keyInfo.dataType)
    }

    /// Write fan target speed — uses correct encoding based on key's data size
    func writeFanSpeed(index: Int, rpm: Double) throws {
        let key = SMCKey.fanTargetSpeed(index)
        let info = try getKeyInfo(key)

        let bytes: [UInt8]
        if info.dataSize == 2 {
            let encoded = encodeFPE2(rpm)
            bytes = [encoded.0, encoded.1]
        } else {
            // 4-byte key: use float32
            bytes = encodeFloat32(rpm)
        }
        try writeKey(key, bytes: bytes)
    }

    /// Write per-fan mode key (F{i}Md) — used on Apple Silicon
    func writeFanModeKey(index: Int, forced: Bool) throws {
        try writeKey(SMCKey.fanMode(index), bytes: [forced ? 1 : 0])
    }

    /// Write FS! force bitmask — used on Intel
    func writeForceMode(fanIndex: Int, forced: Bool) throws {
        let output = try readKey(SMCKey.forceMode)
        var current = (UInt16(output.bytes.0) << 8) | UInt16(output.bytes.1)
        let bit = UInt16(1 << fanIndex)
        if forced {
            current |= bit
        } else {
            current &= ~bit
        }
        try writeKey(SMCKey.forceMode, bytes: [UInt8(current >> 8), UInt8(current & 0xFF)])
    }

    func writeTestMode(enabled: Bool) throws {
        try writeKey(SMCKey.testMode, bytes: [enabled ? 1 : 0])
    }

    // MARK: - Key Enumeration

    /// Get total number of SMC keys
    func getKeyCount() throws -> Int {
        let output = try readKey("#KEY")
        let count = (UInt32(output.bytes.0) << 24) | (UInt32(output.bytes.1) << 16) |
                    (UInt32(output.bytes.2) << 8) | UInt32(output.bytes.3)
        return Int(count)
    }

    /// Get the key at a given index
    func getKeyAtIndex(_ index: Int) throws -> String {
        var input = SMCParamStruct()
        input.data32 = UInt32(index)
        input.data8 = SMCSelector.getKeyFromIndex.rawValue

        var output = SMCParamStruct()
        let result = callSMC(&input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed(result)
        }
        return fourCharCodeToString(output.key)
    }

    // MARK: - Internal

    /// Decode a fan speed value — tries float32 for 4-byte keys, falls back to fpe2
    private func decodeFanValue(_ output: SMCParamStruct) -> Double {
        if output.keyInfo.dataSize >= 4 {
            let floatValue = decodeFloat32(output.bytes.0, output.bytes.1, output.bytes.2, output.bytes.3)
            if floatValue > 0 && floatValue < 20000 {
                return floatValue
            }
        }
        // fpe2 fallback (works for 2-byte keys and 4-byte keys with fpe2-in-first-2-bytes)
        let fpe2Value = decodeFPE2(output.bytes.0, output.bytes.1)
        if fpe2Value > 0 {
            return fpe2Value
        }
        // Last resort: try float32 even if out of range
        if output.keyInfo.dataSize >= 4 {
            return decodeFloat32(output.bytes.0, output.bytes.1, output.bytes.2, output.bytes.3)
        }
        return fpe2Value
    }

    private func callSMC(_ input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        return IOConnectCallStructMethod(
            connection,
            UInt32(2), // kSMCHandleYPCEvent
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }
}
