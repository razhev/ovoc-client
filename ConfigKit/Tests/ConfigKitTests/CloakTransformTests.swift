import XCTest
@testable import ConfigKit

final class CloakTransformTests: XCTestCase {

    private func transform(
        last: [String: Any],
        siblings: [String: Any] = [:],
        hostName: String = "203.0.113.10"
    ) throws -> [String: Any] {
        var sectionFields: [String: Any] = ["last_config": SyntheticKey.jsonString(last)]
        for (key, value) in siblings { sectionFields[key] = value }
        let data = try JSONSerialization.data(withJSONObject: sectionFields)
        let section = try JSONDecoder().decode(ProtocolSection.self, from: data)
        let json = try CloakTransform.makeCloakJSON(fields: section.effectiveFields(), hostName: hostName)
        return try JSONSerialization.jsonObject(with: json) as! [String: Any]
    }

    // Кейс 9: NumConn всегда принудительно 1 (число).
    func testCloakNumConnForcedTo1() throws {
        let result = try transform(last: SyntheticKey.cloakLastConfig(numConn: 4))
        XCTAssertEqual(result["NumConn"] as? Int, 1)
    }

    // Кейс 10: "StreamTimeout":"300" (строкой) → 300 (числом) — иначе Go json.Unmarshal падает.
    func testCloakStreamTimeoutStringToNumber() throws {
        let result = try transform(last: SyntheticKey.cloakLastConfig(streamTimeout: "300"))
        XCTAssertEqual(result["StreamTimeout"] as? Int, 300)
        // и убеждаемся, что это именно число, а не строка
        XCTAssertNil(result["StreamTimeout"] as? String)
    }

    // Кейс 11: UID/PublicKey — base64-строки, остаются как есть, без перекодирования.
    func testCloakUIDStaysString() throws {
        let result = try transform(last: SyntheticKey.cloakLastConfig())
        XCTAssertEqual(result["UID"] as? String, "dGVzdC11aWQ=")
        XCTAssertEqual(result["PublicKey"] as? String, "cHVibGljK2tleQ==")
    }

    // Кейс 12: remote→RemoteHost, port→RemotePort; служебные ключи удалены.
    // Соседний port секции cloak перекрывает RemotePort из last_config (как у Amnezia).
    func testCloakRemoteHostPortMapping() throws {
        let result = try transform(
            last: SyntheticKey.cloakLastConfig(extra: ["remote": "198.51.100.20"]),
            siblings: ["port": "443", "transport_proto": "tcp"]
        )
        XCTAssertEqual(result["RemoteHost"] as? String, "198.51.100.20")
        XCTAssertEqual(result["RemotePort"] as? String, "443")
        XCTAssertNil(result["remote"])
        XCTAssertNil(result["port"])
        XCTAssertNil(result["transport_proto"])
    }

    // Кейс 13: нет ни remote, ни RemoteHost → подставляется hostName сервера.
    func testCloakRemoteHostFallsBackToHostName() throws {
        let result = try transform(
            last: SyntheticKey.cloakLastConfig(removeKeys: ["RemoteHost"]),
            hostName: "vpn.example.org"
        )
        XCTAssertEqual(result["RemoteHost"] as? String, "vpn.example.org")
    }

    // Порт числом в last_config тоже нормализуется в строку RemotePort.
    func testCloakNumericPortBecomesString() throws {
        let result = try transform(
            last: SyntheticKey.cloakLastConfig(),
            siblings: ["port": 8444]
        )
        XCTAssertEqual(result["RemotePort"] as? String, "8444")
    }
}
