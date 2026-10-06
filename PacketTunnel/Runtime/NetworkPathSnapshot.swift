import Foundation
import Network

/// Ignore virtual VPN interfaces and DNS/route changes made by setTunnelNetworkSettings.
/// Addresses distinguish two Wi-Fi networks even when both use en0.
struct NetworkPathSnapshot: Equatable {
    let isAvailable: Bool
    let interface: String
    let addresses: [String]

    init(isAvailable: Bool, interface: String = "none", addresses: [String] = []) {
        self.isAvailable = isAvailable
        self.interface = interface
        self.addresses = addresses.sorted()
    }

    init(_ path: Network.NWPath) {
        let physical = path.availableInterfaces.first {
            [.wifi, .cellular, .wiredEthernet].contains($0.type) && path.usesInterfaceType($0.type)
        }
        self.init(
            isAvailable: path.status == .satisfied && physical != nil,
            interface: physical.map { "\($0.name)#\($0.index)" } ?? "none",
            addresses: physical.map { Self.addresses(of: $0.name) } ?? []
        )
    }

    private static func addresses(of name: String) -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(first) }
        var result: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == name,
                  let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == AF_INET || address.pointee.sa_family == AF_INET6 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer,
                           socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: buffer))
            }
        }
        // IPv6 privacy-address rotation is not a path change for our IPv4 server.
        let ipv4 = result.filter { !$0.contains(":") }
        return ipv4.isEmpty ? result : ipv4
    }
}
