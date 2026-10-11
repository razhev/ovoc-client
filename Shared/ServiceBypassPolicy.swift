import Foundation
import CoreFoundation

public enum BypassService: String, CaseIterable, Codable, Hashable {
    case ozon, wildberries, yandex
    case max, cdek, gosuslugi, mosru, mosenergosbyt
    case tbank, sber
}

public enum ServiceBypassError: String, Error, LocalizedError, CaseIterable {
    case invalidPolicy, invalidCatalog, invalidNetwork, tooManyRoutes
    case dnsConflict, tunnelAddressConflict, missingNetworkSettings, profileBusy, noProfile
    public var errorDescription: String? { "serviceBypass:\(rawValue)" }
}

public struct ServiceBypassPolicy: Equatable {
    public static let configurationKey = "serviceBypassPolicy"
    public let services: Set<BypassService>
    public init(services: Set<BypassService> = []) { self.services = services }

    public init(configuration: [String: Any]?) throws {
        guard let raw = configuration?[Self.configurationKey] else { self.init(); return }
        guard let dict = raw as? [String: Any],
              let version = dict["schemaVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              let ids = dict["services"] as? [String], ids.count <= BypassService.allCases.count,
              Set(ids).count == ids.count else { throw ServiceBypassError.invalidPolicy }
        let values = ids.compactMap(BypassService.init(rawValue:))
        guard values.count == ids.count else { throw ServiceBypassError.invalidPolicy }
        self.init(services: Set(values))
    }

    public var propertyList: [String: Any] {
        ["schemaVersion": 1, "services": services.map(\.rawValue).sorted()]
    }

    public func updating(_ configuration: [String: Any]) -> [String: Any] {
        var updated = configuration
        updated[Self.configurationKey] = propertyList
        return updated
    }
}

public struct ServiceBypassCatalog: Decodable {
    public struct Service: Decodable {
        public struct Route: Decodable {
            public let cidr: String
            public let source: String
            public let domains: [String]
        }
        public let id: BypassService
        public let routes: [Route]
    }
    public static let maximumBytes = 256 * 1024
    public static let maximumRoutes = 1024
    public let schemaVersion: Int
    public let catalogVersion: String
    public let reviewedAt: String
    public let services: [Service]

    public static func load(bundle: Bundle) throws -> Self {
        guard let url = bundle.url(forResource: "ServiceBypassCatalog", withExtension: "json"),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes, let data = try? Data(contentsOf: url) else {
            throw ServiceBypassError.invalidCatalog
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes,
              let catalog = try? JSONDecoder().decode(Self.self, from: data),
              catalog.schemaVersion == 1, !catalog.catalogVersion.isEmpty,
              !catalog.reviewedAt.isEmpty,
              Set(catalog.services.map(\.id)) == Set(BypassService.allCases),
              catalog.services.count == BypassService.allCases.count else {
            throw ServiceBypassError.invalidCatalog
        }
        _ = try catalog.networks(for: ServiceBypassPolicy(services: Set(BypassService.allCases)))
        return catalog
    }

    public func networks(for policy: ServiceBypassPolicy) throws -> [IPNetwork] {
        var result: [IPNetwork] = []
        for service in services where policy.services.contains(service.id) {
            guard !service.routes.isEmpty else { throw ServiceBypassError.invalidCatalog }
            for route in service.routes {
                guard result.count < Self.maximumRoutes else { throw ServiceBypassError.tooManyRoutes }
                let network = try IPNetwork(route.cidr)
                guard network.isPublicServiceNetwork, !route.source.isEmpty, !route.domains.isEmpty else {
                    throw ServiceBypassError.invalidNetwork
                }
                result.append(network)
            }
        }
        return IPNetwork.normalized(result)
    }

    #if SWIFT_PACKAGE
    public static func loadBundled() throws -> Self { try load(bundle: .module) }
    #endif
}
