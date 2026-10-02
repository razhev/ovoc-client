import Foundation
import Darwin
import XCTest
@testable import TunnelRuntime

final class IPv6PacketFilterTests: XCTestCase {
    func testServerIPv6PreservesMixedPacketsAndTheirOrder() {
        let packets = [Data([0x60, 1]), Data([0x45, 2]), Data([0x60, 3])]
        let families = [AF_INET6, AF_INET, AF_INET6].map { NSNumber(value: $0) }
        let result = IPv6PacketFilter.filter(packets, protocols: families, sinkEnabled: false)
        XCTAssertEqual(result.packets, packets)
        XCTAssertEqual(result.protocols, families)
        XCTAssertEqual(result.dropped, 0)
    }

    func testSinkRemovesOnlyIPv6AndKeepsProtocolAlignment() {
        let packets = [Data([0x60, 1]), Data([0x45, 2]), Data([0x60, 3])]
        let families = [AF_INET6, AF_INET, AF_INET6].map { NSNumber(value: $0) }
        let result = IPv6PacketFilter.filter(packets, protocols: families, sinkEnabled: true)
        XCTAssertEqual(result.packets, [packets[1]])
        XCTAssertEqual(result.protocols, [NSNumber(value: AF_INET)])
        XCTAssertEqual(result.dropped, 2)
    }

    func testSinkCanReturnEmptyBatchAndThenForwardAfterModeChange() {
        let packets = [Data([0x60])]
        let families = [NSNumber(value: AF_INET6)]
        XCTAssertTrue(IPv6PacketFilter.filter(packets, protocols: families, sinkEnabled: true).packets.isEmpty)
        XCTAssertEqual(IPv6PacketFilter.filter(packets, protocols: families, sinkEnabled: false).packets, packets)
        XCTAssertTrue(IPv6PacketFilter.filter(packets, protocols: families, sinkEnabled: true).packets.isEmpty)
    }
}
