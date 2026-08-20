import XCTest
@testable import ConfigKit

final class DecoderTests: XCTestCase {

    // Кейс 1: полный путь vpn:// → base64url без паддинга → qUncompress → модель.
    func testDecodeQCompressedKey() throws {
        let key = try SyntheticKey.key(from: SyntheticKey.serverJSON())
        let config = try VPNKeyDecoder.decode(key)

        XCTAssertEqual(config.hostName, "203.0.113.10")
        XCTAssertEqual(config.description, "Test Server")
        XCTAssertEqual(config.dns1, "10.11.12.13")
        XCTAssertEqual(config.defaultContainer, "amnezia-openvpn-cloak")
        XCTAssertEqual(config.containers.count, 1)
        XCTAssertEqual(config.containers[0].container, "amnezia-openvpn-cloak")
        XCTAssertNotNil(config.containers[0].openvpn)
        XCTAssertNotNil(config.containers[0].cloak)
    }

    // Кейс 2: запасной путь — ключ без сжатия (plain base64 JSON).
    func testDecodePlainBase64Fallback() throws {
        let key = try SyntheticKey.key(from: SyntheticKey.serverJSON(), compressed: false)
        let config = try VPNKeyDecoder.decode(key)
        XCTAssertEqual(config.hostName, "203.0.113.10")
    }

    // Кейс 3: восстановление паддинга base64url — все три остатка длины (0, 2, 3).
    // Несжатый JSON позволяет управлять длиной байт с точностью до единицы.
    func testBase64URLPaddingVariants() throws {
        var seenRemainders: Set<Int> = []
        for pad in 0..<3 {
            let json = SyntheticKey.serverJSON(description: "srv" + String(repeating: "x", count: pad))
            let key = try SyntheticKey.key(from: json, compressed: false)
            let encodedLength = key.count - "vpn://".count
            seenRemainders.insert(encodedLength % 4)
            XCTAssertEqual(try VPNKeyDecoder.decode(key).hostName, "203.0.113.10")
        }
        XCTAssertEqual(seenRemainders, [0, 2, 3], "три длины JSON должны покрыть все валидные остатки")
    }

    // Кейс 18: выбор контейнера amnezia-openvpn-cloak среди прочих,
    // и с defaultContainer, и без него.
    func testContainerSelection() throws {
        let wireguard: [String: Any] = ["container": "amnezia-wireguard", "wireguard": ["last_config": "{}"]]
        for defaultContainer in ["amnezia-openvpn-cloak", nil] {
            let json = SyntheticKey.serverJSON(
                defaultContainer: defaultContainer,
                containers: [wireguard, SyntheticKey.cloakContainer()]
            )
            let key = try SyntheticKey.key(from: json)
            let config = try VPNKeyDecoder.decode(key)
            XCTAssertEqual(try config.cloakContainer().container, "amnezia-openvpn-cloak")
        }
    }

    // Кейс 17: мусор на входе → типизированная ошибка, не crash.
    func testGarbageInputTypedErrors() throws {
        // не vpn://
        XCTAssertThrowsError(try VPNKeyDecoder.decode("https://example.com/x")) {
            XCTAssertEqual($0 as? VPNKeyError, .notAVPNKey)
        }
        // битый base64 (недопустимые символы / длина ≡ 1 mod 4)
        XCTAssertThrowsError(try VPNKeyDecoder.decode("vpn://%%%недопустимо%%%")) {
            XCTAssertEqual($0 as? VPNKeyError, .invalidBase64)
        }
        XCTAssertThrowsError(try VPNKeyDecoder.decode("vpn://a")) {
            XCTAssertEqual($0 as? VPNKeyError, .invalidBase64)
        }
        // валидный base64, но внутри ни zlib, ни JSON
        let noise = SyntheticKey.base64url(Data([0xde, 0xad, 0xbe, 0xef, 0x11, 0x22, 0x33, 0x44]))
        XCTAssertThrowsError(try VPNKeyDecoder.decode("vpn://" + noise)) {
            XCTAssertEqual($0 as? VPNKeyError, .decompressionFailed)
        }
        // валидный zlib, но внутри не JSON
        let notJSON = SyntheticKey.base64url(try qCompress(Data("это не JSON".utf8), level: 8))
        XCTAssertThrowsError(try VPNKeyDecoder.decode("vpn://" + notJSON)) {
            guard case .malformedJSON = $0 as? VPNKeyError else {
                return XCTFail("ожидали malformedJSON, получили \($0)")
            }
        }
        // валидный JSON, но нет контейнера Cloak
        let wireguardOnly = SyntheticKey.serverJSON(
            defaultContainer: "amnezia-wireguard",
            containers: [["container": "amnezia-wireguard", "wireguard": ["last_config": "{}"]]]
        )
        XCTAssertThrowsError(try ImportedConfig.make(fromKey: SyntheticKey.key(from: wireguardOnly))) {
            XCTAssertEqual($0 as? VPNKeyError, .noCloakContainer)
        }
        // контейнер есть, но в openvpn.last_config нет поля config
        let brokenOpenVPN: [String: Any] = [
            "container": "amnezia-openvpn-cloak",
            "openvpn": ["last_config": "{}"],
            "cloak": ["last_config": SyntheticKey.jsonString(SyntheticKey.cloakLastConfig())],
        ]
        let brokenJSON = SyntheticKey.serverJSON(containers: [brokenOpenVPN])
        XCTAssertThrowsError(try ImportedConfig.make(fromKey: SyntheticKey.key(from: brokenJSON))) {
            XCTAssertEqual($0 as? VPNKeyError, .missingField("openvpn.last_config.config"))
        }
    }
}
