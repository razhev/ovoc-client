import Foundation
import Darwin

/// Value-only CIDR. No DNS lookup; parsing never accepts a hostname or a zone ID.
public struct IPNetwork: Hashable {
    public let bytes: [UInt8]
    public let prefixLength: Int
    public var isIPv6: Bool { bytes.count == 16 }

    public init(_ cidr: String) throws {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty,
              parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              let prefix = Int(parts[1]),
              let address = Self.parseAddress(String(parts[0])),
              (0...address.count * 8).contains(prefix) else {
            throw ServiceBypassError.invalidNetwork
        }
        self.prefixLength = prefix
        self.bytes = Self.mask(address, prefix: prefix)
    }

    public var address: String {
        var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result = bytes.withUnsafeBytes {
            inet_ntop(isIPv6 ? AF_INET6 : AF_INET, $0.baseAddress!, &output, socklen_t(output.count))
        }
        precondition(result != nil) // bytes always come from inet_pton
        return String(cString: output)
    }

    public var cidr: String { "\(address)/\(prefixLength)" }

    public var ipv4Mask: String {
        Self.mask([255, 255, 255, 255], prefix: prefixLength).map(String.init).joined(separator: ".")
    }

    public func contains(address: String) -> Bool {
        guard let candidate = Self.parseAddress(address), candidate.count == bytes.count else { return false }
        return Self.mask(candidate, prefix: prefixLength) == bytes
    }

    public func contains(_ other: IPNetwork) -> Bool {
        bytes.count == other.bytes.count && prefixLength <= other.prefixLength
            && Self.mask(other.bytes, prefix: prefixLength) == bytes
    }

    public func overlaps(_ other: IPNetwork) -> Bool { contains(other) || other.contains(self) }

    /// Only public service networks. Broad prefixes overlapping a reserved block
    /// are rejected as a whole, rather than accidentally permitting private traffic.
    public var isPublicServiceNetwork: Bool {
        if isIPv6 {
            guard Self.globalIPv6.contains(self) else { return false }
        }
        return !Self.reserved.contains(where: overlaps)
    }

    /// Drop duplicates and contained networks. Never round up to a wider prefix.
    public static func normalized(_ networks: [IPNetwork]) -> [IPNetwork] {
        let sorted = Set(networks).sorted {
            if $0.bytes.count != $1.bytes.count { return $0.bytes.count < $1.bytes.count }
            if $0.prefixLength != $1.prefixLength { return $0.prefixLength < $1.prefixLength }
            return $0.bytes.lexicographicallyPrecedes($1.bytes)
        }
        var result: [IPNetwork] = []
        for network in sorted where !result.contains(where: { $0.contains(network) }) {
            result.append(network)
        }
        return result
    }

    private static func parseAddress(_ text: String) -> [UInt8]? {
        guard !text.isEmpty, !text.contains("%"), !text.utf8.contains(0) else { return nil }
        let family = text.contains(":") ? AF_INET6 : AF_INET
        var bytes = [UInt8](repeating: 0, count: family == AF_INET6 ? 16 : 4)
        guard text.withCString({ inet_pton(family, $0, &bytes) }) == 1 else { return nil }
        return bytes
    }

    private static func mask(_ bytes: [UInt8], prefix: Int) -> [UInt8] {
        bytes.enumerated().map { i, byte in
            let bits = min(8, max(0, prefix - i * 8))
            return bits == 0 ? 0 : byte & (UInt8.max << (8 - bits))
        }
    }

    private static let globalIPv6 = try! IPNetwork("2000::/3")
    private static let reserved = [
        "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
        "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24",
        "192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24",
        "203.0.113.0/24", "224.0.0.0/3", "2001::/23", "2001:db8::/32",
        "2002::/16", "3fff::/20",
    ].map { try! IPNetwork($0) }
}
