import NetworkExtension

@MainActor
final class SystemServiceBypassProfileStore: ServiceBypassProfileStore {
    let manager: NETunnelProviderManager
    private(set) var stateIsKnown = false

    init(manager: NETunnelProviderManager) { self.manager = manager }

    var isDisconnected: Bool {
        manager.connection.status == .disconnected || manager.connection.status == .invalid
    }

    var configuration: [String: Any]? {
        guard stateIsKnown else { return nil }
        return (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
    }

    func reload() async throws {
        stateIsKnown = false
        try await manager.loadFromPreferences()
        stateIsKnown = true
    }

    func save(configuration: [String: Any]) async throws {
        guard isDisconnected else { throw ServiceBypassError.profileBusy }
        guard let proto = manager.protocolConfiguration?.copy() as? NETunnelProviderProtocol else {
            throw ServiceBypassError.noProfile
        }
        proto.providerConfiguration = configuration
        // Keep the existing route enforcement mode until device validation. The
        // current client already uses includeAllNetworks=false for Cloak routing.
        if try !ServiceBypassPolicy(configuration: configuration).services.isEmpty {
            proto.includeAllNetworks = false
        }
        manager.protocolConfiguration = proto
        stateIsKnown = false
        try await manager.saveToPreferences()
    }
}
