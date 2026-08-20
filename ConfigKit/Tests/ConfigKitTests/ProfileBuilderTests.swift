import XCTest
@testable import ConfigKit

final class ProfileBuilderTests: XCTestCase {

    private let cloakJSON = Data(#"{"NumConn":1}"#.utf8)

    // Кейс 4: плейсхолдеры $PRIMARY_DNS/$SECONDARY_DNS подставляются.
    func testDNSPlaceholdersSubstituted() {
        let profile = OVPNProfileBuilder.build(
            ovpnText: SyntheticKey.sampleOVPN,
            serverIP: "203.0.113.10",
            dns1: "10.11.12.13",
            dns2: "10.11.12.14",
            cloakJSON: cloakJSON
        )
        XCTAssertTrue(profile.contains("dhcp-option DNS 10.11.12.13"))
        XCTAssertTrue(profile.contains("dhcp-option DNS 10.11.12.14"))
        XCTAssertFalse(profile.contains("$PRIMARY_DNS"))
        XCTAssertFalse(profile.contains("$SECONDARY_DNS"))
    }

    // Кейс 5: профиль без плейсхолдеров не трогаем (кроме route и <cloak>).
    func testNoPlaceholdersProfileUntouched() {
        let source = SyntheticKey.sampleOVPNNoPlaceholdersNoRoute
        let profile = OVPNProfileBuilder.build(
            ovpnText: source,
            serverIP: "203.0.113.10",
            dns1: "10.11.12.13",
            dns2: "10.11.12.14",
            cloakJSON: cloakJSON
        )
        // Существующая DNS-директива осталась как была.
        XCTAssertTrue(profile.contains("dhcp-option DNS 9.9.9.9"))
        XCTAssertFalse(profile.contains("10.11.12.13"))
        // Все исходные строки на месте.
        for line in source.split(separator: "\n") {
            XCTAssertTrue(profile.contains(line), "потеряна строка: \(line)")
        }
    }

    // Кейс 7: строки route нет → вставлена (и до инлайн-блоков, где директивы не действуют).
    func testRouteInsertedWhenMissing() {
        let profile = OVPNProfileBuilder.build(
            ovpnText: SyntheticKey.sampleOVPNNoPlaceholdersNoRoute,
            serverIP: "198.51.100.7",
            dns1: "1.1.1.1",
            dns2: "1.0.0.1",
            cloakJSON: cloakJSON
        )
        let routeLine = "route 198.51.100.7 255.255.255.255 net_gateway"
        XCTAssertTrue(profile.contains(routeLine))
        let routeIndex = profile.range(of: routeLine)!.lowerBound
        let caIndex = profile.range(of: "<ca>")!.lowerBound
        XCTAssertLessThan(routeIndex, caIndex, "route должен стоять до инлайн-блоков")
    }

    // Кейс 8: строка route уже есть → не дублируется.
    func testRoutePreservedWhenPresent() {
        let profile = OVPNProfileBuilder.build(
            ovpnText: SyntheticKey.sampleOVPN,
            serverIP: "203.0.113.10",
            dns1: "1.1.1.1",
            dns2: "1.0.0.1",
            cloakJSON: cloakJSON
        )
        let occurrences = profile.components(separatedBy: "route 203.0.113.10 255.255.255.255 net_gateway").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    // Кейс 14: блок <cloak> дописан в конец и его base64 декодируется в исходный JSON.
    func testCloakBlockAppendedAndDecodable() throws {
        let profile = OVPNProfileBuilder.build(
            ovpnText: SyntheticKey.sampleOVPN,
            serverIP: "203.0.113.10",
            dns1: "1.1.1.1",
            dns2: "1.0.0.1",
            cloakJSON: cloakJSON
        )
        XCTAssertTrue(profile.hasSuffix("</cloak>\n"))
        let dict = try SyntheticKey.cloakDict(fromProfile: profile)
        XCTAssertEqual(dict["NumConn"] as? Int, 1)
    }
}
