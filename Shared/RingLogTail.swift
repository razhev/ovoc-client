import Foundation

enum RingLogTail {
    /// Последние целые строки в пределах лимита. Если одна строка длиннее
    /// лимита, сохраняем её хвост, начиная с границы UTF-8 символа.
    static func keepingLastLines(in data: Data, maxBytes: Int) -> Data {
        guard maxBytes > 0 else { return Data() }
        guard data.count > maxBytes else { return data }
        let start = data.endIndex - maxBytes
        if data[start - 1] == 0x0a { return Data(data[start...]) }
        if let newline = data[start...].firstIndex(of: 0x0a), newline + 1 < data.endIndex {
            return Data(data[(newline + 1)...])
        }
        // Внутри многобайтного символа байты имеют префикс 10xxxxxx.
        var boundary = start
        while boundary < data.endIndex, data[boundary] & 0xc0 == 0x80 { boundary += 1 }
        return Data(data[boundary...])
    }
}
