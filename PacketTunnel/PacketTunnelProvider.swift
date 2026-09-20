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

    private static let errorDomain = "com.razhev.personalvpn.tunnel"

    private let logger = RingLogger.shared
    private let stateQueue = DispatchQueue(label: "com.razhev.personalvpn.tunnel.state")

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
        configuration.fileContent = ovpn.data(using: .utf8)
        // tunPersist НЕ включаем: рабочий код Amnezia (4.8.12.x) его не ставит.
        // С ним при цикле переподключений туннель продолжал забирать весь трафик,
        // и телефон оставался без интернета.
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
        armStartWatchdog()
        packetBridge.serverAddress = serverIP.split(separator: ".").compactMap { UInt8($0) }
        packetBridge.reset()
        adapter.connect(using: packetBridge)
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
        completion(error)
    }

    private func finishStop() {
        guard let completion = stopCompletion else { return }
        stopCompletion = nil
        stopWatchdog?.cancel()
        stopWatchdog = nil
        phase = .stopped
        completion()
    }

    // MARK: - Sleep/wake (v1 — простой проброс)

    override func sleep(completionHandler: @escaping () -> Void) {
        logger.log("sleep")
        completionHandler()
    }

    override func wake() {
        logger.log("wake")
    }

    // MARK: - Вспомогательное

    /// Только на stateQueue.
    private func armStartWatchdog() {
        let watchdog = DispatchSource.makeTimerSource(queue: stateQueue)
        watchdog.schedule(deadline: .now() + 30)
        watchdog.setEventHandler { [weak self] in
            guard let self, self.phase == .starting else { return }
            self.logger.log("start watchdog fired: no .connected event in 30s")
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

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let message = nsError.userInfo[OpenVPNAdapterErrorMessageKey] as? String
        return "\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)"
            + (message.map { " | \($0)" } ?? "")
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
            self.configureTunnel(networkSettings, completionHandler: completionHandler)
        }
    }

    /// Только на stateQueue.
    private func configureTunnel(
        _ networkSettings: NEPacketTunnelNetworkSettings?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let settings = networkSettings else {
            logger.log("configureTunnel: clearing network settings")
            setTunnelNetworkSettings(nil) { completionHandler($0) }
            return
        }

        func refuse(_ message: String) {
            logger.log("configureTunnel REFUSED: \(message)")
            refusalReason = message
            writeLastError(message)
            completionHandler(Self.makeError(4, message))
        }

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

        // MTU задаём явно: сервер его не присылает, а значение «по умолчанию»
        // у iOS не документировано. Сервер OpenVPN в TCP-режиме рвёт соединение
        // на первом же пакете длиннее своего предела («Bad encapsulated packet
        // length») — снаружи это выглядит ровно как наш обрыв сразу после
        // connected. 1400 — с запасом под tun-mtu 1500 на сервере.
        if settings.mtu == nil {
            settings.mtu = 1400
        }

        let included = settings.ipv4Settings?.includedRoutes?.count ?? 0
        let excluded = settings.ipv4Settings?.excludedRoutes?.count ?? 0
        logger.log("configureTunnel: remote=\(settings.tunnelRemoteAddress) "
                   + "routes incl=\(included) excl=\(excluded) serverExcluded=\(alreadyExcluded ? "by-profile" : "added") "
                   + "ipv6=\(settings.ipv6Settings == nil ? "none" : "set") "
                   + "dns=\(settings.dnsSettings?.servers.joined(separator: ",") ?? "none") "
                   + "mtu=\(settings.mtu?.stringValue ?? "default")")

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.logger.log("setTunnelNetworkSettings failed: \(error.localizedDescription)")
            }
            completionHandler(error)
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleEvent event: OpenVPNAdapterEvent, message: String?) {
        logger.log("event: \(eventName(event))" + (message.map { " — \($0)" } ?? ""))
        stateQueue.async { self.handle(event) }
    }

    /// Только на stateQueue.
    private func handle(_ event: OpenVPNAdapterEvent) {
        switch event {
        case .connected:
            reasserting = false
            lastAdapterError = nil
            if phase == .starting {
                // Успешный старт: очищаем прошлую ошибку, чтобы приложение её не показывало.
                if let url = SharedPaths.lastErrorURL { try? FileManager.default.removeItem(at: url) }
                logger.logMemory("connected")
                finishStart(nil)
            }

        case .disconnected:
            switch phase {
            case .starting:
                // Клиент завершился, не дойдя до .connected — не ждём 30 секунд.
                let error = lastAdapterError
                    ?? Self.makeError(7, refusalReason ?? "Соединение разорвано до установления")
                finishStart(error)
            case .connected:
                logger.log("unexpected disconnect — cancelling tunnel")
                phase = .stopped
                cancelTunnelWithError(lastAdapterError)
            case .stopping:
                finishStop()
            case .idle, .stopped:
                break
            }

        case .reconnecting:
            reasserting = true
            packetBridge.reset()

        default:
            break
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        let nsError = error as NSError
        let fatal = (nsError.userInfo[OpenVPNAdapterErrorFatalKey] as? Bool) ?? false
        logger.log("error(fatal=\(fatal)): \(describe(error))")
        // Что успело пройти через туннель к моменту ошибки — главный след
        // для обрывов вида PT_SIZE_ERROR.
        logger.log("packets at error: \(packetBridge.summary())")

        stateQueue.async {
            self.lastAdapterError = error
            guard fatal else { return }

            // Если туннель отказались поднимать мы сами, наш текст понятнее.
            let reported: Error = self.refusalReason.map { Self.makeError(4, $0) } ?? error
            self.writeLastError(self.refusalReason ?? self.describe(error))

            switch self.phase {
            case .starting:
                self.finishStart(reported)
            case .connected:
                self.phase = .stopped
                self.cancelTunnelWithError(reported)
            case .idle, .stopping, .stopped:
                break
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
