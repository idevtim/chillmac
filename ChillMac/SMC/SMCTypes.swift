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

/// Decode float32 from 4 little-endian bytes (Apple Silicon SMC byte order)
func decodeFloat32(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Double {
    let bits = UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
    return Double(Float(bitPattern: bits))
}

/// Encode Double → float32 as 4 little-endian bytes (Apple Silicon SMC byte order)
func encodeFloat32(_ value: Double) -> [UInt8] {
    let bits = Float(value).bitPattern
    return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
}

// Known SMC data type FourCharCodes
let smcTypeFPE2 = fourCharCode("fpe2")
let smcTypeSP78 = fourCharCode("sp78")
let smcTypeFLT  = fourCharCode("flt ")
let smcTypeUI8  = fourCharCode("ui8 ")
let smcTypeUI16 = fourCharCode("ui16")
let smcTypeUI32 = fourCharCode("ui32")
let smcTypeFlag = fourCharCode("flag")

/// Decode a numeric value from SMC output based on its reported data type
func decodeNumericValue(_ output: SMCParamStruct, dataType: UInt32) -> Double {
    let b = output.bytes
    switch dataType {
    case smcTypeFPE2:
        return decodeFPE2(b.0, b.1)
    case smcTypeSP78:
        return decodeSP78(b.0, b.1)
    case smcTypeFLT:
        return decodeFloat32(b.0, b.1, b.2, b.3)
    case smcTypeUI8, smcTypeFlag:
        return Double(b.0)
    case smcTypeUI16:
        return Double((UInt16(b.0) << 8) | UInt16(b.1))
    case smcTypeUI32:
        return Double((UInt32(b.0) << 24) | (UInt32(b.1) << 16) | (UInt32(b.2) << 8) | UInt32(b.3))
    default:
        // Fallback: try fpe2 for 2-byte, float for 4-byte
        let size = output.keyInfo.dataSize
        if size == 4 {
            return decodeFloat32(b.0, b.1, b.2, b.3)
        }
        return decodeFPE2(b.0, b.1)
    }
}

/// Encode a numeric value into bytes for the given SMC data type
func encodeNumericValue(_ value: Double, dataType: UInt32) -> [UInt8] {
    switch dataType {
    case smcTypeFPE2:
        let e = encodeFPE2(value)
        return [e.0, e.1]
    case smcTypeFLT:
        return encodeFloat32(value)
    case smcTypeUI8, smcTypeFlag:
        return [UInt8(min(max(value, 0), 255))]
    case smcTypeUI16:
        let v = UInt16(min(max(value, 0), Double(UInt16.max)))
        return [UInt8(v >> 8), UInt8(v & 0xFF)]
    default:
        // Fallback: try float for 4-byte types
        return encodeFloat32(value)
    }
}
