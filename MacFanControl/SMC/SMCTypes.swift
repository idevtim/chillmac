import Foundation
import IOKit

// MARK: - SMC Param Struct (must match kernel layout exactly)

struct SMCParamStruct {
    struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

// MARK: - SMC Selectors

enum SMCSelector: UInt8 {
    case readKey = 5
    case writeKey = 6
    case getKeyFromIndex = 8
    case getKeyInfo = 9
}

// MARK: - Errors

enum SMCError: Error, LocalizedError {
    case driverNotFound
    case failedToOpen
    case keyNotFound(String)
    case readFailed(kern_return_t)
    case writeFailed(kern_return_t)
    case unknownDataType(String)

    var errorDescription: String? {
        switch self {
        case .driverNotFound: return "AppleSMC driver not found"
        case .failedToOpen: return "Failed to open SMC connection"
        case .keyNotFound(let key): return "SMC key not found: \(key)"
        case .readFailed(let code): return "SMC read failed with code: \(code)"
        case .writeFailed(let code): return "SMC write failed with code: \(code)"
        case .unknownDataType(let type): return "Unknown SMC data type: \(type)"
        }
    }
}

// MARK: - Encoding Helpers

func fourCharCode(_ s: String) -> UInt32 {
    var result: UInt32 = 0
    for char in s.utf8.prefix(4) {
        result = (result << 8) | UInt32(char)
    }
    return result
}

func fourCharCodeToString(_ code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

/// Decode fpe2 (unsigned 14.2 fixed-point) → Double RPM
func decodeFPE2(_ byte0: UInt8, _ byte1: UInt8) -> Double {
    let raw = (UInt16(byte0) << 8) | UInt16(byte1)
    return Double(raw) / 4.0
}

/// Encode Double RPM → fpe2 (unsigned 14.2 fixed-point) as (byte0, byte1)
func encodeFPE2(_ value: Double) -> (UInt8, UInt8) {
    let raw = UInt16(min(max(value * 4.0, 0), Double(UInt16.max)))
    return (UInt8(raw >> 8), UInt8(raw & 0xFF))
}

/// Decode sp78 (signed 8.8 fixed-point) → Double Celsius
func decodeSP78(_ byte0: UInt8, _ byte1: UInt8) -> Double {
    let raw = Int16(bitPattern: (UInt16(byte0) << 8) | UInt16(byte1))
    return Double(raw) / 256.0
}
