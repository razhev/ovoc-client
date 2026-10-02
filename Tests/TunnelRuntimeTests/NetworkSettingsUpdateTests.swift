import NetworkExtension
import XCTest
@testable import TunnelRuntime

final class NetworkSettingsUpdateTests: XCTestCase {
    func testReconnectRetainsRoutesDNSAndServerExclusionUntilReplacement() {
        let first = settings(address: "10.8.0.2", dns: "1.1.1.1")
        let replacement = settings(address: "10.9.0.2", dns: "9.9.9.9")
        var installed: NEPacketTunnelNetworkSettings?
        var applications = 0
        var completions = 0
        let configure: (NEPacketTunnelNetworkSettings, @escaping (Error?) -> Void) -> Void = { settings, completion in
            applications += 1
            installed = settings
            completion(nil)
        }
        func update(_ settings: NEPacketTunnelNetworkSettings?) {
            TunnelNetworkSettingsUpdate.apply(settings, using: configure) { error in
                XCTAssertNil(error)
                completions += 1
            }
        }

        update(nil) // initial tun_builder_new: nothing to clear
        XCTAssertNil(installed)
        update(first)
        for _ in 0..<3 {
            // teardown can arrive BEFORE RECONNECTING; failed attempts can
            // produce several resets before a successful PUSH_REPLY.
            update(nil)
            update(nil)
            XCTAssertTrue(installed === first)
            XCTAssertEqual(installed?.ipv4Settings?.includedRoutes?.first?.destinationAddress, "0.0.0.0")
            XCTAssertEqual(installed?.ipv4Settings?.excludedRoutes?.first?.destinationAddress, "203.0.113.10")
            XCTAssertEqual(installed?.ipv6Settings?.includedRoutes?.first?.destinationAddress, "::")
            XCTAssertEqual(installed?.dnsSettings?.servers, ["1.1.1.1"])
            XCTAssertEqual(installed?.dnsSettings?.matchDomains, [""])
        }
        update(replacement)
        XCTAssertTrue(installed === replacement)
        XCTAssertEqual(installed?.ipv4Settings?.addresses, ["10.9.0.2"])
        XCTAssertEqual(installed?.dnsSettings?.servers, ["9.9.9.9"])
        update(nil) // final adapter teardown: iOS owns removal on provider stop
        XCTAssertTrue(installed === replacement)
        XCTAssertEqual(applications, 2)
        XCTAssertEqual(completions, 10)
    }

    func testDoesNotAcknowledgeNewSettingsBeforeSystemCompletion() {
        var systemCompletion: ((Error?) -> Void)?
        var completions = 0
        let expected = NSError(domain: "test.network-settings", code: 1)
        TunnelNetworkSettingsUpdate.apply(settings(address: "10.8.0.2", dns: "1.1.1.1"), using: { _, completion in
            systemCompletion = completion
        }) { error in
            XCTAssertEqual(error as NSError?, expected)
            completions += 1
        }
        XCTAssertEqual(completions, 0)
        systemCompletion?(expected)
        XCTAssertEqual(completions, 1)
    }

    private func settings(address: String, dns: String) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: [address], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [.default()]
        ipv4.excludedRoutes = [NEIPv4Route(destinationAddress: "203.0.113.10", subnetMask: "255.255.255.255")]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fd00:6f76:6f63::2"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [.default()]
        settings.ipv6Settings = ipv6
        settings.dnsSettings = NEDNSSettings(servers: [dns])
        settings.dnsSettings?.matchDomains = [""]
        return settings
    }
}
