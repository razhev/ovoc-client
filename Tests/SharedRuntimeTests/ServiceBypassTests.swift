import XCTest
@testable import SharedRuntime

final class ServiceBypassTests: XCTestCase {
    func testLegacyProfilesAndAllSelectionsRoundTripAsPropertyLists() throws {
        XCTAssertEqual(try ServiceBypassPolicy(configuration: nil).services, [])
        XCTAssertEqual(try ServiceBypassPolicy(configuration: [:]).services, [])
        for mask in 0..<(1 << BypassService.allCases.count) {
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

    func testExistingThreeServiceChoiceDoesNotEnableNewServicesOnUpgrade() throws {
        let saved: [String: Any] = [ServiceBypassPolicy.configurationKey: [
            "schemaVersion": 1, "services": ["ozon", "wildberries", "yandex"],
        ]]
        let policy = try ServiceBypassPolicy(configuration: saved)
        XCTAssertEqual(policy.services, [.ozon, .wildberries, .yandex])
        XCTAssertNotEqual(policy.services, Set(BypassService.allCases))
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

    func testOzonRegionalImagesAndFinanceAreCoveredWithoutExcludingCDNProviders() throws {
        let catalog = try ServiceBypassCatalog.loadBundled()
        let networks = try catalog.networks(for: ServiceBypassPolicy(services: [.ozon]))
        // Observed A records on 2026-10-10, outside the original three /24s.
        for address in ["5.101.71.73", "185.40.155.13", "212.164.51.50", "212.164.51.51",
                        "85.173.175.100", "85.173.175.101", "176.208.118.244", "176.208.118.245",
                        "194.9.211.128", "31.130.143.131"] {
            XCTAssertTrue(networks.contains { $0.contains(address: address) }, address)
        }
        // Adjacent hosting/CDN addresses are not part of the observed service.
        for address in ["5.101.71.74", "185.40.155.14", "212.164.51.52", "85.173.175.102",
                        "176.208.118.246", "194.9.210.1", "31.130.142.1"] {
            XCTAssertFalse(networks.contains { $0.contains(address: address) }, address)
        }
    }

    func testNewServicesCoverTheirEndpointsWithoutExcludingSharedProviderNetworks() throws {
        let catalog = try ServiceBypassCatalog.loadBundled()
        let cases: [(BypassService, [String], [String])] = [
            (.max, ["155.212.204.140", "155.212.204.150", "155.212.204.70", "155.212.205.225",
                    "217.20.147.23", "217.20.155.82"], ["155.212.204.1", "217.20.147.1"]),
            (.cdek, ["91.206.127.236", "155.212.234.130", "109.238.90.137", "155.212.234.5"],
                    ["91.206.127.1", "155.212.234.1", "109.238.90.1"]),
            (.gosuslugi, ["213.59.253.7", "213.59.254.8", "213.59.253.6", "212.193.153.34",
                         "46.235.184.101"], ["213.59.253.1", "212.193.153.1", "46.235.184.1"]),
            (.mosru, ["94.79.51.135", "94.79.51.136", "212.11.155.134", "212.45.30.1",
                      "212.11.155.165", "212.11.152.248"], ["94.79.51.1", "212.11.155.1", "212.45.30.4"]),
            (.mosenergosbyt, ["195.82.140.164", "195.82.140.228", "195.82.140.218"], ["195.82.141.1"]),
        ]
        for (service, included, excluded) in cases {
            let networks = try catalog.networks(for: ServiceBypassPolicy(services: [service]))
            for address in included {
                XCTAssertTrue(networks.contains { $0.contains(address: address) }, "\(service): \(address)")
            }
            for address in excluded + ["1.1.1.1", "8.8.8.8", "185.73.193.68"] {
                XCTAssertFalse(networks.contains { $0.contains(address: address) }, "\(service): \(address)")
            }
        }
    }

    func testCatalogRejectsMissingGroupsBadNetworksAndExcessiveInput() throws {
        func data(_ routes: [String], ids: [String]? = nil) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "catalogVersion": "test", "reviewedAt": "2026-10-06",
                "services": (ids ?? BypassService.allCases.map(\.rawValue)).map { id in ["id": id, "routes": routes.map {
                    ["cidr": $0, "source": "fixture", "domains": ["example.test"]]
                }] },
            ])
        }
        XCTAssertNoThrow(try ServiceBypassCatalog.decode(data(["185.73.193.0/24"])))
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

final class ServiceBypassSelectionTests: XCTestCase {
    @MainActor func testSelectAllFromPartialChoiceThenClearAllPersistsAcrossReopening() async throws {
        let store = FakeProfileStore()
        try await ServiceBypassProfileUpdate.apply(ServiceBypassPolicy(services: [.max, .cdek]), to: store)
        let screen = ServiceBypassSelectionModel()
        screen.synchronize(try ServiceBypassPolicy(configuration: store.configuration))
        for choice: Set<BypassService> in [Set(BypassService.allCases), []] {
            let write = try XCTUnwrap(screen.updateSelection(choice, save: {
                try await ServiceBypassProfileUpdate.apply($0, to: store)
            }, readSaved: { try? ServiceBypassPolicy(configuration: store.configuration) }))
            await write.value
            XCTAssertNil(screen.saveError)
            try await store.reload()
            let reopened = ServiceBypassSelectionModel()
            reopened.synchronize(try ServiceBypassPolicy(configuration: store.configuration))
            XCTAssertEqual(reopened.selection, choice)
        }
    }

    @MainActor func testSwitchesPersistBeforeDismissAndSurviveConnectReload() async throws {
        let store = FakeProfileStore()
        let screen = ServiceBypassSelectionModel()
        screen.synchronize(try ServiceBypassPolicy(configuration: store.configuration))
        let all = Set(BypassService.allCases)
        let write = try XCTUnwrap(screen.updateSelection(all, save: {
            try await ServiceBypassProfileUpdate.apply($0, to: store)
        }, readSaved: { try? ServiceBypassPolicy(configuration: store.configuration) }))
        // The view disables Done and swipe dismissal synchronously, before the
        // Task gets its first opportunity to start a preferences operation.
        XCTAssertTrue(screen.isSaving)
        await write.value
        XCTAssertFalse(screen.isSaving)
        XCTAssertNil(screen.saveError)

        // Dismiss/recreate the screen and reload as connect() does: no explicit
        // Save button is required for the all-services choice to survive.
        try await store.reload()
        let reopened = ServiceBypassSelectionModel()
        reopened.synchronize(try ServiceBypassPolicy(configuration: store.configuration))
        XCTAssertEqual(reopened.selection, all)
        XCTAssertEqual(try ServiceBypassPolicy(configuration: store.persisted).services, all)

        for service in BypassService.allCases {
            let remaining = reopened.selection.subtracting([service])
            let next = try XCTUnwrap(reopened.updateSelection(remaining, save: {
                try await ServiceBypassProfileUpdate.apply($0, to: store)
            }, readSaved: { try? ServiceBypassPolicy(configuration: store.configuration) }))
            await next.value
        }
        try await store.reload()
        XCTAssertEqual(try ServiceBypassPolicy(configuration: store.configuration).services, [])
    }

    @MainActor func testInFlightSaveLocksEditingAndIgnoresStaleProfileEvents() async throws {
        let screen = ServiceBypassSelectionModel()
        let all = Set(BypassService.allCases)
        var persisted = ServiceBypassPolicy()
        var resumeSave: CheckedContinuation<Void, Never>?
        let started = expectation(description: "save started")
        let write = try XCTUnwrap(screen.updateSelection(all, save: { policy in
            await withCheckedContinuation { continuation in
                resumeSave = continuation
                started.fulfill()
            }
            persisted = policy
        }, readSaved: { persisted }))
        XCTAssertTrue(screen.isSaving)
        await fulfillment(of: [started], timeout: 2)
        screen.synchronize(ServiceBypassPolicy())
        screen.synchronize(nil)
        XCTAssertEqual(screen.selection, all)
        let duplicate = screen.updateSelection([], save: { _ in XCTFail("Editing must be locked") },
                                                readSaved: { persisted })
        XCTAssertNil(duplicate)
        XCTAssertEqual(screen.selection, all)
        resumeSave?.resume()
        await write.value
        XCTAssertEqual(screen.selection, all)
        XCTAssertFalse(screen.isSaving)
    }

    @MainActor func testFailedAutosaveRestoresActualChoiceAndAllowsRetry() async throws {
        let store = FakeProfileStore()
        store.failSave = true
        let screen = ServiceBypassSelectionModel()
        let save: @MainActor (ServiceBypassPolicy) async throws -> Void = {
            try await ServiceBypassProfileUpdate.apply($0, to: store)
        }
        let read: @MainActor () -> ServiceBypassPolicy? = {
            try? ServiceBypassPolicy(configuration: store.configuration)
        }
        let failed = try XCTUnwrap(screen.updateSelection([.ozon], save: save, readSaved: read))
        await failed.value
        XCTAssertNotNil(screen.saveError)
        XCTAssertFalse(screen.isSaving)
        XCTAssertEqual(screen.selection, [])
        store.failSave = false
        let retry = try XCTUnwrap(screen.updateSelection([.ozon], save: save, readSaved: read))
        await retry.value
        XCTAssertNil(screen.saveError)
        XCTAssertEqual(screen.selection, [.ozon])
    }
}
