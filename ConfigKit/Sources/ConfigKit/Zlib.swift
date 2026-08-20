import Czlib
import Foundation

enum ZlibError: Error, Equatable {
    case truncatedInput
    case inflateFailed(code: Int32)
    case deflateFailed(code: Int32)
    case lengthMismatch(expected: Int, actual: Int)
}

/// Аналог Qt `qUncompress`: вход = 4 байта big-endian (длина несжатых данных)
/// + zlib-поток RFC1950 (с заголовком). Именно так Amnezia пакует JSON в ключе
/// vpn:// (см. exportController.cpp: `qCompress(json, 8)`).
func qUncompress(_ data: Data) throws -> Data {
    guard data.count > 4 else { throw ZlibError.truncatedInput }

    let header = [UInt8](data.prefix(4))
    let expected = (Int(header[0]) << 24) | (Int(header[1]) << 16)
                 | (Int(header[2]) << 8) | Int(header[3])
    if expected == 0 { return Data() }

    let payload = data.dropFirst(4)
    var output = Data(count: expected)
    var destLen = uLongf(expected)

    let status: Int32 = payload.withUnsafeBytes { src in
        output.withUnsafeMutableBytes { dst in
            uncompress(
                dst.bindMemory(to: Bytef.self).baseAddress!, &destLen,
                src.bindMemory(to: Bytef.self).baseAddress!, uLong(payload.count)
            )
        }
    }

    guard status == Z_OK else { throw ZlibError.inflateFailed(code: status) }
    guard Int(destLen) == expected else {
        throw ZlibError.lengthMismatch(expected: expected, actual: Int(destLen))
    }
    return output
}

/// Аналог Qt `qCompress` — нужен тестам, чтобы синтезировать ключи vpn://
/// (реальный ключ в тесты не попадает никогда).
func qCompress(_ data: Data, level: Int32 = -1) throws -> Data {
    var destLen = uLongf(compressBound(uLong(data.count)))
    var output = Data(count: Int(destLen))

    let status: Int32 = output.withUnsafeMutableBytes { dst in
        if data.isEmpty {
            // compress2 корректно жмёт и пустой вход, но baseAddress у пустого Data — nil
            var emptyByte: Bytef = 0
            return compress2(dst.bindMemory(to: Bytef.self).baseAddress!, &destLen, &emptyByte, 0, level)
        }
        return data.withUnsafeBytes { src in
            compress2(
                dst.bindMemory(to: Bytef.self).baseAddress!, &destLen,
                src.bindMemory(to: Bytef.self).baseAddress!, uLong(data.count), level
            )
        }
    }
    guard status == Z_OK else { throw ZlibError.deflateFailed(code: status) }

    let n = UInt32(data.count)
    var result = Data(capacity: 4 + Int(destLen))
    result.append(contentsOf: [
        UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff),
        UInt8((n >> 8) & 0xff), UInt8(n & 0xff),
    ])
    result.append(output.prefix(Int(destLen)))
    return result
}
