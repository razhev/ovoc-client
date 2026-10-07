import NetworkExtension
import OpenVPNAdapter

/// Мост между системным потоком пакетов (NEPacketTunnelFlow) и адаптером.
///
/// Раньше NEPacketTunnelFlow передавался адаптеру напрямую через пустой
/// retroactive-конформанс. Так же делала Amnezia в 4.8.10.0 — версии, у которой
/// на iOS 26 «подключается с переподключениями, трафик не идёт»
/// (amnezia-client#2072). В починенной 4.8.12.x они заменили это на отдельный
/// класс с явными ObjC-селекторами — повторяем их рабочую схему.
///
/// Заодно мост — единственное место, где видно пакеты: он считает их и пишет
/// размеры первых пачек после подключения. Первое боевое подключение рвалось
/// ровно тогда, когда начинали идти данные; без этих чисел причину не найти.
final class PacketFlowBridge: NSObject, OpenVPNAdapterPacketFlow {

    private let flow: NEPacketTunnelFlow
    private let logger: RingLogger

    /// IPv4 VPN-сервера (4 байта). Пакет с таким адресом назначения внутри туннеля —
    /// это петля маршрутов: собственное соединение Cloak завернулось в наш же туннель.
    var serverAddress: [UInt8]?
    private var loopedPackets = 0
    /// IPv6-пакеты, отброшенные мостом: провайдер заводит их в туннель
    /// маршрутом-«раковиной» (см. configureTunnel), чтобы они не ушли мимо VPN;
    /// включается только когда сервер не выдал IPv6-настройки.
    private var sunkIPv6Packets = 0
    private var ipv6SinkEnabled = true

    private let lock = NSLock()
    private var outbound = Counter()
    private var inbound = Counter()
    /// Сколько пачек ещё расписать подробно (на одно подключение), чтобы
    /// цикл переподключений не забил кольцевой лог.
    private var detailedBatchesLeft = 0

    private struct Counter {
        var packets = 0
        var bytes = 0
        var maxSize = 0
    }

    init(flow: NEPacketTunnelFlow, logger: RingLogger) {
        self.flow = flow
        self.logger = logger
    }

    /// Вызывается после успешного применения сетевых настроек, перед запуском
    /// чтения адаптера; чтение пакетов может приходить с другого потока.
    func setIPv6SinkEnabled(_ enabled: Bool) {
        lock.lock()
        ipv6SinkEnabled = enabled
        lock.unlock()
    }

    /// Новое подключение: счётчики с нуля, первые пачки — подробно.
    func reset() {
        lock.lock()
        outbound = Counter()
        inbound = Counter()
        loopedPackets = 0
        sunkIPv6Packets = 0
        detailedBatchesLeft = 24
        lock.unlock()
    }

    /// Итог по пакетам — в лог при ошибке и обрыве.
    func summary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return "tun→vpn \(outbound.packets) pkt / \(outbound.bytes) B (max \(outbound.maxSize)), "
             + "vpn→tun \(inbound.packets) pkt / \(inbound.bytes) B (max \(inbound.maxSize)), "
             + "to-server-inside-tunnel \(loopedPackets), ipv6-sunk \(sunkIPv6Packets)"
    }

    // MARK: - OpenVPNAdapterPacketFlow

    @objc(readPacketsWithCompletionHandler:)
    func readPackets(completionHandler: @escaping ([Data], [NSNumber]) -> Void) {
        flow.readPackets { [weak self] packets, protocols in
            guard let self else {
                completionHandler(packets, protocols)
                return
            }
            let (kept, keptProtocols) = self.dropIPv6(packets, protocols)
            self.note(kept, direction: "tun→vpn", isOutbound: true)
            completionHandler(kept, keptProtocols)
        }
    }

    /// В режиме раковины AF_INET6 отбрасывается; с IPv6 сервера идёт в адаптер.
    /// Обычная пачка целиком IPv4 — возвращаем как есть, без копирования.
    private func dropIPv6(_ packets: [Data], _ protocols: [NSNumber]) -> ([Data], [NSNumber]) {
        lock.lock()
        let sinkEnabled = ipv6SinkEnabled
        lock.unlock()
        let filtered = IPv6PacketFilter.filter(packets, protocols: protocols, sinkEnabled: sinkEnabled)
        let dropped = filtered.dropped

        lock.lock()
        let firstSunk = sunkIPv6Packets == 0
        sunkIPv6Packets += dropped
        lock.unlock()
        if firstSunk, dropped > 0 {
            // Одна строка на подключение: раковина работает, IPv6 не утёк.
            logger.log("ipv6 sink: first IPv6 packet entered the tunnel and was dropped (n=\(dropped))")
        }
        return (filtered.packets, filtered.protocols)
    }

    @objc(writePackets:withProtocols:)
    func writePackets(_ packets: [Data], withProtocols protocols: [NSNumber]) -> Bool {
        note(packets, direction: "vpn→tun", isOutbound: false)
        return flow.writePackets(packets, withProtocols: protocols)
    }

    // MARK: - Учёт

    private func note(_ packets: [Data], direction: String, isOutbound: Bool) {
        guard !packets.isEmpty else { return }
        let sizes = packets.map(\.count)

        // Петля: исходящий IPv4-пакет, адресованный самому VPN-серверу (байты 16–19 заголовка).
        var looped = 0
        if isOutbound, let server = serverAddress {
            for packet in packets where packet.count >= 20 && packet[packet.startIndex] >> 4 == 4 {
                let start = packet.startIndex + 16
                if Array(packet[start..<start + 4]) == server { looped += 1 }
            }
        }

        lock.lock()
        loopedPackets += looped
        let firstLoop = looped > 0 && loopedPackets == looped
        var counter = isOutbound ? outbound : inbound
        counter.packets += sizes.count
        counter.bytes += sizes.reduce(0, +)
        let previousMax = counter.maxSize
        counter.maxSize = max(previousMax, sizes.max() ?? 0)
        if isOutbound { outbound = counter } else { inbound = counter }

        let detailed = detailedBatchesLeft > 0
        if detailed { detailedBatchesLeft -= 1 }
        lock.unlock()

        if firstLoop {
            logger.log("ROUTING LOOP: packets to the VPN server are entering the tunnel (n=\(looped), "
                       + "sizes=\(sizes.map(String.init).joined(separator: ",")))")
        }
        if detailed {
            logger.log("pkt \(direction) n=\(sizes.count) sizes=\(sizes.prefix(12).map(String.init).joined(separator: ","))")
        } else if counter.maxSize > previousMax, counter.maxSize > 1400 {
            // Новый рекорд размера — возможная причина обрыва на стороне сервера.
            logger.log("pkt \(direction) new max size=\(counter.maxSize)")
        }
    }
}
