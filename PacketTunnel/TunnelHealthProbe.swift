import Network
import NetworkExtension

/// All methods and completion run on the provider's stateQueue. A fresh UDP
/// connection is forced through the VPN interface; no default-route HTTP probe.
final class TunnelHealthProbe {
    private weak var provider: NEPacketTunnelProvider?
    private let queue: DispatchQueue
    private var connection: Network.NWConnection?
    private var legacySession: NWUDPSession?
    private var observation: NSKeyValueObservation?
    private var timeout: DispatchWorkItem?
    private var completion: ((Bool) -> Void)?
    private var servers: [String] = []
    private var generation = 0
    private var sent = false

    init(provider: NEPacketTunnelProvider, queue: DispatchQueue) {
        self.provider = provider
        self.queue = queue
    }

    func start(servers: [String], completion: @escaping (Bool) -> Void) {
        cancel()
        self.servers = Array(NSOrderedSet(array: servers).array.compactMap { $0 as? String }.prefix(2))
        self.completion = completion
        nextServer()
    }

    func cancel() {
        completion = nil
        servers = []
        closeConnection()
    }

    private func closeConnection() {
        generation += 1
        timeout?.cancel()
        timeout = nil
        // The state handler captures this connection for send/receive. Break
        // that cycle on every success, timeout and cancellation.
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        observation = nil
        legacySession?.cancel()
        legacySession = nil
        sent = false
    }

    private func finish(_ success: Bool) {
        let callback = completion
        cancel()
        callback?(success)
    }

    private func nextServer() {
        closeConnection()
        guard !servers.isEmpty, let provider else { finish(false); return }
        let server = servers.removeFirst()
        let generation = generation
        let query = TunnelDNSQuery(id: UInt16.random(in: .min ... .max))
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            self.nextServer()
        }
        timeout = deadline
        queue.asyncAfter(deadline: .now() + 4, execute: deadline)

        if #available(iOS 18.0, macOS 15.0, *) {
            guard let interface = provider.virtualInterface else { finish(false); return }
            let parameters = NWParameters.udp
            parameters.requiredInterface = interface
            let connection = Network.NWConnection(host: Network.NWEndpoint.Host(server), port: 53, using: parameters)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == generation else { return }
                if case .failed = state { self.nextServer(); return }
                guard case .ready = state, !self.sent else { return }
                self.sent = true
                connection.send(content: query.data, completion: .contentProcessed { [weak self] error in
                    guard let self, self.generation == generation else { return }
                    if error != nil { self.nextServer() }
                })
                connection.receiveMessage { [weak self] data, _, _, error in
                    guard let self, self.generation == generation else { return }
                    if let data, query.accepts(data) { self.finish(true) }
                    else if error != nil { self.nextServer() }
                    // A malformed/unrelated reply is not success; let the deadline expire.
                }
            }
            connection.start(queue: queue)
        } else {
            let session = provider.createUDPSessionThroughTunnel(
                to: NWHostEndpoint(hostname: server, port: "53"), from: nil)
            legacySession = session
            session.setReadHandler({ [weak self] datagrams, error in
                self?.queue.async { [weak self] in
                    guard let self, self.generation == generation else { return }
                    if datagrams?.contains(where: query.accepts) == true { self.finish(true) }
                    else if error != nil { self.nextServer() }
                }
            }, maxDatagrams: 1)
            observation = session.observe(\.state, options: [.initial, .new]) { [weak self] session, _ in
                self?.queue.async { [weak self] in
                    guard let self, self.generation == generation else { return }
                    if session.state == .failed { self.nextServer(); return }
                    guard session.state == .ready, !self.sent else { return }
                    self.sent = true
                    session.writeDatagram(query.data) { [weak self] error in
                        self?.queue.async { [weak self] in
                            guard let self, self.generation == generation else { return }
                            if error != nil { self.nextServer() }
                        }
                    }
                }
            }
        }
    }
}
