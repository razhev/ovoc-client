import NetworkExtension
import OpenVPNAdapter

/// Ядро VPN. Два режима:
/// - «пустышка» (в providerConfiguration нет ключа ovpnConfig) — для M1:
///   фиктивный интерфейс с УЗКИМ маршрутом, проверяет подписи/App Group;
/// - боевой: OpenVPN over Cloak через OpenVPNAdapter.
///
/// Сигнатуры фреймворка зафиксированы в docs/FRAMEWORK-API.md — код написан
/// строго по ним, не по упоминаниям в блогах (форк Amnezia менял API).
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let logger = RingLogger.shared

    private lazy var adapter: OpenVPNAdapter = {
        let adapter = OpenVPNAdapter()
        adapter.delegate = self
        return adapter
    }()

    /// Состояние старта/остановки. Completion'ы системы можно вызвать ровно
    /// один раз — храним и обнуляем.
    private var startCompletion: ((Error?) -> Void)?
    private var stopCompletion: (() -> Void)?
    private var adapterStarted = false

    /// Сторожевой таймер старта: рукопожатие Cloak многосекундное, а через
    /// ~60 сек (недокументировано) систем­а молча убивает расширение.
    /// 30 сек — понятная ошибка вместо тихой смерти.
    private var startWatchdog: DispatchSourceTimer?
    /// Страховка стопа: если адаптер не отдал .disconnected за 5 сек —
    /// завершаем стоп сами.
    private var stopWatchdog: DispatchSourceTimer?

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

        ovpnText = ovpn
        serverIP = providerConfig?[TunnelConfigKeys.serverIP] as? String
        fallbackDNS = [
            providerConfig?[TunnelConfigKeys.dns1] as? String,
            providerConfig?[TunnelConfigKeys.dns2] as? String,
        ].compactMap { $0 }

        logger.log("real tunnel: serverIP=\(serverIP ?? "nil") profile=\(ovpn.count) bytes")

        let configuration = OpenVPNConfiguration()
        configuration.fileContent = ovpn.data(using: .utf8)
        configuration.tunPersist = true
        // Включает Cloak-транспорт; сам конфиг Cloak фреймворк читает
        // из блока <cloak> внутри fileContent (метод аргументов не имеет).
        configuration.setPTCloak()

        do {
            let evaluation = try adapter.apply(configuration: configuration)
            logger.log("apply OK: remoteHost=\(evaluation.remoteHost ?? "?")")
        } catch {
            // Ошибки разбора конфига — самый вероятный класс багов; лог дословный.
            logger.log("apply FAILED: \(describe(error))")
            writeLastError("Ошибка конфигурации: \(describe(error))")
            completionHandler(error)
            return
        }

        startCompletion = completionHandler
        armStartWatchdog()
        adapterStarted = true
        adapter.connect(using: packetFlow)
    }

    private func startDummyTunnel(completionHandler: @escaping (Error?) -> Void) {
        logger.log("dummy mode: no ovpnConfig in providerConfiguration")

        // M1 проверяет именно App Group. Без контейнера файловый лог молча не
        // пишется, поэтому падаем громко: приложение покажет причину под кнопкой
        // (она доходит через fetchLastDisconnectError).
        guard SharedPaths.containerURL != nil else {
            completionHandler(NSError(
                domain: "com.razhev.personalvpn.tunnel", code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    "App Group \(SharedPaths.appGroupID) недоступна расширению — проверьте "
                    + "entitlements PacketTunnel и App Groups у App ID на портале"]
            ))
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
        cancelStartWatchdog()

        guard adapterStarted else {
            completionHandler()
            return
        }

        stopCompletion = completionHandler
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 5)
        watchdog.setEventHandler { [weak self] in
            self?.logger.log("stop watchdog fired: adapter didn't report .disconnected in 5s")
            self?.finishStop()
        }
        watchdog.resume()
        stopWatchdog = watchdog

        adapter.disconnect()
    }

    private func finishStop() {
        stopWatchdog?.cancel()
        stopWatchdog = nil
        adapterStarted = false
        stopCompletion?()
        stopCompletion = nil
    }

    // MARK: - Sleep/wake (v1 — простой проброс; tunPersist держит туннель)

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
    }

    // MARK: - Вспомогательное

    private func armStartWatchdog() {
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 30)
        watchdog.setEventHandler { [weak self] in
            guard let self, let completion = self.startCompletion else { return }
            self.logger.log("start watchdog fired: no .connected event in 30s")
            self.writeLastError("Не удалось подключиться за 30 секунд — сервер недоступен или конфигурация неверна")
            self.startCompletion = nil
            self.adapter.disconnect()
            completion(NSError(
                domain: "com.razhev.personalvpn.tunnel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Connection timed out after 30s"]
            ))
        }
        watchdog.resume()
        startWatchdog = watchdog
    }

    private func cancelStartWatchdog() {
        startWatchdog?.cancel()
        startWatchdog = nil
    }

    /// dhcp-option DNS x.x.x.x из текста конфига — второй уровень DNS-fallback.
    private func dnsFromProfile() -> [String] {
        ovpnText.split(separator: "\n").compactMap { line in
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
    /// 127.0.0.1 и автоисключение IP сервера у iOS НЕ сработает. Исключаем сами.
    func openVPNAdapter(
        _ openVPNAdapter: OpenVPNAdapter,
        configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let settings = networkSettings else {
            logger.log("configureTunnel: clearing network settings")
            setTunnelNetworkSettings(nil) { completionHandler($0) }
            return
        }

        // Весь DNS — в туннель (иначе часть запросов уйдёт мимо VPN).
        let dnsServers = settings.dnsSettings?.servers ?? []
        if dnsServers.isEmpty {
            let fallback = dnsFromProfile().isEmpty ? fallbackDNS : dnsFromProfile()
            logger.log("adapter gave no DNS, fallback: \(fallback.joined(separator: ","))")
            settings.dnsSettings = NEDNSSettings(servers: fallback)
        }
        settings.dnsSettings?.matchDomains = [""]

        // Вторая половина защиты от петли (первая — route ... net_gateway в профиле).
        if let serverIP {
            let ipv4 = settings.ipv4Settings
            var excluded = ipv4?.excludedRoutes ?? []
            excluded.append(NEIPv4Route(destinationAddress: serverIP, subnetMask: "255.255.255.255"))
            ipv4?.excludedRoutes = excluded
        }

        let included = settings.ipv4Settings?.includedRoutes?.count ?? 0
        let excluded = settings.ipv4Settings?.excludedRoutes?.count ?? 0
        logger.log("configureTunnel: remote=\(settings.tunnelRemoteAddress) "
                   + "routes incl=\(included) excl=\(excluded) "
                   + "dns=\(settings.dnsSettings?.servers.joined(separator: ",") ?? "none")")

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.logger.log("setTunnelNetworkSettings failed: \(error.localizedDescription)")
            }
            completionHandler(error)
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleEvent event: OpenVPNAdapterEvent, message: String?) {
        logger.log("event: \(eventName(event))" + (message.map { " — \($0)" } ?? ""))

        switch event {
        case .connected:
            cancelStartWatchdog()
            // Успешный старт: очищаем прошлую ошибку, чтобы приложение её не показывало.
            if let url = SharedPaths.lastErrorURL { try? FileManager.default.removeItem(at: url) }
            startCompletion?(nil)
            startCompletion = nil

        case .disconnected:
            adapterStarted = false
            if stopCompletion != nil {
                finishStop()
            } else if startCompletion == nil {
                // Неожиданный обрыв уже установленного соединения.
                logger.log("unexpected disconnect — cancelling tunnel")
                cancelTunnelWithError(nil)
            }

        case .reconnecting:
            reasserting = true

        case .assignIP, .addRoutes, .getConfig, .connecting, .wait, .resolve:
            break

        default:
            break
        }

        if event == .connected {
            reasserting = false
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        let nsError = error as NSError
        let fatal = (nsError.userInfo[OpenVPNAdapterErrorFatalKey] as? Bool) ?? false
        logger.log("error(fatal=\(fatal)): \(describe(error))")

        guard fatal else { return }

        writeLastError(describe(error))
        cancelStartWatchdog()
        if let completion = startCompletion {
            startCompletion = nil
            completion(error)
        } else {
            cancelTunnelWithError(error)
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logMessage: String) {
        logger.log("ovpn: \(logMessage)")
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

/// Протокол фреймворка в точности повторяет методы NEPacketTunnelFlow —
/// мост между ними пустой. @retroactive: конформанс чужого типа чужому
/// протоколу здесь осознанный (документированный паттерн OpenVPNAdapter).
extension NEPacketTunnelFlow: @retroactive OpenVPNAdapterPacketFlow {}
