import Foundation
import Darwin

enum IPv6PacketFilter {
    static func filter(
        _ packets: [Data], protocols: [NSNumber], sinkEnabled: Bool
    ) -> (packets: [Data], protocols: [NSNumber], dropped: Int) {
        let ipv6 = NSNumber(value: AF_INET6)
        guard sinkEnabled, protocols.contains(ipv6) else { return (packets, protocols, 0) }
        var kept: [Data] = []
        var families: [NSNumber] = []
        var dropped = 0
        for (packet, family) in zip(packets, protocols) {
            if family == ipv6 {
                dropped += 1
            } else {
                kept.append(packet)
                families.append(family)
            }
        }
        return (kept, families, dropped)
    }
}
