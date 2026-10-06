import XCTest
@testable import TunnelRuntime

final class ReconnectCoordinatorTests: XCTestCase {
    private let wifi = NetworkPathSnapshot(isAvailable: true, interface: "en0#4", addresses: ["192.0.2.2"])
    private let cell = NetworkPathSnapshot(isAvailable: true, interface: "pdp_ip0#5", addresses: ["198.51.100.2"])
    private let offline = NetworkPathSnapshot(isAvailable: false)

    private func online() -> ReconnectCoordinator {
        var coordinator = ReconnectCoordinator()
        coordinator.start()
        XCTAssertTrue(coordinator.pathChanged(wifi).isEmpty)
        _ = coordinator.connected()
        XCTAssertEqual(coordinator.state, .verifying)
        XCTAssertTrue(coordinator.probeFinished(ticket: coordinator.ticket, success: true).contains(.ready))
        return coordinator
    }

    func testSystemStartCompletesBeforeScopedProbeCanRun() {
        var c = ReconnectCoordinator()
        c.start()
        _ = c.pathChanged(wifi)
        let effects = c.connected()
        let activation = effects.firstIndex(of: .activateTunnel)
        let probe = effects.firstIndex(of: .probe(ticket: c.ticket))
        XCTAssertNotNil(activation)
        XCTAssertNotNil(probe)
        XCTAssertLessThan(activation ?? .max, probe ?? .min)
        XCTAssertEqual(c.state, .verifying)
        XCTAssertFalse(effects.contains(.ready)) // health still has its own deadline
    }

    func testRecoveryClearsReassertingBeforeScopedProbe() {
        var c = online()
        _ = c.pathChanged(cell)
        _ = c.timerFired(ticket: c.ticket)
        _ = c.reconnecting()
        let effects = c.connected()
        let resumed = effects.firstIndex(of: .reassert(false))
        let probe = effects.firstIndex(of: .probe(ticket: c.ticket))
        XCTAssertNotNil(resumed)
        XCTAssertNotNil(probe)
        XCTAssertLessThan(resumed ?? .max, probe ?? .min)
        XCTAssertEqual(c.attempts, 1) // activation alone must not reset recovery budget
    }

    func testRealTrafficConfirmsStartupWhenSyntheticDNSDoesNotReply() {
        var c = ReconnectCoordinator()
        c.start()
        _ = c.pathChanged(wifi)
        _ = c.connected()
        var activity = TunnelTrafficActivity()
        activity.inbound(at: 101)
        let effects = c.probeFinished(ticket: c.ticket, success: activity.receivedInbound(since: 100))
        XCTAssertEqual(c.state, .online)
        XCTAssertTrue(effects.contains(.ready))
        XCTAssertFalse(effects.contains(.reassert(true)))
    }

    func testNetworkLossImmediatelyReassertsAndWaitsWithoutTimer() {
        var c = online()
        let effects = c.pathChanged(offline)
        XCTAssertTrue(effects.contains(.reassert(true)))
        XCTAssertEqual(c.state, .waitingForNetwork)
        XCTAssertFalse(effects.contains { if case .schedule = $0 { return true }; return false })
        XCTAssertTrue(c.timerFired(ticket: c.ticket - 1).isEmpty)
        // A late success from the dead path must not turn the VPN green.
        XCTAssertFalse(c.connected().contains(.ready))
        _ = c.pathChanged(cell)
        XCTAssertEqual(c.state, .settling)
        XCTAssertTrue(c.timerFired(ticket: c.ticket).contains(.reconnect(attempt: 1)))
    }

    func testRapidSwitchesInvalidateTimersAndOnlyReconnectLatestPath() {
        var c = online()
        _ = c.pathChanged(cell)
        let oldTicket = c.ticket
        _ = c.pathChanged(wifi)
        XCTAssertTrue(c.timerFired(ticket: oldTicket).isEmpty)
        XCTAssertTrue(c.connected().isEmpty)
        XCTAssertTrue(c.timerFired(ticket: c.ticket).contains(.reconnect(attempt: 1)))
        XCTAssertTrue(c.connected().isEmpty) // wait for RECONNECTING acknowledgement
        _ = c.reconnecting()
        _ = c.connected()
        XCTAssertEqual(c.state, .verifying)
        XCTAssertTrue(c.probeFinished(ticket: c.ticket, success: true).contains(.reassert(false)))
    }

    func testDuplicatesAndVirtualRouteUpdatesDoNotReconnect() {
        var c = online()
        XCTAssertTrue(c.pathChanged(wifi).isEmpty)
        XCTAssertTrue(c.connected().isEmpty)
        XCTAssertEqual(c.attempts, 0)
        let otherWiFi = NetworkPathSnapshot(isAvailable: true, interface: "en0#4", addresses: ["203.0.113.2"])
        XCTAssertTrue(c.pathChanged(otherWiFi).contains(.reassert(true)))
    }

    func testFirstPathAfterConnectedIsOnlyBaselineUnlessOffline() {
        var c = ReconnectCoordinator()
        c.start()
        _ = c.connected()
        _ = c.probeFinished(ticket: c.ticket, success: true)
        XCTAssertTrue(c.pathChanged(wifi).isEmpty)
        XCTAssertEqual(c.state, .online)
        XCTAssertTrue(c.pathChanged(offline).contains(.reassert(true)))
    }

