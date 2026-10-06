import Foundation

/// Small boundary around the asynchronous preferences API, usable without a VPN
/// entitlement in tests. The app holds its operation lock for this entire call.
@MainActor
public protocol ServiceBypassProfileStore: AnyObject {
    var isDisconnected: Bool { get }
    var configuration: [String: Any]? { get }
    func reload() async throws
    func save(configuration: [String: Any]) async throws
}

public enum ServiceBypassProfileUpdate {
    @MainActor
    public static func apply(_ policy: ServiceBypassPolicy, to store: ServiceBypassProfileStore) async throws {
        try await store.reload()
        guard store.isDisconnected else { throw ServiceBypassError.profileBusy }
        guard let current = store.configuration,
              let profile = current["ovpnConfig"] as? String, !profile.isEmpty else {
            throw ServiceBypassError.noProfile
        }
        do {
            try await store.save(configuration: policy.updating(current))
            try await store.reload()
            guard try ServiceBypassPolicy(configuration: store.configuration) == policy else {
                throw ServiceBypassError.invalidPolicy
            }
        } catch {
            // Recover actual persistent state even when save succeeded but reload
            // failed. The caller invalidates its UI if this recovery also fails.
            try? await store.reload()
            throw error
        }
    }
}
