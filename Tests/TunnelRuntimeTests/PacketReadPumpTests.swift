import XCTest
@testable import TunnelRuntime

final class PacketReadPumpTests: XCTestCase {
    func testReconnectHasOneOSReadAndOnlyNewestConsumerReceivesPackets() {
        var pending: PacketReadPump.Completion?
        var reads = 0
        let pump = PacketReadPump { completion in reads += 1; pending = completion }
        let generation = pump.newGeneration()
        pump.request(generation: generation) { _, _ in XCTFail("Retired tun reader consumed packets") }
        for _ in 0..<20 {
            pump.discardPendingConsumer()
            pump.request(generation: generation) { _, _ in XCTFail("Old reconnect reader consumed packets") }
        }
        var received: [Data] = []
        pump.request(generation: generation) { packets, _ in received = packets }
        XCTAssertEqual(reads, 1)
        pending?([Data([1, 2, 3])], [2])
        XCTAssertEqual(received, [Data([1, 2, 3])])
    }

    func testOldAdapterCannotStealPendingReadFromReplacement() {
        var pending: PacketReadPump.Completion?
        var reads = 0
        let pump = PacketReadPump { completion in reads += 1; pending = completion }
        let old = pump.newGeneration()
        pump.request(generation: old) { _, _ in XCTFail("Old adapter") }
        let current = pump.newGeneration()
        var received = false
        pump.request(generation: current) { _, _ in received = true }
        pump.request(generation: old) { _, _ in XCTFail("Old adapter re-registered") }
        XCTAssertEqual(reads, 1)
        pending?([], [])
        XCTAssertTrue(received)
    }

    func testStopDropsOutstandingPacketsAndNewSessionCanRead() {
        var pending: PacketReadPump.Completion?
        let pump = PacketReadPump { pending = $0 }
        let old = pump.newGeneration()
        pump.request(generation: old) { _, _ in XCTFail("Stopped adapter") }
        let new = pump.newGeneration()
        pending?([], [])
        var received = false
        pump.request(generation: new) { _, _ in received = true }
        pending?([], [])
        XCTAssertTrue(received)
    }

    func testCompletionCanSynchronouslyRequestNextBatchWithoutDeadlock() {
        var pending: PacketReadPump.Completion?
        let pump = PacketReadPump { pending = $0 }
        let generation = pump.newGeneration()
        var batches = 0
        pump.request(generation: generation) { _, _ in
            batches += 1
            pump.request(generation: generation) { _, _ in batches += 1 }
        }
        pending?([], [])
        pending?([], [])
        XCTAssertEqual(batches, 2)
    }
}
