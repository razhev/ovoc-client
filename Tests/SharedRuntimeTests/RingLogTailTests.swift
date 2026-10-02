import Foundation
import XCTest
@testable import SharedRuntime

final class RingLogTailTests: XCTestCase {
    func testRotationKeepsCompleteRecentLinesWithCyrillicAndEmoji() {
        let latest = "2026-10-02 Подключено → 🟢\n"
        let data = Data((String(repeating: "Предыдущая строка → 🔥\n", count: 10) + latest).utf8)
        let result = RingLogTail.keepingLastLines(in: data, maxBytes: latest.utf8.count + 4)
        XCTAssertEqual(String(data: result, encoding: .utf8), latest)
    }

    func testEveryCutAcrossMultibyteCharactersRemainsReadableAndBounded() {
        let data = Data((String(repeating: "Я→🔥", count: 40) + "\n").utf8)
        for limit in 0..<data.count {
            let result = RingLogTail.keepingLastLines(in: data, maxBytes: limit)
            XCTAssertLessThanOrEqual(result.count, limit)
            XCTAssertNotNil(String(data: result, encoding: .utf8), "limit=\(limit)")
        }
    }

    func testExactLineBoundaryDoesNotDiscardWholeLine() {
        let data = Data("old\nновая\n".utf8)
        let result = RingLogTail.keepingLastLines(in: data, maxBytes: "новая\n".utf8.count)
        XCTAssertEqual(String(data: result, encoding: .utf8), "новая\n")
    }

    func testLoggerRemainsReadableAfterRepeatedRotations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.log")
        let logger = RingLogger(fileURL: url, maxBytes: 256, category: "rotation-test")
        for _ in 0..<12 { logger.log(String(repeating: "Я→🔥", count: 30)) }
        logger.log("rotation-finished")
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 10_000_000)
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8), text.contains("rotation-finished"), data.count <= 256 {
                return
            }
        }
        XCTFail("Logger did not produce a bounded, readable UTF-8 log after rotation")
    }
}
