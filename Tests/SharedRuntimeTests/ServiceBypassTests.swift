import XCTest
@testable import SharedRuntime

final class ServiceBypassTests: XCTestCase {
    func testLegacyProfilesAndAllSelectionsRoundTripAsPropertyLists() throws {
        XCTAssertEqual(try ServiceBypassPolicy(configuration: nil).services, [])
        XCTAssertEqual(try ServiceBypassPolicy(configuration: [:]).services, [])
        for mask in 0..<8 {
            let services = Set(BypassService.allCases.enumerated().compactMap { i, item in
                mask & (1 << i) == 0 ? nil : item
            })
            let policy = ServiceBypassPolicy(services: services)
            let config = policy.updating(["ovpnConfig": "certificate data", "serverIP": "203.0.113.1", "future": [1, 2]])
            let encoded = try PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)
            let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
            XCTAssertEqual(try ServiceBypassPolicy(configuration: decoded), policy)
            XCTAssertEqual(decoded["ovpnConfig"] as? String, "certificate data")
            XCTAssertEqual(decoded["serverIP"] as? String, "203.0.113.1")
            XCTAssertEqual(decoded["future"] as? [Int], [1, 2])
        }
    }

    func testInvalidPolicyNeverSilentlyDisablesExceptions() {
        let invalid: [Any] = [
            true, [], "ozon", ["schemaVersion": true, "services": []],
            ["schemaVersion": 1.1, "services": []], ["schemaVersion": 2, "services": []],
            ["schemaVersion": 1, "services": ["unknown"]],
            ["schemaVersion": 1, "services": ["ozon", "ozon"]],
            ["schemaVersion": 1, "services": "ozon"],
        ]
        for value in invalid {
            XCTAssertThrowsError(try ServiceBypassPolicy(configuration: [ServiceBypassPolicy.configurationKey: value]))
        }
    }

    func testCIDRBoundariesAndCanonicalization() throws {
        let v4 = try IPNetwork("185.73.193.119/24")
        XCTAssertEqual(v4.cidr, "185.73.193.0/24")
        XCTAssertEqual(v4.ipv4Mask, "255.255.255.0")
        XCTAssertTrue(v4.contains(address: "185.73.193.0"))
        XCTAssertTrue(v4.contains(address: "185.73.193.255"))
        XCTAssertFalse(v4.contains(address: "185.73.194.0"))
        let v6 = try IPNetwork("2a02:6b8::115/62")
        XCTAssertEqual(v6.cidr, "2a02:6b8::/62")
        XCTAssertTrue(v6.contains(address: "2a02:6b8:0:3:ffff:ffff:ffff:ffff"))
        XCTAssertFalse(v6.contains(address: "2a02:6b8:0:4::"))
        XCTAssertFalse(v6.contains(address: "185.73.193.1"))
        XCTAssertTrue(try IPNetwork("2a02:6b8::115/128").contains(address: "2a02:6b8::115"))
    }

    func testMalformedCIDRsAndNonPublicNetworks() throws {
        for text in ["foo/24", "1.2.3.4/33", "::/129", "1.2.3.4/-1", "1.2.3.4/", "1.2.3.4", "1.2.3.4/24/1", "fe80::1%en0/64", "1.2.3.4\0/32"] {
            XCTAssertThrowsError(try IPNetwork(text), text)
        }
        for text in ["0.0.0.0/0", "::/0", "127.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "192.168.0.0/16", "169.254.0.0/16", "192.0.2.0/24", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4", "fc00::/7", "fe80::/10", "2001:db8::/32", "64:ff9b::/96", "2002::/16", "3fff::/20", "128.0.0.0/1"] {
            XCTAssertFalse(try IPNetwork(text).isPublicServiceNetwork, text)
        }
    }

    func testNormalizationDoesNotRoundUpOrRetainDuplicates() throws {
        let inputs = try ["185.73.193.0/24", "185.73.193.10/32", "185.73.193.119/24", "185.73.194.0/24"].map(IPNetwork.init)
        let normalized = IPNetwork.normalized(inputs)
        XCTAssertEqual(normalized.count, 2)
        XCTAssertFalse(normalized.contains { $0.contains(address: "185.73.192.1") })
        XCTAssertFalse(normalized.contains { $0.contains(address: "185.73.195.1") })
        XCTAssertEqual(IPNetwork.normalized(normalized), normalized)
    }

    func testBundledCatalogAndSelections() throws {
        let catalog = try ServiceBypassCatalog.loadBundled()
        XCTAssertEqual(try catalog.networks(for: ServiceBypassPolicy()), [])
        let all = try catalog.networks(for: ServiceBypassPolicy(services: Set(BypassService.allCases)))
        XCTAssertTrue(all.count < 1024)
        XCTAssertTrue(all.contains { $0.contains(address: "185.73.193.119") })
        XCTAssertTrue(all.contains { $0.contains(address: "185.62.202.2") })
        XCTAssertTrue(all.contains { $0.contains(address: "87.250.250.198") })
        for address in ["1.1.1.1", "8.8.8.8", "77.88.8.8", "84.201.128.1", "2a02:6b8:b999::1"] {
            XCTAssertFalse(all.contains { $0.contains(address: address) }, address)
        }
        let ozon = try catalog.networks(for: ServiceBypassPolicy(services: [.ozon]))
        XCTAssertFalse(ozon.contains { $0.contains(address: "185.62.202.2") })
    }

    func testCatalogRejectsMissingGroupsBadNetworksAndExcessiveInput() throws {
        func data(_ routes: [String], ids: [String] = ["ozon", "wildberries", "yandex"]) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "catalogVersion": "test", "reviewedAt": "2026-10-06",
                "services": ids.map { id in ["id": id, "routes": routes.map {
                    ["cidr": $0, "source": "fixture", "domains": ["example.test"]]
                }] },
            ])
        }
        XCTAssertThrowsError(try ServiceBypassCatalog.decode(data(["0.0.0.0/0"])))
        XCTAssertThrowsError(try ServiceBypassCatalog.decode(data([])))
        XCTAssertThrowsError(try ServiceBypassCatalog.decode(data(["185.73.193.0/24"], ids: ["ozon"])))
        XCTAssertThrowsError(try ServiceBypassCatalog.decode(data(["185.73.193.0/24"], ids: ["ozon", "ozon", "yandex"])))
        XCTAssertThrowsError(try ServiceBypassCatalog.decode(data(Array(repeating: "185.73.193.0/24", count: 350))))
        XCTAssertThrowsError(try ServiceBypassCatalog.decode(Data(repeating: 32, count: 256 * 1024 + 1)))
    }
}

