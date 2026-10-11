import NetworkExtension
#if SWIFT_PACKAGE
import SharedRuntime
#endif

/// Operates on a fresh copy of adapter settings. The adapter's baseline is never
/// mutated: reconnects and removing a selection cannot retain our old additions.
enum ServiceBypassRoutes {
    static func copyOf(_ original: NEPacketTunnelNetworkSettings) throws -> NEPacketTunnelNetworkSettings {
        guard let settings = original.copy() as? NEPacketTunnelNetworkSettings else {
            throw ServiceBypassError.missingNetworkSettings
        }
        settings.ipv4Settings = original.ipv4Settings?.copy() as? NEIPv4Settings
        settings.ipv6Settings = original.ipv6Settings?.copy() as? NEIPv6Settings
        settings.dnsSettings = original.dnsSettings?.copy() as? NEDNSSettings
        return settings
    }

    static func applying(_ networks: [IPNetwork], to original: NEPacketTunnelNetworkSettings) throws
        -> NEPacketTunnelNetworkSettings {
        let settings = try copyOf(original)
        guard !networks.isEmpty else { return settings }
        guard networks.count <= ServiceBypassCatalog.maximumRoutes else { throw ServiceBypassError.tooManyRoutes }
        guard networks.allSatisfy(\.isPublicServiceNetwork) else { throw ServiceBypassError.invalidNetwork }
        for dns in settings.dnsSettings?.servers ?? [] where networks.contains(where: { $0.contains(address: dns) }) {
            throw ServiceBypassError.dnsConflict
        }
        let tunnelAddresses = (settings.ipv4Settings?.addresses ?? []) + (settings.ipv6Settings?.addresses ?? [])
        guard !tunnelAddresses.contains(where: { ip in networks.contains { $0.contains(address: ip) } }) else {
            throw ServiceBypassError.tunnelAddressConflict
        }
        let v4 = networks.filter { !$0.isIPv6 }, v6 = networks.filter(\.isIPv6)
        if !v4.isEmpty {
            guard let ipv4 = settings.ipv4Settings?.copy() as? NEIPv4Settings else {
                throw ServiceBypassError.missingNetworkSettings
            }
            var routes = ipv4.excludedRoutes ?? []
            for network in v4 where !routes.contains(where: {
                $0.destinationAddress == network.address && $0.destinationSubnetMask == network.ipv4Mask
            }) {
                routes.append(NEIPv4Route(destinationAddress: network.address, subnetMask: network.ipv4Mask))
            }
            ipv4.excludedRoutes = routes
            settings.ipv4Settings = ipv4
        }
        if !v6.isEmpty {
            guard let ipv6 = settings.ipv6Settings?.copy() as? NEIPv6Settings else {
                throw ServiceBypassError.missingNetworkSettings
            }
            var routes = ipv6.excludedRoutes ?? []
            for network in v6 where !routes.contains(where: {
                $0.destinationAddress == network.address && $0.destinationNetworkPrefixLength.intValue == network.prefixLength
            }) {
                routes.append(NEIPv6Route(destinationAddress: network.address, networkPrefixLength: NSNumber(value: network.prefixLength)))
            }
            ipv6.excludedRoutes = routes
            settings.ipv6Settings = ipv6
        }
        return settings
    }
}
