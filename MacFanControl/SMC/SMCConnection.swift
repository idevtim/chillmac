import Foundation
import IOKit

final class SMCConnection {
    private var connection: io_connect_t = 0
    private var isOpen = false

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
        input.key = fourCharCode(key)
        input.data8 = SMCSelector.getKeyInfo.rawValue

        var output = SMCParamStruct()
        var result = callSMC(&input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.keyNotFound(key)
        }

        // Now read the actual value using the size from keyInfo
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCSelector.readKey.rawValue

        output = SMCParamStruct()
        result = callSMC(&input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed(result)
        }
        if output.result == 132 {
            throw SMCError.keyNotFound(key)
        }
        return output
    }

    // MARK: - Fan Reads (fpe2 format)

    func readFanCount() throws -> Int {
        let output = try readKey(SMCKey.fanCount)
        return Int(output.bytes.0)
    }

    func readFanSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanActualSpeed(index))
        return decodeFPE2(output.bytes.0, output.bytes.1)
    }

    func readFanMinSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanMinSpeed(index))
        return decodeFPE2(output.bytes.0, output.bytes.1)
    }

    func readFanMaxSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanMaxSpeed(index))
        return decodeFPE2(output.bytes.0, output.bytes.1)
    }

    func readFanTargetSpeed(index: Int) throws -> Double {
        let output = try readKey(SMCKey.fanTargetSpeed(index))
        return decodeFPE2(output.bytes.0, output.bytes.1)
    }

    func readFanMode(index: Int) throws -> Bool {
        let output = try readKey(SMCKey.fanMode(index))
        return output.bytes.0 != 0
    }

    // MARK: - Temperature Reads (sp78 format)

    func readTemperature(key: String) throws -> Double {
        let output = try readKey(key)
        return decodeSP78(output.bytes.0, output.bytes.1)
    }

    // MARK: - Write Operations (requires root)

    func writeKey(_ key: String, bytes: [UInt8]) throws {
        // Get key info for type and size
        var input = SMCParamStruct()
        input.key = fourCharCode(key)
        input.data8 = SMCSelector.getKeyInfo.rawValue

        var infoOutput = SMCParamStruct()
        var result = callSMC(&input, output: &infoOutput)
        guard result == kIOReturnSuccess else {
            throw SMCError.keyNotFound(key)
        }

        // Write the value
        input = SMCParamStruct()
        input.key = fourCharCode(key)
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

    func writeFanSpeed(index: Int, rpm: Double) throws {
        let encoded = encodeFPE2(rpm)
        try writeKey(SMCKey.fanTargetSpeed(index), bytes: [encoded.0, encoded.1])
    }

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

    // MARK: - Internal

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
