import XCTest
@testable import ConfigKit

/// Сквозные тесты конвейера ImportedConfig.make: ключ vpn:// → готовый конфиг.
final class ImportPipelineTests: XCTestCase {

    // Кейс 15: двойной разбор last_config — текст .ovpn с инлайн <ca> извлечён дословно.
    func testNestedLastConfigDoubleParse() throws {
        let key = try SyntheticKey.key(from: SyntheticKey.serverJSON())
        let config = try VPNKeyDecoder.decode(key)
        let ovpnText = try config.cloakContainer().openvpn!.ovpnConfigText()
        XCTAssertEqual(ovpnText, SyntheticKey.sampleOVPN)
        XCTAssertTrue(ovpnText.contains("-----BEGIN CERTIFICATE-----"))
    }

    // Сквозной happy path: всё вместе.
    func testEndToEndImport() throws {
        let key = try SyntheticKey.key(from: SyntheticKey.serverJSON())
        let imported = try ImportedConfig.make(fromKey: key) { _ in
            XCTFail("hostName — IPv4-литерал, резолвер вызываться не должен")
            return ""
        }

        XCTAssertEqual(imported.serverIP, "203.0.113.10")
        XCTAssertEqual(imported.dns1, "10.11.12.13")
        XCTAssertEqual(imported.description, "Test Server")
        XCTAssertTrue(imported.ovpnProfile.contains("dhcp-option DNS 10.11.12.13"))
        XCTAssertTrue(imported.ovpnProfile.contains("route 203.0.113.10 255.255.255.255 net_gateway"))

        let cloak = try SyntheticKey.cloakDict(fromProfile: imported.ovpnProfile)
        XCTAssertEqual(cloak["NumConn"] as? Int, 1)
        XCTAssertEqual(cloak["StreamTimeout"] as? Int, 300)
        XCTAssertEqual(cloak["RemotePort"] as? String, "443", "соседний port секции должен перекрыть last_config")
        XCTAssertEqual(cloak["RemoteHost"] as? String, "203.0.113.10")
        XCTAssertNil(cloak["transport_proto"])
    }

    // Кейс 6: dns1/dns2 в ключе нет → значения по умолчанию 1.1.1.1 / 1.0.0.1.
    func testDNSDefaultsWhenAbsent() throws {
        let json = SyntheticKey.serverJSON(dns1: nil, dns2: nil)
        let imported = try ImportedConfig.make(fromKey: SyntheticKey.key(from: json))
        XCTAssertEqual(imported.dns1, "1.1.1.1")
        XCTAssertEqual(imported.dns2, "1.0.0.1")
        XCTAssertTrue(imported.ovpnProfile.contains("dhcp-option DNS 1.1.1.1"))
    }

    // Кейс 16: hostName — домен → serverIP берётся из резолвера и попадает в route,
    // и RemoteHost фиксируется тем же IP: повторного DNS в Go нет.
    func testHostNameDomainResolved() throws {
        let json = SyntheticKey.serverJSON(
            hostName: "vpn.example.org",
            ovpnText: SyntheticKey.sampleOVPNNoPlaceholdersNoRoute,
            cloakLast: SyntheticKey.cloakLastConfig(removeKeys: ["RemoteHost"])
        )
        var resolvedHosts: [String] = []
        let imported = try ImportedConfig.make(fromKey: SyntheticKey.key(from: json)) { host in
            resolvedHosts.append(host)
            return "198.51.100.7"
        }

        XCTAssertEqual(resolvedHosts, ["vpn.example.org"])
        XCTAssertEqual(imported.serverIP, "198.51.100.7")
        XCTAssertTrue(imported.ovpnProfile.contains("route 198.51.100.7 255.255.255.255 net_gateway"))

        let cloak = try SyntheticKey.cloakDict(fromProfile: imported.ovpnProfile)
        XCTAssertEqual(cloak["RemoteHost"] as? String, "198.51.100.7")
    }

    // Резолвер вернул не-IPv4 → типизированная ошибка.
    func testResolverReturningGarbageFails() throws {
        let json = SyntheticKey.serverJSON(
            hostName: "vpn.example.org",
            cloakLast: SyntheticKey.cloakLastConfig(removeKeys: ["RemoteHost"])
        )
        XCTAssertThrowsError(try ImportedConfig.make(fromKey: SyntheticKey.key(from: json)) { _ in "не-адрес" }) {
            XCTAssertEqual($0 as? VPNKeyError, .notAnIPv4("vpn.example.org"))
        }
    }

    func testRouteFollowsCloakEndpointInsteadOfManagementHost() throws {
        let json = SyntheticKey.serverJSON(
            hostName: "management.example.org",
            ovpnText: SyntheticKey.sampleOVPNNoPlaceholdersNoRoute,
            cloakLast: SyntheticKey.cloakLastConfig(extra: ["RemoteHost": "198.51.100.20"])
        )
        let imported = try ImportedConfig.make(fromKey: SyntheticKey.key(from: json)) { _ in
            XCTFail("Management host must not be resolved when Cloak has an IP endpoint")
            return "203.0.113.10"
        }
        XCTAssertEqual(imported.serverIP, "198.51.100.20")
        XCTAssertTrue(imported.ovpnProfile.contains("route 198.51.100.20 255.255.255.255 net_gateway"))
        let cloak = try SyntheticKey.cloakDict(fromProfile: imported.ovpnProfile)
        XCTAssertEqual(cloak["RemoteHost"] as? String, imported.serverIP)
    }

    func testRemoteOverrideIsResolvedOnceAndPinnedInCloak() throws {
        let json = SyntheticKey.serverJSON(
            cloakSiblings: ["remote": "edge.example.org", "port": "443"]
        )
        var resolved: [String] = []
        let imported = try ImportedConfig.make(fromKey: SyntheticKey.key(from: json)) { host in
            resolved.append(host)
            return "198.51.100.30"
        }
        XCTAssertEqual(resolved, ["edge.example.org"])
        XCTAssertEqual(imported.serverIP, "198.51.100.30")
        let cloak = try SyntheticKey.cloakDict(fromProfile: imported.ovpnProfile)
        XCTAssertEqual(cloak["RemoteHost"] as? String, imported.serverIP)
        XCTAssertEqual(cloak["ServerName"] as? String, "example-mask.com", "SNI must remain unchanged")
        XCTAssertNil(cloak["remote"])
    }
}