@MainActor
private final class FakeProfileStore: ServiceBypassProfileStore {
    var isDisconnected = true
    var configuration: [String: Any]? = ["ovpnConfig": "unchanged", "dns1": "1.1.1.1"]
    var persisted: [String: Any]? = ["ovpnConfig": "unchanged", "dns1": "1.1.1.1"]
    var writes = 0
    var reads = 0
    var failSave = false
    var failingReads: Set<Int> = []
    var connectOnReload = false
    func reload() async throws {
        reads += 1
        if failingReads.contains(reads) { throw ServiceBypassError.noProfile }
        configuration = persisted
        if connectOnReload { isDisconnected = false }
    }
    func save(configuration: [String: Any]) async throws {
        writes += 1
        self.configuration = configuration
        if failSave { throw ServiceBypassError.noProfile }
        persisted = configuration
    }
}

final class ServiceBypassProfileTests: XCTestCase {
    @MainActor func testSuccessfulSavePreservesProfileAndReloadsIt() async throws {
        let store = FakeProfileStore()
        let policy = ServiceBypassPolicy(services: [.yandex])
        try await ServiceBypassProfileUpdate.apply(policy, to: store)
        XCTAssertEqual(store.reads, 2)
        XCTAssertEqual(store.writes, 1)
        XCTAssertEqual(store.configuration?["ovpnConfig"] as? String, "unchanged")
        XCTAssertEqual(store.configuration?["dns1"] as? String, "1.1.1.1")
        XCTAssertEqual(try ServiceBypassPolicy(configuration: store.configuration), policy)
    }

    @MainActor func testStatusChangeDuringReloadPreventsWrite() async {
        let store = FakeProfileStore()
        store.connectOnReload = true
        do {
            try await ServiceBypassProfileUpdate.apply(ServiceBypassPolicy(services: [.ozon]), to: store)
            XCTFail("Must not save an active profile")
        } catch { XCTAssertEqual(error as? ServiceBypassError, .profileBusy) }
        XCTAssertEqual(store.writes, 0)
    }

    @MainActor func testFailedSaveRestoresPersistentSelection() async throws {
        let store = FakeProfileStore()
        store.failSave = true
        do {
            try await ServiceBypassProfileUpdate.apply(ServiceBypassPolicy(services: [.ozon]), to: store)
            XCTFail("Expected save failure")
        } catch {}
        XCTAssertEqual(try ServiceBypassPolicy(configuration: store.configuration).services, [])
    }

    @MainActor func testSuccessfulSaveFailedReloadReportsErrorAndRecoversActualChoice() async throws {
        let store = FakeProfileStore()
        store.failingReads = [2]
        let policy = ServiceBypassPolicy(services: [.wildberries])
        do {
            try await ServiceBypassProfileUpdate.apply(policy, to: store)
            XCTFail("Expected reload failure")
        } catch {}
        XCTAssertEqual(store.reads, 3)
        XCTAssertEqual(try ServiceBypassPolicy(configuration: store.configuration), policy)
    }

    @MainActor func testMissingProfileAndInitialReadFailureNeverWrite() async {
        for failsRead in [false, true] {
            let store = FakeProfileStore()
            store.persisted = nil
            if failsRead { store.failingReads = [1] }
            do {
                try await ServiceBypassProfileUpdate.apply(ServiceBypassPolicy(), to: store)
                XCTFail("Expected failure")
            } catch {}
            XCTAssertEqual(store.writes, 0)
        }
    }
}
