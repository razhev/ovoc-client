import NetworkExtension

/// Ядро VPN. Пока — «пустышка» для M1: поднимает фиктивный интерфейс
/// с УЗКИМ маршрутом, чтобы проверить подписи/entitlements/App Group
/// до появления настоящей VPN-логики.
///
/// Пустышке НИКОГДА не отдаём default route: мёртвый туннель, забравший
/// весь трафик, оставит телефон без интернета.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let logger = RingLogger.shared

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.log("startTunnel: dummy mode")
        logger.startMemoryHeartbeat()

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.8.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "10.8.0.0", subnetMask: "255.255.255.0")]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.logger.log("setTunnelNetworkSettings failed: \(error.localizedDescription)")
            } else {
                self?.logger.log("dummy tunnel is up (route 10.8.0.0/24 only)")
            }
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.log("stopTunnel: reason=\(reason.rawValue)")
        completionHandler()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
    }
}
