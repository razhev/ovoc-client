import XCTest
@testable import TunnelRuntime

final class TunnelHealthTests: XCTestCase {
    func testIdleTunnelDoesNotTriggerRecovery() {
        let activity = TunnelTrafficActivity()
        XCTAssertFalse(activity.needsProbe(at: 10_000))
    }

    func testOutboundWithoutRepliesTriggersProbeAndInboundClearsSuspicion() {
        var activity = TunnelTrafficActivity()
        activity.outbound(at: 10)
        activity.outbound(at: 20)
        XCTAssertFalse(activity.needsProbe(at: 24))
        XCTAssertTrue(activity.needsProbe(at: 25))
        activity.inbound(at: 26)
        XCTAssertEqual(activity.lastInbound, 26)
        XCTAssertFalse(activity.needsProbe(at: 100))
        activity.outbound(at: 101)
        XCTAssertFalse(activity.needsProbe(at: 102))
    }

    func testProbeRequiresMatchingDNSReplyAndAcceptsDNSErrorAsRoundTrip() {
        let query = TunnelDNSQuery(id: 0xabcd)
        XCTAssertEqual(Array(query.data), [0xab, 0xcd, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 1])
        XCTAssertFalse(query.accepts(query.data))
        var reply = query.data
        reply[2] = 0x81
        XCTAssertTrue(query.accepts(reply))
        reply[3] = 0x85 // REFUSED: DNS policy is not a broken VPN transport
        XCTAssertTrue(query.accepts(reply))
        reply[1] = 0
        XCTAssertFalse(query.accepts(reply))
        reply[1] = 0xcd
        reply[14] = 1 // different question
        XCTAssertFalse(query.accepts(reply))
        XCTAssertFalse(query.accepts(Data(reply.prefix(12))))
    }
}
