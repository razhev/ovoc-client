import XCTest
@testable import ConfigKit

final class ZlibTests: XCTestCase {

    // Кейс 19: qCompress → qUncompress — идентичность (валидирует сам синтезатор ключей).
    func testQCompressRoundTrip() throws {
        let samples: [Data] = [
            Data("hello".utf8),
            Data(String(repeating: "config ", count: 5000).utf8),
            Data((0..<255).map { UInt8($0) }),
        ]
        for sample in samples {
            let packed = try qCompress(sample, level: 8)
            XCTAssertEqual(try qUncompress(packed), sample)
        }
    }

    func testQUncompressRejectsTruncatedInput() {
        XCTAssertThrowsError(try qUncompress(Data([0x00, 0x00]))) { error in
            XCTAssertEqual(error as? ZlibError, .truncatedInput)
        }
    }

    func testQUncompressRejectsGarbage() {
        // Правдоподобный заголовок длины + мусор вместо zlib-потока.
        var garbage = Data([0x00, 0x00, 0x00, 0x10])
        garbage.append(Data([0xde, 0xad, 0xbe, 0xef, 0x01, 0x02, 0x03]))
        XCTAssertThrowsError(try qUncompress(garbage)) { error in
            guard case .inflateFailed = error as? ZlibError else {
                return XCTFail("ожидали inflateFailed, получили \(error)")
            }
        }
    }
}
