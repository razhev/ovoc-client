import XCTest
@testable import ConfigKit

/// Экран импорта получает не «чистый ключ», а то, что человек скопировал:
/// сообщение целиком, строку с переносами, обрезанный кусок. У приложения нет
/// тестового таргета, поэтому вся эта логика живёт в ConfigKit и проверяется здесь.
final class PastedTextTests: XCTestCase {

    private func sampleKey(compressed: Bool = true) throws -> String {
        try SyntheticKey.key(from: SyntheticKey.serverJSON(), compressed: compressed)
    }

    /// Ключ, разорванный переносами каждые `width` символов (так делает почта).
    private func wrapped(_ key: String, width: Int = 76, separator: String = "\n") -> String {
        var lines: [String] = []
        var rest = Substring(key)
        while !rest.isEmpty {
            lines.append(String(rest.prefix(width)))
            rest = rest.dropFirst(width)
        }
        return lines.joined(separator: separator)
    }

    private func assertImports(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let imported = try ImportedConfig.make(fromPastedText: text)
            XCTAssertEqual(imported.serverIP, "203.0.113.10", file: file, line: line)
            XCTAssertEqual(imported.description, "Test Server", file: file, line: line)
        } catch {
            XCTFail("импорт не прошёл: \(error)", file: file, line: line)
        }
    }

    // MARK: - Успешные случаи

    func testCleanKey() throws {
        assertImports(try sampleKey())
    }

    func testSurroundingWhitespace() throws {
        assertImports("  \n\t" + (try sampleKey()) + " \r\n\n")
    }

    func testKeyWrappedByNewlines() throws {
        let key = try sampleKey()
        assertImports(wrapped(key))
        assertImports(wrapped(key, separator: "\r\n"))
        // перенос + отступ, как в цитате письма
        assertImports(wrapped(key, separator: "\n   "))
    }

    func testKeyInsideRussianMessage() throws {
        assertImports("Привет! Вот ключ для VPN: \(try sampleKey()) — вставь его в приложение. Спасибо!")
        assertImports("Ключ:\n\(wrapped(try sampleKey()))\n\nНапиши, если не заработает.")
    }

    func testKeyInQuotesAndWithTrailingPunctuation() throws {
        let key = try sampleKey()
        assertImports("«\(key)»")
        assertImports("\"\(key)\"")
        assertImports("(\(key)).")
    }

    // Латинское слово после ключа неотличимо от его продолжения — выручает перебор
    // кандидатов. Проверяем оба формата: сжатый терпит хвост сам (zlib знает свой
    // конец), несжатый JSON — нет.
    func testLatinTextAfterKey() throws {
        for compressed in [true, false] {
            let key = try sampleKey(compressed: compressed)
            assertImports("\(key) thanks")
            assertImports("key: \(key)\nthanks a lot, see you")
            assertImports("\(wrapped(key))\nBest regards\nJohn")
        }
    }

    func testUppercasePrefix() throws {
        let key = try sampleKey()
        assertImports("VPN://" + key.dropFirst("vpn://".count))
    }

    func testInvisibleCharactersRemoved() throws {
        let key = try sampleKey()
        let middle = key.index(key.startIndex, offsetBy: key.count / 2)
        // BOM в начале, zero-width space и мягкий перенос посреди ключа
        assertImports("\u{FEFF}" + key[..<middle] + "\u{200B}\u{00AD}" + key[middle...])
        // неразрывный пробел вместо обычного
        assertImports("ключ:\u{00A0}" + key)
    }

    func testFirstOfTwoKeysWins() throws {
        let first = try SyntheticKey.key(from: SyntheticKey.serverJSON(description: "Первый"))
        let second = try SyntheticKey.key(from: SyntheticKey.serverJSON(description: "Второй"))
        let imported = try ImportedConfig.make(fromPastedText: "\(first)\n\(second)")
        XCTAssertEqual(imported.description, "Первый")
    }

    // MARK: - Ошибки

    func testTextWithoutKey() {
        for text in ["", "   \n", "просто сообщение без ключа", "https://example.com/vpn", "vpn://", "vpn:// \n"] {
            XCTAssertThrowsError(try ImportedConfig.make(fromPastedText: text), "«\(text)»") {
                XCTAssertEqual($0 as? VPNKeyError, .notAVPNKey)
            }
        }
    }

    func testGarbageAfterPrefix() {
        XCTAssertThrowsError(try ImportedConfig.make(fromPastedText: "vpn://qwertyQWERTYqwertyQWERTY12")) {
            XCTAssertEqual($0 as? VPNKeyError, .decompressionFailed)
        }
    }

    // Обрезанный ключ — при любой длине обрезка, включая невозможную для base64
    // длину ≡ 1 (mod 4), — даёт «скопирован не целиком», а не общее «повреждён».
    func testTruncatedKeyAtAnyLength() throws {
        let key = try sampleKey()
        let bodyLength = key.count - "vpn://".count
        var seenRemainders: Set<Int> = []
        for cut in [bodyLength - 1, bodyLength - 2, bodyLength - 3, bodyLength - 4, bodyLength / 2, bodyLength / 3, 9] {
            seenRemainders.insert(cut % 4)
            let truncated = String(key.prefix("vpn://".count + cut))
            XCTAssertThrowsError(try ImportedConfig.make(fromPastedText: truncated), "обрезка до \(cut)") {
                XCTAssertEqual($0 as? VPNKeyError, .truncated, "обрезка до \(cut)")
            }
        }
        XCTAssertEqual(seenRemainders, [0, 1, 2, 3])
    }

    func testTruncatedUncompressedKey() throws {
        let key = try sampleKey(compressed: false)
        XCTAssertThrowsError(try ImportedConfig.make(fromPastedText: String(key.prefix(key.count / 2)))) {
            XCTAssertEqual($0 as? VPNKeyError, .truncated)
        }
    }

    // Ключ другого протокола: ошибка окончательная, укороченные кандидаты её не маскируют.
    func testOtherProtocolKeyInsideMessage() throws {
        let wireguardOnly = SyntheticKey.serverJSON(
            defaultContainer: "amnezia-awg",
            containers: [["container": "amnezia-awg", "awg": ["last_config": "{}"]]]
        )
        let key = try SyntheticKey.key(from: wireguardOnly)
        XCTAssertThrowsError(try ImportedConfig.make(fromPastedText: "Держи: \(key) ok")) {
            XCTAssertEqual($0 as? VPNKeyError, .noCloakContainer)
        }
    }

    // Мусорный заголовок длины не должен просить буфер на гигабайты.
    func testHugeDeclaredSizeRejectedCheaply() {
        var payload = Data([0x7f, 0xff, 0xff, 0xff])
        payload.append(Data([0x78, 0x9c, 0x01, 0x02, 0x03, 0x04]))
        XCTAssertThrowsError(try qUncompress(payload)) {
            XCTAssertEqual($0 as? ZlibError, .declaredSizeTooLarge(0x7fff_ffff))
        }
        XCTAssertThrowsError(try ImportedConfig.make(fromPastedText: "vpn://" + SyntheticKey.base64url(payload))) {
            XCTAssertEqual($0 as? VPNKeyError, .decompressionFailed)
        }
    }

    // Все тексты ошибок — непустые русские строки: экран показывает их как есть.
    func testEveryErrorHasRussianDescription() {
        let errors: [VPNKeyError] = [
            .notAVPNKey, .invalidBase64, .truncated, .decompressionFailed,
            .malformedJSON("x"), .noCloakContainer, .missingField("x"), .notAnIPv4("x"),
        ]
        for error in errors {
            let text = error.errorDescription ?? ""
            XCTAssertTrue(text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "\(error)")
        }
    }

    // MARK: - Кандидаты

    func testCandidatesOrderAndLimit() {
        XCTAssertEqual(VPNKeyText.candidates(in: "vpn://AAA BBB CCC"),
                       ["vpn://AAABBBCCC", "vpn://AAABBB", "vpn://AAA"])
        XCTAssertEqual(VPNKeyText.candidates(in: "x vpn://AAA.BBB"), ["vpn://AAA"])
        XCTAssertEqual(VPNKeyText.candidates(in: "нет ключа"), [])
        // Перебор ограничен: гигантский текст не превращается в квадратичный разбор.
        let many = "vpn://" + Array(repeating: "AAAA", count: 500).joined(separator: " ")
        XCTAssertEqual(VPNKeyText.candidates(in: many).count, 17)
    }
}
