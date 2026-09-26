import Czlib
import Foundation

enum ZlibError: Error, Equatable {
    case truncatedInput
    /// Поток zlib корректен, но оборвался раньше своего конца — ключ скопирован не целиком.
    case truncatedStream
    /// Заявленная длина несжатых данных неправдоподобна (мусор вместо ключа).
    case declaredSizeTooLarge(Int)
    case inflateFailed(code: Int32)
    case deflateFailed(code: Int32)
    case lengthMismatch(expected: Int, actual: Int)

    /// Признак «данные обрезаны», а не испорчены.
    var isTruncation: Bool { self == .truncatedInput || self == .truncatedStream }
}

/// Реальный ключ распаковывается в 10–20 КБ. Предел защищает от мусорного
/// заголовка длины: без него вставка случайной строки просила бы буфер на гигабайты.
let qUncompressSizeLimit = 8 * 1024 * 1024

/// Аналог Qt `qUncompress`: вход = 4 байта big-endian (длина несжатых данных)
/// + zlib-поток RFC1950 (с заголовком). Именно так Amnezia пакует JSON в ключе
/// vpn:// (см. exportController.cpp: `qCompress(json, 8)`).
///
/// Потоковый `inflate`, а не `uncompress`: только он отличает оборванный поток
/// (вход кончился раньше Z_STREAM_END) от испорченного — экрану импорта нужна
/// именно эта разница («скопирован не целиком» против «повреждён»).
func qUncompress(_ data: Data) throws -> Data {
    guard data.count > 4 else { throw ZlibError.truncatedInput }

    let header = [UInt8](data.prefix(4))
    let expected = (Int(header[0]) << 24) | (Int(header[1]) << 16)
                 | (Int(header[2]) << 8) | Int(header[3])
    if expected == 0 { return Data() }
    guard expected <= qUncompressSizeLimit else { throw ZlibError.declaredSizeTooLarge(expected) }

    let payload = data.dropFirst(4)
    var output = Data(count: expected)

    var stream = z_stream()
    let initStatus = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard initStatus == Z_OK else { throw ZlibError.inflateFailed(code: initStatus) }
    defer { inflateEnd(&stream) }

    let status: Int32 = payload.withUnsafeBytes { src in
        output.withUnsafeMutableBytes { dst in
            stream.next_in = UnsafeMutablePointer(mutating: src.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(payload.count)
            stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress!
            stream.avail_out = uInt(expected)
            return inflate(&stream, Z_FINISH)
        }
    }

    switch status {
    case Z_STREAM_END:
        break
    case Z_OK, Z_BUF_ERROR:
        // Конца потока нет. Вход исчерпан — данные обрезаны; иначе кончился
        // выходной буфер — данных больше, чем заявлено в заголовке.
        if stream.avail_in == 0 { throw ZlibError.truncatedStream }
        throw ZlibError.lengthMismatch(expected: expected, actual: Int(stream.total_out))
    default:
        throw ZlibError.inflateFailed(code: status)
    }
    guard Int(stream.total_out) == expected else {
        throw ZlibError.lengthMismatch(expected: expected, actual: Int(stream.total_out))
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
