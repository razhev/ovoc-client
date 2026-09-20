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

    /// Новое подключение: счётчики с нуля, первые пачки — подробно.
    func reset() {
        lock.lock()
        outbound = Counter()
        inbound = Counter()
        detailedBatchesLeft = 24
        lock.unlock()
    }

    /// Итог по пакетам — в лог при ошибке и обрыве.
    func summary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return "tun→vpn \(outbound.packets) pkt / \(outbound.bytes) B (max \(outbound.maxSize)), "
             + "vpn→tun \(inbound.packets) pkt / \(inbound.bytes) B (max \(inbound.maxSize))"
    }

    // MARK: - OpenVPNAdapterPacketFlow

    @objc(readPacketsWithCompletionHandler:)
    func readPackets(completionHandler: @escaping ([Data], [NSNumber]) -> Void) {
        flow.readPackets { [weak self] packets, protocols in
            self?.note(packets, direction: "tun→vpn", isOutbound: true)
            completionHandler(packets, protocols)
        }
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

        lock.lock()
        var counter = isOutbound ? outbound : inbound
        counter.packets += sizes.count
        counter.bytes += sizes.reduce(0, +)
        let previousMax = counter.maxSize
        counter.maxSize = max(previousMax, sizes.max() ?? 0)
        if isOutbound { outbound = counter } else { inbound = counter }

        let detailed = detailedBatchesLeft > 0
        if detailed { detailedBatchesLeft -= 1 }
        lock.unlock()

        if detailed {
            logger.log("pkt \(direction) n=\(sizes.count) sizes=\(sizes.prefix(12).map(String.init).joined(separator: ","))")
        } else if counter.maxSize > previousMax, counter.maxSize > 1400 {
            // Новый рекорд размера — возможная причина обрыва на стороне сервера.
            logger.log("pkt \(direction) new max size=\(counter.maxSize)")
        }
    }
}
