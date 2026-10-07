import Foundation

enum TunnelProbeResult {
    case success, noReply, inconclusive
}

/// Monotonic packet activity, sampled under PacketFlowBridge's lock.
struct TunnelTrafficActivity {
    private(set) var lastInbound: TimeInterval?
    private var lastOutbound: TimeInterval?
    private(set) var unansweredSince: TimeInterval?

    mutating func outbound(at now: TimeInterval) {
        if let lastOutbound, now - lastOutbound > 15 { unansweredSince = nil }
        lastOutbound = now
        if unansweredSince == nil { unansweredSince = now }
    }

    mutating func inbound(at now: TimeInterval) {
        lastInbound = now
        unansweredSince = nil
    }

    func needsProbe(at now: TimeInterval) -> Bool {
        guard let lastOutbound, now - lastOutbound <= 5 else { return false }
        return unansweredSince.map { now - $0 >= 15 } ?? false
    }

    /// Real decrypted traffic is stronger evidence than a failed synthetic
    /// query. Only traffic received during this check counts, never old data
    /// from before a network switch or a previous verification attempt.
    func receivedInbound(since startedAt: TimeInterval) -> Bool {
        lastInbound.map { $0 >= startedAt } ?? false
    }
}

/// A root NS query sends no user hostname to the VPN's configured DNS servers.
/// Even an error response proves a round trip through the data plane; DNS health
/// itself is outside the reconnect policy.
struct TunnelDNSQuery {
    let id: UInt16

    var data: Data {
        Data([UInt8(id >> 8), UInt8(id & 0xff), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0,
              0, 0, 2, 0, 1]) // RD, QDCOUNT=1, root, NS, IN
    }

    func accepts(_ response: Data) -> Bool {
        let bytes = Array(response)
        guard bytes.count >= 17 else { return false }
        return bytes[0] == UInt8(id >> 8) && bytes[1] == UInt8(id & 0xff)
            && bytes[2] & 0xf8 == 0x80 // QR=1, opcode=QUERY
            && bytes[4] == 0 && bytes[5] == 1
            && Array(bytes[12..<17]) == [0, 0, 2, 0, 1]
    }
}
