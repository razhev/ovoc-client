import NetworkExtension
import XCTest
import SharedRuntime
@testable import TunnelRuntime

final class ServiceBypassRouteTests: XCTestCase {
    func testPreparingSettingsCannotTurnAdapterBaselineIntoSyntheticIPv6OnReconnect() throws {
        let original = baseline()
        original.ipv6Settings = nil
        original.dnsSettings?.matchDomains = ["example.test"]
        let prepared = try ServiceBypassRoutes.copyOf(original)
        prepared.ipv6Settings = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])
        prepared.dnsSettings?.matchDomains = [""]
        XCTAssertNil(original.ipv6Settings)
        XCTAssertEqual(original.dnsSettings?.matchDomains, ["example.test"])
    }

    private func baseline() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let v4 = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        v4.includedRoutes = [.default()]
        v4.excludedRoutes = [NEIPv4Route(destinationAddress: "203.0.113.1", subnetMask: "255.255.255.255")]
        settings.ipv4Settings = v4
        let v6 = NEIPv6Settings(addresses: ["fd00:6f76:6f63::2"], networkPrefixLengths: [64])
        v6.includedRoutes = [.default()]
        settings.ipv6Settings = v6
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1"])
        settings.dnsSettings?.matchDomains = [""]
        settings.mtu = 1400
        return settings
    }

    func testPreservesOriginalRoutesDNSMTUAndIPv6SinkWithoutMutatingBaseline() throws {
        let original = baseline()
        let networks = try ["185.73.193.0/24", "2a02:6b8::/62"].map(IPNetwork.init)
        let result = try ServiceBypassRoutes.applying(networks, to: original)
        XCTAssertEqual(result.ipv4Settings?.excludedRoutes?.count, 2)
        XCTAssertEqual(result.ipv4Settings?.excludedRoutes?.first?.destinationAddress, "203.0.113.1")
        XCTAssertEqual(result.ipv6Settings?.excludedRoutes?.count, 1)
        XCTAssertEqual(result.ipv6Settings?.includedRoutes?.first?.destinationAddress, "::")
        XCTAssertEqual(result.ipv6Settings?.addresses, ["fd00:6f76:6f63::2"])
        XCTAssertEqual(result.dnsSettings?.servers, ["1.1.1.1"])
        XCTAssertEqual(result.dnsSettings?.matchDomains, [""])
        XCTAssertEqual(result.mtu, 1400)
        XCTAssertEqual(original.ipv4Settings?.excludedRoutes?.count, 1)
        XCTAssertTrue(original.ipv6Settings?.excludedRoutes?.isEmpty ?? true)
        XCTAssertEqual(try ServiceBypassRoutes.applying(networks, to: result).ipv4Settings?.excludedRoutes?.count, 2)
        // A new session always starts from adapter baseline; turning all off
        // retains the original exclusion but none of our additions.
        XCTAssertEqual(try ServiceBypassRoutes.applying([], to: original).ipv4Settings?.excludedRoutes?.count, 1)
    }

    func testRejectsDNSConflictIncludingPublicYandexDNSAndIPv6() throws {
        for (dns, cidr) in [("77.88.8.8", "77.88.0.0/18"), ("2a02:6b8::feed", "2a02:6b8::/62")] {
            let settings = baseline()
            settings.dnsSettings = NEDNSSettings(servers: [dns])
            XCTAssertThrowsError(try ServiceBypassRoutes.applying([IPNetwork(cidr)], to: settings)) {
                XCTAssertEqual($0 as? ServiceBypassError, .dnsConflict)
            }
            XCTAssertEqual(settings.ipv4Settings?.excludedRoutes?.count, 1)
        }
    }

    func testPreservesServerIPv6AndRejectsCollisionWithItsAddress() throws {
        let settings = baseline()
        let v6 = NEIPv6Settings(addresses: ["2606:4700::1234"], networkPrefixLengths: [64])
        v6.includedRoutes = [.default()]
        v6.excludedRoutes = [NEIPv6Route(destinationAddress: "2001:db8::1", networkPrefixLength: 128)]
        settings.ipv6Settings = v6
        let result = try ServiceBypassRoutes.applying([IPNetwork("2a02:6b8::/62")], to: settings)
        XCTAssertEqual(result.ipv6Settings?.addresses, ["2606:4700::1234"])
        XCTAssertEqual(result.ipv6Settings?.excludedRoutes?.count, 2)
        XCTAssertThrowsError(try ServiceBypassRoutes.applying([IPNetwork("2606:4700::/32")], to: settings)) {
            XCTAssertEqual($0 as? ServiceBypassError, .tunnelAddressConflict)
        }
    }

    func testReconnectNilRetainsExceptionsAndFreshDNSIsRechecked() throws {
        let rules = try [IPNetwork("185.73.193.0/24")]
        var installed = try ServiceBypassRoutes.applying(rules, to: baseline())
        let first = installed
        TunnelNetworkSettingsUpdate.apply(nil, using: { _, _ in XCTFail("nil must not clear settings") }) {
            XCTAssertNil($0)
        }
        XCTAssertTrue(installed === first)
        let replacement = baseline()
        replacement.dnsSettings = NEDNSSettings(servers: ["185.73.193.1"])
        TunnelNetworkSettingsUpdate.apply(replacement, using: { settings, completion in
            do { installed = try ServiceBypassRoutes.applying(rules, to: settings); completion(nil) }
            catch { completion(error) }
        }) { XCTAssertEqual($0 as? ServiceBypassError, .dnsConflict) }
        XCTAssertTrue(installed === first)
    }

    func testRejectsMissingFamilySettingsAndInvalidNetworkAtRuntimeBoundary() throws {
        let settings = baseline()
        settings.ipv6Settings = nil
        XCTAssertThrowsError(try ServiceBypassRoutes.applying([IPNetwork("2a02:6b8::/62")], to: settings))
        XCTAssertThrowsError(try ServiceBypassRoutes.applying([IPNetwork("0.0.0.0/0")], to: settings))
    }
}