    func testNetworkChangeDuringStartupIsNotLost() {
        var c = ReconnectCoordinator()
        c.start()
        _ = c.pathChanged(wifi)
        _ = c.pathChanged(cell)
        XCTAssertTrue(c.connected().contains(.reassert(true)))
        XCTAssertEqual(c.state, .settling)
    }

    func testRecoveryBudgetAndConfirmedStopBeforeLastAttempt() {
        var c = online()
        _ = c.pathChanged(cell)
        for attempt in 1...2 {
            XCTAssertTrue(c.timerFired(ticket: c.ticket).contains(.reconnect(attempt: attempt)))
            _ = c.reconnecting()
            let deadline = c.ticket
            XCTAssertTrue(c.reconnecting().isEmpty)
            XCTAssertEqual(c.ticket, deadline) // autonomous retries cannot extend deadline
            _ = c.timerFired(ticket: deadline)
            XCTAssertEqual(c.state, .settling)
        }
        let effects = c.timerFired(ticket: c.ticket)
        XCTAssertTrue(effects.contains(.stopAdapter))
        XCTAssertEqual(c.state, .stoppingAdapter)
        XCTAssertTrue(c.connected().isEmpty)
        _ = c.disconnected()
        XCTAssertTrue(c.timerFired(ticket: c.ticket).contains(.replaceAdapter(attempt: 3)))
        _ = c.connected() // new adapter has no RECONNECTING event
        let failure = c.probeFinished(ticket: c.ticket, success: false)
        XCTAssertEqual(c.state, .failed)
        XCTAssertTrue(failure.contains { if case .fail = $0 { return true }; return false })
        XCTAssertTrue(c.pathChanged(wifi).isEmpty)
    }

    func testHungStopFailsInsteadOfRunningTwoAdapters() {
        var c = online()
        _ = c.pathChanged(cell)
        for _ in 1...2 {
            _ = c.timerFired(ticket: c.ticket)
            _ = c.timerFired(ticket: c.ticket)
        }
        _ = c.timerFired(ticket: c.ticket)
        XCTAssertEqual(c.state, .stoppingAdapter)
        let stopTicket = c.ticket
        XCTAssertTrue(c.pathChanged(offline).isEmpty)
        XCTAssertEqual(c.ticket, stopTicket)
        _ = c.timerFired(ticket: stopTicket)
        XCTAssertEqual(c.state, .failed)
    }

    func testNoReplacementUntilNetworkReturnsAfterConfirmedStop() {
        var c = online()
        _ = c.pathChanged(offline)
        _ = c.disconnected()
        XCTAssertEqual(c.state, .waitingForNetwork)
        _ = c.pathChanged(cell)
        XCTAssertTrue(c.timerFired(ticket: c.ticket).contains(.replaceAdapter(attempt: 1)))
    }

    func testStaleProbeCannotCompleteAfterPathChangeOrStop() {
        var c = online()
        _ = c.checkHealth()
        let probeTicket = c.ticket
        _ = c.pathChanged(cell)
        XCTAssertTrue(c.probeFinished(ticket: probeTicket, success: true).isEmpty)
        let timerTicket = c.ticket
        _ = c.stop()
        XCTAssertTrue(c.timerFired(ticket: timerTicket).isEmpty)
        XCTAssertTrue(c.connected().isEmpty)
        XCTAssertTrue(c.reconnecting().isEmpty)
        XCTAssertTrue(c.disconnected().isEmpty)
        XCTAssertTrue(c.pathChanged(wifi).isEmpty)
        XCTAssertTrue(c.checkHealth().isEmpty)
    }

    func testSilentConnectionIsOnlyRecoveredAfterProbeFails() {
        var c = online()
        let check = c.checkHealth()
        XCTAssertFalse(check.contains(.reassert(true)))
        XCTAssertTrue(c.checkHealth().isEmpty) // one probe at a time
        XCTAssertTrue(c.probeFinished(ticket: c.ticket, success: false).contains(.reassert(true)))
        XCTAssertEqual(c.state, .settling)
    }

    func testSpontaneousCoreReconnectHasBoundedDeadline() {
        var c = online()
        XCTAssertTrue(c.reconnecting().contains(.reassert(true)))
        XCTAssertEqual(c.attempts, 1)
        let deadline = c.ticket
        XCTAssertTrue(c.reconnecting().isEmpty)
        _ = c.timerFired(ticket: deadline)
        XCTAssertEqual(c.state, .settling)
    }

    func testHandshakeDoesNotExtendRecoveryDeadlineWhileVerifyingTraffic() {
        var c = online()
        _ = c.pathChanged(cell)
        _ = c.timerFired(ticket: c.ticket)
        _ = c.reconnecting()
        let deadline = c.ticket
        _ = c.connected()
        XCTAssertEqual(c.ticket, deadline)
        XCTAssertEqual(c.state, .verifying)
        _ = c.timerFired(ticket: deadline)
        XCTAssertEqual(c.state, .settling)
        XCTAssertTrue(c.probeFinished(ticket: deadline, success: true).isEmpty)
    }
}
