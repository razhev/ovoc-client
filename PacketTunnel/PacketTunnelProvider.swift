import Network
import NetworkExtension
import OpenVPNAdapter

/// Ядро VPN. Два режима:
/// - «пустышка» (в providerConfiguration нет ключа ovpnConfig) — для M1:
///   фиктивный интерфейс с УЗКИМ маршрутом, проверяет подписи/App Group;
/// - боевой: OpenVPN over Cloak через OpenVPNAdapter.
///
/// Сигнатуры фреймворка зафиксированы в docs/FRAMEWORK-API.md — код написан
/// строго по ним, не по упоминаниям в блогах (форк Amnezia менял API).
///
/// Потоки. Система, делегат адаптера (его собственный поток) и сторожевые
/// таймеры приходят с разных потоков, а completion'ы системы можно вызвать
/// ровно один раз — двойной вызов убивает расширение. Поэтому ВСЁ изменяемое
/// состояние живёт на stateQueue, и заходят на неё только через async:
/// поток адаптера в это время ждёт наш completion, sync дал бы взаимоблокировку.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private static let errorDomain = "com.razhev.ovocclient.tunnel"

    private let logger = RingLogger.shared
    private let stateQueue = DispatchQueue(label: "com.razhev.ovocclient.tunnel.state")

    private lazy var adapter: OpenVPNAdapter = {
        let adapter = OpenVPNAdapter()
        adapter.delegate = self
        return adapter
    }()

    /// Поток пакетов адаптер получает через мост (см. PacketFlowBridge), а не
    /// напрямую: так сделано в починенной версии клиента Amnezia, и только
    /// в мосте видно размеры пакетов.
    private lazy var packetBridge = PacketFlowBridge(flow: packetFlow, logger: logger)

    // ── Состояние: читать и менять только на stateQueue ──

    private enum Phase { case idle, starting, connected, stopping, stopped }
    private var phase: Phase = .idle

    private var startCompletion: ((Error?) -> Void)?
    private var stopCompletion: (() -> Void)?

    /// Сторожевой таймер старта: рукопожатие Cloak многосекундное, а через
    /// ~60 сек (недокументировано) система молча убивает расширение.
    /// 30 сек — понятная ошибка вместо тихой смерти.
    private var startWatchdog: DispatchSourceTimer?
    /// Страховка стопа: если адаптер не отдал .disconnected за 5 сек —
    /// завершаем стоп сами.
    private var stopWatchdog: DispatchSourceTimer?

    /// Последняя ошибка адаптера — объясняет следующий за ней обрыв.
    private var lastAdapterError: Error?
    /// Наш собственный отказ поднять туннель (см. configureTunnel): его текст
    /// важнее общей ошибки адаптера «TUN setup failed», которая придёт следом.
    private var refusalReason: String?

    private var serverIP: String?
    private var fallbackDNS: [String] = []
    private var ovpnText = ""
    /// Immutable for a session, including adapter reconnects.
    private var serviceBypassNetworks: [IPNetwork] = []

    /// Сколько раз ядро переподключалось за эту сессию (событие .reconnecting).
    private var reconnectCount = 0
    /// Момент ухода в сон — чтобы на wake написать, сколько спали.
    private var sleptAt: Date?

    private var recovery = ReconnectCoordinator()
    private var pathMonitor: NWPathMonitor?
    private var recoveryTimer: DispatchSourceTimer?
    private var activityTimer: DispatchSourceTimer?
    private var adapterConfiguration: OpenVPNConfiguration?
    // The framework keeps packetFlow weakly; retain the endpoint for this adapter.
    private var adapterFlow: OpenVPNAdapterPacketFlow?
    private var adapterHasDisconnected = false
    private var probeDNS: [String] = []
    private var recoveryStartedAt: TimeInterval?
    private var lastProbeAt: TimeInterval = -.infinity
    private lazy var healthProbe = TunnelHealthProbe(provider: self, queue: stateQueue) { [weak self] message in
        self?.logger.log("health transport: \(message)")
    }

    /// Адрес-«раковина» для IPv6 (см. configureTunnel). ULA-префикс fd00::/8,
    /// 6f76:6f63 — «ovoc»; в реальной сети такого адреса нет.
    private static let ipv6SinkAddress = "fd00:6f76:6f63::2"

    // MARK: - Старт

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.log("startTunnel: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        logger.startMemoryHeartbeat()

        let providerConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        guard let ovpn = providerConfig?[TunnelConfigKeys.ovpnConfig] as? String, !ovpn.isEmpty else {
            startDummyTunnel(completionHandler: completionHandler)
            return
        }

        stateQueue.async {
            self.startRealTunnel(ovpn: ovpn, providerConfig: providerConfig, completionHandler: completionHandler)
        }
    }

    /// Только на stateQueue.
    private func startRealTunnel(
        ovpn: String,
        providerConfig: [String: Any]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        ovpnText = ovpn
        serverIP = providerConfig?[TunnelConfigKeys.serverIP] as? String
        fallbackDNS = [
            providerConfig?[TunnelConfigKeys.dns1] as? String,
            providerConfig?[TunnelConfigKeys.dns2] as? String,
        ].compactMap { $0 }

        do {
            let policy = try ServiceBypassPolicy(configuration: providerConfig)
            serviceBypassNetworks = []
            if !policy.services.isEmpty {
                let catalog = try ServiceBypassCatalog.load(bundle: .main)
                serviceBypassNetworks = try catalog.networks(for: policy)
                logger.log("service bypass: catalog=\(catalog.catalogVersion) services=\(policy.services.map(\.rawValue).sorted().joined(separator: ",")) routes=\(serviceBypassNetworks.count)")
            }
        } catch {
            let failure = (error as? ServiceBypassError) ?? .invalidCatalog
            writeLastError(failure.localizedDescription)
            logger.log("service bypass REFUSED: \(failure.rawValue)")
            completionHandler(failure)
            return
        }

        logger.log("real tunnel: serverIP=\(serverIP ?? "nil") profile=\(ovpn.utf8.count) bytes")

        // Без IPv4-литерала сервера нельзя поставить маршрут-исключение — а без
        // него трафик к серверу завернётся в сам туннель (петля). Не стартуем.
        guard let serverIP, Self.isIPv4Literal(serverIP) else {
            let message = "В профиле нет IPv4-адреса сервера — импортируйте ключ заново"
            logger.log("start REFUSED: \(message)")
            writeLastError(message)
            completionHandler(Self.makeError(2, message))
            return
        }

        let configuration = OpenVPNConfiguration()
        adapterConfiguration = configuration
        configuration.fileContent = ovpn.data(using: .utf8)
        // tunPersist НЕ включаем: адаптер должен пересоздать свои сокеты и
        // получить свежий PUSH_REPLY. Системные маршруты и DNS сохраняются
        // независимо от этого: TunnelNetworkSettingsUpdate не передаёт resetTun
        // в setTunnelNetworkSettings(nil). Пока Cloak восстанавливается, трафик
        // ждёт в туннеле; пользователь может отключить VPN обычной кнопкой.
        //
        // Проверено и отброшено: compressionMode / peerInfo из более позднего
        // рецепта Amnezia (PR #2360). В этой сборке ядра пользовательский
        // peer-info уходит серверу только при директиве push-peer-info в профиле,
        // а заглушки сжатия объявляются только при compress/comp-lzo — у нас нет
        // ни того, ни другого, в Peer Info ничего не менялось.

        // Включает Cloak-транспорт; сам конфиг Cloak фреймворк читает
        // из блока <cloak> внутри fileContent (метод аргументов не имеет).
        // Только при наличии блока — как в клиенте Amnezia: профиль без <cloak>
        // (диагностический, make push-key KEY=….ovpn) идёт обычным OpenVPN по TCP.
        let usesCloak = ovpn.contains("<cloak>")
        if usesCloak {
            configuration.setPTCloak()
        }
        logger.log("transport: \(usesCloak ? "Cloak (pluggable transport)" : "plain OpenVPN, no Cloak")")

        do {
            let evaluation = try adapter.apply(configuration: configuration)
            logger.log("apply OK: remote=\(evaluation.remoteHost ?? "?"):\(evaluation.remotePort) "
                       + "autologin=\(evaluation.autologin) externalPki=\(evaluation.externalPki) "
                       + "keyPassword=\(evaluation.isPrivateKeyPasswordRequired)")
            // Логин/пароль не поддерживаем: без этой проверки такой профиль
            // выглядел бы как 30-секундный таймаут без объяснений.
            if !evaluation.autologin, ovpn.contains("auth-user-pass") {
                let message = "Профиль требует логин и пароль (auth-user-pass) — такие ключи не поддерживаются"
                logger.log("start REFUSED: \(message)")
                writeLastError(message)
                completionHandler(Self.makeError(5, message))
                return
            }
        } catch {
            // Ошибки разбора конфига — самый вероятный класс багов; лог дословный.
            logger.log("apply FAILED: \(describe(error))")
            writeLastError("Ошибка конфигурации: \(describe(error))")
            completionHandler(error)
            return
        }
        logger.logMemory("after apply")

        phase = .starting
        startCompletion = completionHandler
        reconnectCount = 0
        armStartWatchdog()
        packetBridge.serverAddress = serverIP.split(separator: ".").compactMap { UInt8($0) }
        packetBridge.reset()
        logger.heartbeatExtra = { [weak self] in self?.packetBridge.summary() ?? "" }
        startRecoveryTracking()
        adapterHasDisconnected = false
        let flow = packetBridge.makeAdapterFlow()
        adapterFlow = flow
        adapter.connect(using: flow)
    }

    /// Tracking and every recovery effect run on stateQueue, including deadlines.
    private func startRecoveryTracking() {
        recovery.start()
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            guard let self, let monitor, self.pathMonitor === monitor else { return }
            let snapshot = NetworkPathSnapshot(path)
            self.logger.log("network path: available=\(snapshot.isAvailable) interface=\(snapshot.interface) addresses=\(snapshot.addresses.count)")
            self.perform(self.recovery.pathChanged(snapshot))
        }
        monitor.start(queue: stateQueue)

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, self.phase == .connected else { return }
            let activity = self.packetBridge.trafficActivity()
            if (self.recovery.state == .verifying || self.recovery.state == .probeBackoff || self.recovery.state == .unverified), activity.receivedInbound(since: self.lastProbeAt) {
                self.logger.log("health: incoming tunnel traffic confirms data path")
                self.perform(self.recovery.probeFinished(ticket: self.recovery.ticket, success: true))
                return
            }
            guard self.recovery.state == .online,
                  activity.needsProbe(at: ProcessInfo.processInfo.systemUptime) else { return }
            self.logger.log("health: outbound traffic without replies for 15s; checking tunnel")
            self.perform(self.recovery.checkHealth())
        }
        timer.resume()
        activityTimer = timer
    }

    private func perform(_ effects: [ReconnectCoordinator.Effect]) {
        if !effects.isEmpty {
            logger.log("recovery: state=\(recovery.state.rawValue) attempt=\(recovery.attempts) ticket=\(recovery.ticket)")
        }
        for effect in effects {
            switch effect {
            case .reassert(let value):
                reasserting = value
                if value, recoveryStartedAt == nil { recoveryStartedAt = ProcessInfo.processInfo.systemUptime }
            case .cancelTimer:
                recoveryTimer?.cancel()
                recoveryTimer = nil
            case .cancelProbe:
                healthProbe.cancel()
            case .schedule(let ticket, let delay):
                let timer = DispatchSource.makeTimerSource(queue: stateQueue)
                timer.schedule(deadline: .now() + delay)
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    self.perform(self.recovery.timerFired(ticket: ticket))
                }
                recoveryTimer = timer
                timer.resume()
            case .reconnect(let attempt):
                logger.log("recovery attempt \(attempt): requesting OpenVPN reconnect")
                adapter.reconnect(afterTimeInterval: 0)
            case .stopAdapter:
                logger.log("recovery: stopping adapter before replacement (deadline 5s)")
                adapter.disconnect()
            case .replaceAdapter(let attempt):
                guard let configuration = adapterConfiguration else { failTunnel("Потеряна конфигурация VPN"); return }
                // DISCONNECTED is required before this effect. Old callbacks are
                // rejected by adapter identity, including delayed settings/errors.
                adapter.delegate = nil
                let replacement = OpenVPNAdapter()
                replacement.delegate = self
                adapter = replacement
                adapterHasDisconnected = false
                do {
                    _ = try adapter.apply(configuration: configuration)
                    packetBridge.reset()
                    logger.log("recovery attempt \(attempt): connecting new adapter")
                    let flow = packetBridge.makeAdapterFlow()
                    adapterFlow = flow
                    adapter.connect(using: flow)
                } catch {
                    failTunnel("Не удалось пересоздать VPN: \(describe(error))")
                    return
                }
            case .activateTunnel:
                if phase == .starting {
                    logger.log("adapter and network settings ready; completing system tunnel start")
                    finishStart(nil)
                }
            case .probe(let ticket):
                lastProbeAt = ProcessInfo.processInfo.systemUptime
                let startedAt = lastProbeAt
                guard !probeDNS.isEmpty else {
                    logger.log("health: no eligible DNS targets; monitoring path, adapter and incoming traffic")
                    perform(recovery.probeUnavailable(ticket: ticket))
                    continue
                }
                logger.log("health: checking data path through tunnel (ticket=\(ticket))")
                healthProbe.start(servers: probeDNS) { [weak self] probeResult in
                    guard let self else { return }
                    let receivedTraffic = self.packetBridge.trafficActivity().receivedInbound(since: startedAt)
                    let result: TunnelProbeResult = receivedTraffic ? .success : probeResult
                    self.logger.log("health: \(result == .success ? "round trip OK" : (result == .noReply ? "no reply" : "inconclusive")) (ticket=\(ticket))")
                    self.perform(self.recovery.probeFinished(ticket: ticket, result: result))
                }
            case .ready:
                lastAdapterError = nil
                if let url = SharedPaths.lastErrorURL { try? FileManager.default.removeItem(at: url) }
                let elapsed = recoveryStartedAt.map { Int(ProcessInfo.processInfo.systemUptime - $0) } ?? 0
                recoveryStartedAt = nil
                logger.logMemory("tunnel verified, recovery=\(elapsed)s")
            case .fail(let message):
                failTunnel(message)
                return
            }
        }
    }

    private func failTunnel(_ message: String) {
        logger.log("tunnel failed: \(message)")
        writeLastError(message)
        let error = Self.makeError(8, message)
        stopRecoveryTracking()
        adapter.disconnect()
        if phase == .starting { finishStart(error) }
        else if phase == .connected {
            phase = .stopped
            cancelTunnelWithError(error)
        }
    }

    private func startDummyTunnel(completionHandler: @escaping (Error?) -> Void) {
        logger.log("dummy mode: no ovpnConfig in providerConfiguration")

        // M1 проверяет именно App Group. Без контейнера файловый лог молча не
        // пишется, поэтому падаем громко: приложение покажет причину под кнопкой
        // (она доходит через fetchLastDisconnectError).
        guard SharedPaths.containerURL != nil else {
            completionHandler(Self.makeError(3,
                "App Group \(SharedPaths.appGroupID) недоступна расширению — проверьте "
                + "entitlements PacketTunnel и App Groups у App ID на портале"))
            return
        }

        // M2: фреймворк реально загрузился и инициализировался в процессе
        // расширения на устройстве (ошибки встраивания/подписи вылезают здесь,
        // а не в M3). Строка памяти — базовый расход Go+OpenVPN3 при лимите ~50 МБ.
        let frameworkBundle = Bundle(for: OpenVPNAdapter.self)
        let version = frameworkBundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        logger.log("OpenVPNAdapter loaded: \(type(of: adapter)) v\(version) from \(frameworkBundle.bundlePath)")
        logger.logMemory("after framework init")

        // Пустышке НИКОГДА не отдаём default route: мёртвый туннель,
        // забравший весь трафик, оставит телефон без интернета.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.8.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "10.8.0.0", subnetMask: "255.255.255.0")]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.logger.log("dummy setTunnelNetworkSettings failed: \(error.localizedDescription)")
            } else {
                self?.logger.log("dummy tunnel is up (route 10.8.0.0/24 only)")
            }
            completionHandler(error)
        }
    }

    // MARK: - Стоп

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.log("stopTunnel: reason=\(Self.stopReasonName(reason))")
        stateQueue.async {
            let adapterRunning = self.phase == .starting || self.phase == .connected
            if self.phase == .starting {
                // Система отменила ещё не завершённый старт — закрываем его.
                self.finishStart(Self.makeError(6, "Подключение отменено"))
            }
            guard adapterRunning else {
                // Пустышка либо адаптер уже остановлен.
                completionHandler()
                return
            }

            self.phase = .stopping
            self.stopCompletion = completionHandler
            self.stopRecoveryTracking()

            let watchdog = DispatchSource.makeTimerSource(queue: self.stateQueue)
            watchdog.schedule(deadline: .now() + 5)
            watchdog.setEventHandler { [weak self] in
                self?.logger.log("stop watchdog fired: adapter didn't report .disconnected in 5s")
                self?.finishStop()
            }
            watchdog.resume()
            self.stopWatchdog = watchdog

            self.adapter.disconnect()
        }
    }

    // MARK: - Одноразовые завершения (только на stateQueue)

    /// Второй и последующие вызовы игнорируются: completion системы вызывается один раз.
    private func finishStart(_ error: Error?) {
        guard let completion = startCompletion else { return }
        startCompletion = nil
        startWatchdog?.cancel()
        startWatchdog = nil
        phase = error == nil ? .connected : .stopped
        if error != nil { stopRecoveryTracking() }
        completion(error)
    }

    private func finishStop() {
        guard let completion = stopCompletion else { return }
        stopCompletion = nil
        stopWatchdog?.cancel()
        stopWatchdog = nil
        phase = .stopped
        stopRecoveryTracking()
        completion()
    }

    /// Только на stateQueue.
    private func stopRecoveryTracking() {
        perform(recovery.stop())
        packetBridge.invalidateAdapterFlow()
        pathMonitor?.cancel()
        pathMonitor = nil
        activityTimer?.cancel()
        activityTimer = nil
    }

    // MARK: - Sleep/wake

    /// Почему не pause()/resume() адаптера. pause у ядра — это остановка
    /// сессии с разборкой его tun (interim_finalize → tun_builder_teardown),
    /// resume — полное рукопожатие Cloak заново. Наши системные маршруты при
    /// resetTun сохраняются, но фоновый трафик всё равно ждал бы восстановления.
    /// А iOS дёргает sleep/wake очень часто — в логах бывали пары через 2–3 сек.
    /// После wake проверяем путь; если давно не было входящих пакетов — делаем
    /// пробу через туннель. Короткие частые sleep/wake не должны порождать запрос
    /// каждые 2–3 секунды и держать радио включённым.
    override func sleep(completionHandler: @escaping () -> Void) {
        logger.log("sleep")
        stateQueue.async { self.sleptAt = Date() }
        completionHandler()
    }

    override func wake() {
        stateQueue.async {
            let slept = self.sleptAt.map { Int(Date().timeIntervalSince($0)) }
            self.sleptAt = nil
            self.logger.log("wake" + (slept.map { " after \($0)s" } ?? ""))
            if let monitor = self.pathMonitor {
                self.perform(self.recovery.pathChanged(NetworkPathSnapshot(monitor.currentPath)))
            }
            let now = ProcessInfo.processInfo.systemUptime
            let lastInbound = self.packetBridge.trafficActivity().lastInbound ?? -.infinity
            if now - lastInbound >= 30, now - self.lastProbeAt >= 30 {
                self.perform(self.recovery.checkHealth())
            }
        }
    }

    // MARK: - Вспомогательное

    /// Только на stateQueue.
    private func armStartWatchdog() {
        let watchdog = DispatchSource.makeTimerSource(queue: stateQueue)
        watchdog.schedule(deadline: .now() + 30)
        watchdog.setEventHandler { [weak self] in
            guard let self, self.phase == .starting else { return }
            self.logger.log("start watchdog fired: tunnel not ready for activation in 30s")
            let message = self.refusalReason
                ?? "Не удалось подключиться за 30 секунд — сервер недоступен или конфигурация неверна"
            self.writeLastError(message)
            self.finishStart(Self.makeError(1, message))
            self.adapter.disconnect()
        }
        watchdog.resume()
        startWatchdog = watchdog
    }

    /// dhcp-option DNS x.x.x.x из текста конфига — второй уровень DNS-fallback.
    private func dnsFromProfile() -> [String] {
        ovpnText.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, parts[0] == "dhcp-option", parts[1] == "DNS" else { return nil }
            return String(parts[2])
        }
    }

    /// По rawValue, а не switch по кейсам: internalError появился только в
    /// iOS 18.1, а deployment target — 16.0.
    private static func stopReasonName(_ reason: NEProviderStopReason) -> String {
        let names = [
            0: "none", 1: "userInitiated", 2: "providerFailed", 3: "noNetworkAvailable",
            4: "unrecoverableNetworkChange", 5: "providerDisabled", 6: "authenticationCanceled",
            7: "configurationFailed", 8: "idleTimeout", 9: "configurationDisabled",
            10: "configurationRemoved", 11: "superceded", 12: "userLogout", 13: "userSwitch",
            14: "connectionFailed", 15: "sleep", 16: "appUpdate", 17: "internalError",
        ]
        return names[reason.rawValue].map { "\($0)(\(reason.rawValue))" } ?? "#\(reason.rawValue)"
    }

    private static func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: errorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func isIPv4Literal(_ string: String) -> Bool {
        var address = in_addr()
        return string.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private static func isIPLiteral(_ string: String) -> Bool {
        if isIPv4Literal(string) { return true }
        var address = in6_addr()
        return string.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    private func writeLastError(_ text: String) {
        guard let url = SharedPaths.lastErrorURL else { return }
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Домен, код, описание и сообщение ядра OpenVPN. От вложенной ошибки
    /// (NSUnderlyingErrorKey — то, что вернула система в setTunnelNetworkSettings)
    /// берём только домен и код: её текст нам ни о чём не говорит, а в файл
    /// должны попадать только наши строки.
    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let message = nsError.userInfo[OpenVPNAdapterErrorMessageKey] as? String
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        return "\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)"
            + (message.map { " | \($0)" } ?? "")
            + (underlying.map { " | underlying: \(Self.brief($0))" } ?? "")
    }

    /// Только домен и код.
    private static func brief(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}

// MARK: - OpenVPNAdapterDelegate

extension PacketTunnelProvider: OpenVPNAdapterDelegate {

    /// Здесь закрываем главный риск проекта — петлю маршрутов: CloakTransport
    /// игнорирует endpoint из строки remote, поэтому tunnelRemoteAddress будет
    /// 127.0.0.1 и автоисключение IP сервера у iOS НЕ сработает. Исключаем сами,
    /// а если исключить нельзя — туннель не поднимаем (fail-closed): «подключено,
    /// но трафика нет» хуже честной ошибки.
    func openVPNAdapter(
        _ openVPNAdapter: OpenVPNAdapter,
        configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        stateQueue.async {
            guard self.adapter === openVPNAdapter else {
                // Teardown still needs its completion to unblock the old core.
                completionHandler(networkSettings == nil ? nil : Self.makeError(6, "Подключение отменено"))
                return
            }
            if networkSettings == nil {
                self.packetBridge.resetReader()
                self.logger.log("configureTunnel: adapter reset acknowledged; system routes and DNS retained (phase=\(self.phase))")
            }
            TunnelNetworkSettingsUpdate.apply(
                networkSettings,
                using: self.configureTunnel,
                completionHandler: completionHandler
            )
        }
    }

    /// Только на stateQueue.
    private func configureTunnel(
        _ adapterSettings: NEPacketTunnelNetworkSettings,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Запоздавший PUSH_REPLY после stop/watchdog не должен снова ставить
        // маршруты. nil/resetTun при этом по-прежнему получает успех выше.
        guard phase == .starting || phase == .connected else {
            completionHandler(Self.makeError(6, "Подключение отменено"))
            return
        }

        func refuse(_ message: String) {
            logger.log("configureTunnel REFUSED: \(message)")
            refusalReason = message
            writeLastError(message)
            completionHandler(Self.makeError(4, message))
        }

        // Never give our synthetic IPv6 settings back to the adapter's baseline:
        // a reused callback object must not be mistaken for server IPv6 on reconnect.
        let settings: NEPacketTunnelNetworkSettings
        do { settings = try ServiceBypassRoutes.copyOf(adapterSettings) }
        catch { refuse(ServiceBypassError.missingNetworkSettings.localizedDescription); return }

        // ── DNS: весь — в туннель (иначе часть запросов уйдёт мимо VPN) ──
        let adapterDNS = (settings.dnsSettings?.servers ?? []).filter(Self.isIPLiteral)
        if adapterDNS.isEmpty {
            let fromProfile = dnsFromProfile().filter(Self.isIPLiteral)
            let fallback = fromProfile.isEmpty ? fallbackDNS.filter(Self.isIPLiteral) : fromProfile
            logger.log("adapter gave no DNS, fallback: \(fallback.joined(separator: ","))")
            // matchDomains = [""] забирает ВСЕ запросы: с пустым списком серверов
            // это «подключено, но ничего не резолвится».
            guard !fallback.isEmpty else {
                refuse("Нет ни одного DNS-сервера: ни от сервера, ни в профиле, ни в ключе")
                return
            }
            settings.dnsSettings = NEDNSSettings(servers: fallback)
        }
        settings.dnsSettings?.matchDomains = [""]

        // ── Вторая половина защиты от петли (первая — route … net_gateway в профиле) ──
        guard let serverIP, Self.isIPv4Literal(serverIP) else {
            refuse("Неизвестен IPv4-адрес сервера — нельзя исключить его из туннеля")
            return
        }
        guard let ipv4 = settings.ipv4Settings else {
            refuse("Адаптер не выдал IPv4-настройки — нельзя исключить адрес сервера из туннеля")
            return
        }
        var excludedRoutes = ipv4.excludedRoutes ?? []
        let alreadyExcluded = excludedRoutes.contains {
            $0.destinationAddress == serverIP && $0.destinationSubnetMask == "255.255.255.255"
        }
        if !alreadyExcluded {
            excludedRoutes.append(NEIPv4Route(destinationAddress: serverIP, subnetMask: "255.255.255.255"))
        }
        ipv4.excludedRoutes = excludedRoutes
        // Свойство объявлено copy — присваиваем обратно явно, не полагаясь на то,
        // что геттер вернул тот же объект.
        settings.ipv4Settings = ipv4

        // ── IPv6: в туннель и в раковину (утечка мимо VPN) ──
        // Адаптер выставляет ipv6Settings только при ifconfig-ipv6 от сервера,
        // а его tun_builder_set_block_ipv6 — пустышка. Наш сервер даёт лишь IPv4,
        // и без IPv6-настроек iOS оставляет IPv6-маршруты физической сети:
        // всё, что резолвится в AAAA (у оператора и домашнего Wi-Fi IPv6 есть),
        // уходит мимо туннеля с настоящим адресом телефона.
        //
        // Приём общепринятый (так делают OpenVPN Connect при block-ipv6 и
        // WireGuard-клиенты): выдать интерфейсу ULA-адрес, которого нет ни в
        // одной сети, и default-маршрут IPv6 в туннель. Пакеты IPv6 тогда попадают
        // в наш packetFlow, и мост их отбрасывает (PacketFlowBridge: серверу они
        // не нужны, он бы их и так уронил). Почему именно ULA: по RFC 6724
        // источник fd00::/8 «не того класса» для глобальных адресатов, и iOS
        // сама предпочитает IPv4 (Happy Eyeballs не ждёт таймаута IPv6).
        // IPv4 и DNS не задеты: DNS-серверы — IPv4-литералы, идут в туннель как
        // и раньше; link-local (fe80::/10) остаётся на своих интерфейсах.
        let ipv6Mode: String
        let sinkIPv6 = settings.ipv6Settings == nil
        if sinkIPv6 {
            let sink = NEIPv6Settings(addresses: [Self.ipv6SinkAddress], networkPrefixLengths: [64])
            sink.includedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = sink
            ipv6Mode = "sink(\(Self.ipv6SinkAddress)/64→tunnel)"
        } else {
            ipv6Mode = "server"
        }

        // MTU задаём явно: сервер его не присылает, а значение «по умолчанию»
        // у iOS не документировано. Сервер OpenVPN в TCP-режиме рвёт соединение
        // на первом же пакете длиннее своего предела («Bad encapsulated packet
        // length») — снаружи это выглядит ровно как наш обрыв сразу после
        // connected. 1400 — с запасом под tun-mtu 1500 на сервере.
        if settings.mtu == nil {
            settings.mtu = 1400
        }

        let routedSettings: NEPacketTunnelNetworkSettings
        do {
            routedSettings = try ServiceBypassRoutes.applying(serviceBypassNetworks, to: settings)
        } catch {
            refuse(((error as? ServiceBypassError) ?? .invalidCatalog).localizedDescription)
            return
        }
        let included = routedSettings.ipv4Settings?.includedRoutes?.count ?? 0
        let excluded = routedSettings.ipv4Settings?.excludedRoutes?.count ?? 0
        logger.log("configureTunnel: remote=\(settings.tunnelRemoteAddress) "
                   + "routes incl=\(included) excl=\(excluded) serverExcluded=\(alreadyExcluded ? "by-profile" : "added") "
                   + "ipv6=\(ipv6Mode) "
                   + "dns=\(settings.dnsSettings?.servers.joined(separator: ",") ?? "none") "
                   + "mtu=\(settings.mtu?.stringValue ?? "default")")

        let configuringAdapter = adapter
        setTunnelNetworkSettings(routedSettings) { [weak self] error in
            guard let self else { completionHandler(Self.makeError(6, "Подключение отменено")); return }
            self.stateQueue.async {
                guard self.adapter === configuringAdapter,
                      self.phase == .starting || self.phase == .connected else {
                    completionHandler(Self.makeError(6, "Подключение отменено"))
                    return
                }
                if let error {
                    self.logger.log("setTunnelNetworkSettings failed: \(error.localizedDescription)")
                } else {
                    self.packetBridge.setIPv6SinkEnabled(sinkIPv6)
                    self.probeDNS = (routedSettings.dnsSettings?.servers ?? []).filter {
                        $0 != self.serverIP && (!sinkIPv6 || Self.isIPv4Literal($0))
                    }
                    self.logger.log("network settings installed; probe DNS count=\(self.probeDNS.count)")
                }
                completionHandler(error)
            }
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleEvent event: OpenVPNAdapterEvent, message: String?) {
        // Пишем в лог на stateQueue, как и ошибки: порядок строк «error → event»
        // в файле тогда совпадает с порядком обработки.
        let line = "event: \(eventName(event))" + (message.map { " — \($0)" } ?? "")
        stateQueue.async {
            guard self.adapter === openVPNAdapter else { return }
            self.logger.log(line)
            self.handle(event)
        }
    }

    /// Только на stateQueue.
    private func handle(_ event: OpenVPNAdapterEvent) {
        guard phase == .starting || phase == .connected || phase == .stopping else { return }
        switch event {
        case .connected:
            guard phase != .stopping else { return }
            logger.logMemory("adapter connected; verifying traffic")
            perform(recovery.connected())

        case .disconnected:
            adapterHasDisconnected = true
            switch phase {
            case .starting, .connected:
                perform(recovery.disconnected())
            case .stopping:
                finishStop()
            case .idle, .stopped:
                break
            }

        case .reconnecting:
            // Ядро начало новую сессию (new_client): tun разберётся и соберётся
            // заново, настройки придут свежие из PUSH_REPLY. Пока идёт
            // рукопожатие, приложение показывает «Переподключение…».
            guard phase != .stopping else { return }
            reconnectCount += 1
            logger.log("reconnect #\(reconnectCount): \(packetBridge.summary())")
            packetBridge.reset()
            perform(recovery.reconnecting())

        default:
            break
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        let nsError = error as NSError
        let fatal = (nsError.userInfo[OpenVPNAdapterErrorFatalKey] as? Bool) ?? false
        // Что успело пройти через туннель к моменту ошибки — главный след
        // для обрывов вида PT_SIZE_ERROR.
        let packets = packetBridge.summary()

        stateQueue.async {
            guard self.adapter === openVPNAdapter else { return }
            self.lastAdapterError = error
            // Фатальная ошибка обрывает сессию, только пока сессия есть. Во время
            // остановки по команде пользователя (и после неё) адаптер всё равно
            // отдаст .disconnected, а last_error.txt показал бы под кнопкой
            // «ошибку» там, где человек сам нажал «Отключить».
            let terminatesSession = (self.phase == .starting || self.phase == .connected)
                && self.recovery.state != .stoppingAdapter
                && !self.adapterHasDisconnected
            let tag = fatal && !terminatesSession ? "fatal=true, ignored: \(self.phase)" : "fatal=\(fatal)"
            self.logger.log("error(\(tag)): \(self.describe(error))")
            self.logger.log("packets at error: \(packets)")
            guard fatal, terminatesSession else { return }

            // Если туннель отказались поднимать мы сами, наш текст понятнее.
            let reported: Error = self.refusalReason.map { Self.makeError(4, $0) } ?? error
            self.writeLastError(self.refusalReason ?? self.describe(error))
            self.stopRecoveryTracking()
            self.adapter.disconnect()

            if self.phase == .starting {
                self.finishStart(reported)
            } else {
                self.phase = .stopped
                self.cancelTunnelWithError(reported)
            }
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logMessage: String) {
        // Сообщения ядра приходят с хвостовым переводом строки — без обрезки
        // лог наполовину состоит из пустых строк.
        logger.log("ovpn: \(logMessage.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private func eventName(_ event: OpenVPNAdapterEvent) -> String {
        switch event {
        case .disconnected: return "disconnected"
        case .connected: return "connected"
        case .reconnecting: return "reconnecting"
        case .authPending: return "authPending"
        case .resolve: return "resolve"
        case .wait: return "wait"
        case .waitProxy: return "waitProxy"
        case .connecting: return "connecting"
        case .getConfig: return "getConfig"
        case .assignIP: return "assignIP"
        case .addRoutes: return "addRoutes"
        case .echo: return "echo"
        case .info: return "info"
        case .warn: return "warn"
        case .pause: return "pause"
        case .resume: return "resume"
        case .relay: return "relay"
        case .compressionEnabled: return "compressionEnabled"
        case .unsupportedFeature: return "unsupportedFeature"
        case .unknown: return "unknown"
        @unknown default: return "event#\(event.rawValue)"
        }
    }
}
