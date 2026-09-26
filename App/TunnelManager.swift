import Foundation
import NetworkExtension
import ConfigKit

/// Обёртка NETunnelProviderManager: профиль VPN в настройках системы,
/// старт/стоп туннеля, наблюдение за статусом.
///
/// Профиль — это то, что появляется в Настройках iOS после первого
/// «Разрешить» (системный диалог «…хочет добавить конфигурации VPN»).
///
/// Локализация: всё, что уходит на экран (`lastError`, `notice`, тексты
/// статусов), берётся из `Localizable.xcstrings` через `String(localized:)`;
/// всё, что уходит в `app.log`, остаётся на английском и не локализуется —
/// лог должен читаться одинаково, с какого бы телефона его ни прислали.
@MainActor
final class TunnelManager: ObservableObject {

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?
    /// Нейтральное сообщение под кнопкой (например, «ключ импортирован»).
    @Published private(set) var notice: String?
    /// true, когда в профиле лежит боевой конфиг. Пока его нет, приложение
    /// предлагает импорт ключа, а не подключение.
    @Published private(set) var hasRealConfig = false
    /// Профили прочитаны: до этого момента неизвестно, есть ли ключ, и экран
    /// не должен мигать приглашением к импорту.
    @Published private(set) var isLoaded = false

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private let logger = RingLogger.shared

    /// Не удалось даже прочитать профили при запуске — почти наверняка в подписи
    /// сборки нет права на Network Extension.
    private var loadFailed = false
    /// Отключение по кнопке — не ошибка, причину искать не нужно.
    private var userRequestedStop = false
    /// Момент последнего запроса на старт: по нему видно, успело ли расширение
    /// написать в tunnel.log хоть строку.
    private var startRequestedAt: Date?

    private static let tunnelBundleID = "com.razhev.ovocclient.tunnel"

    init() {
        // object: nil — уведомления приходят обо всех VPN системы; обработчик
        // всё равно перечитывает статус только нашего соединения.
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.statusChanged() }
        }
    }

    // MARK: - Загрузка/сохранение профиля

    /// Подтягивает существующий профиль (если есть) при запуске приложения.
    func load() async {
        defer { isLoaded = true }
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first
            loadFailed = false
            logger.log("load: profiles=\(managers.count) appGroup=\(SharedPaths.containerURL == nil ? "UNAVAILABLE" : "ok")")
            refreshDerivedState()
        } catch {
            loadFailed = true
            logger.log("load FAILED: \(Self.raw(error))")
            lastError = explain(error)
            return
        }
        #if DEBUG
        await importDebugKeyIfPresent()
        startDebugCommandWatcher()
        #endif
    }

    #if DEBUG
    private var debugCommandTimer: DispatchSourceTimer?

    /// DEBUG-мост для `make disconnect`: команда приходит файлом Documents/debug.disconnect
    /// (scripts/debug-command.sh), а не перезапуском приложения — принудительный перезапуск
    /// через devicectl (--terminate-existing) убивает и процесс расширения (в логе приложения
    /// NEVPNConnectionErrorDomain 12, stopTunnel в расширении не вызывается), и остановку
    /// по кнопке так не проверить. Выполняется тем же `stop()`, что и кнопка.
    private func startDebugCommandWatcher() {
        guard debugCommandTimer == nil,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let marker = documents.appendingPathComponent("debug.disconnect")
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, FileManager.default.fileExists(atPath: marker.path) else { return }
            try? FileManager.default.removeItem(at: marker)
            self.logger.log("debug command: disconnect")
            self.stop()
        }
        timer.resume()
        debugCommandTimer = timer
    }
    #endif

    // MARK: - Импорт ключа

    /// Откуда пришёл ключ — только для лога.
    enum KeySource: String {
        case paste, file
        #if DEBUG
        case debugBridge
        #endif
    }

    /// Ошибка импорта с готовым (уже локализованным) текстом для экрана.
    struct ImportFailure: LocalizedError {
        let errorDescription: String?
    }

    /// ЕДИНСТВЕННЫЙ путь импорта ключа: им пользуются и экран импорта (вставка,
    /// файл), и DEBUG-мост `make push-key` — один путь, одна проверка.
    ///
    /// Порядок выбран так, чтобы неудача ничего не портила: сначала ключ целиком
    /// разбирается (до этого момента профиль не трогаем), затем поднятый VPN
    /// отключается, и только потом профиль перезаписывается. При первом импорте
    /// на шаге записи появляется системный диалог «…хочет добавить конфигурации VPN».
    ///
    /// В лог идут только размеры и вид ошибки: ни ключ, ни профиль, ни адреса.
    /// - Returns: название сервера из ключа (для сообщения на экране).
    @discardableResult
    func importKey(_ text: String, source: KeySource) async throws -> String {
        logger.log("import[\(source.rawValue)]: start, text=\(text.utf8.count) bytes")

        // Разбор — не на главном потоке: если hostName в ключе — домен, внутри
        // синхронный DNS-запрос.
        let config: ImportedConfig
        do {
            config = try await Task.detached(priority: .userInitiated) {
                try ImportedConfig.make(fromPastedText: text)
            }.value
        } catch {
            logger.log("import FAILED: parse: \(Self.logCode(error))")
            throw ImportFailure(errorDescription: Self.explainParse(error))
        }

        // Менять профиль под работающим туннелем нельзя: расширение продолжит
        // жить со старым конфигом, а статус на экране будет врать.
        if isTunnelActive {
            logger.log("import: tunnel is up — stopping before profile change")
            guard await stopAndWait() else {
                logger.log("import FAILED: tunnel did not stop in time")
                throw ImportFailure(errorDescription: String(localized:
                    "Не удалось отключить VPN перед сменой ключа. Отключите его кнопкой и повторите импорт."))
            }
        }

        do {
            try await timed { try await self.apply(config: config) }
        } catch {
            logger.log("import FAILED: save profile: \(Self.raw(Self.unwrap(error).error))")
            throw ImportFailure(errorDescription:
                explain(error, retry: String(localized: "Повторите импорт")))
        }

        logger.log("import OK: profile=\(config.ovpnProfile.utf8.count) bytes")
        lastError = nil
        notice = String(localized: "Ключ импортирован: «\(config.description)»")
        return config.description
    }

    private var isTunnelActive: Bool {
        switch manager?.connection.status {
        case .connected, .connecting, .reasserting, .disconnecting: return true
        default: return false
        }
    }

    /// Останавливает туннель и ждёт статуса «Отключено» (обычно 1–2 секунды;
    /// расширение страхует остановку своим таймером на 5 секунд).
    private func stopAndWait(timeout: TimeInterval = 10) async -> Bool {
        guard let connection = manager?.connection else { return true }
        userRequestedStop = true
        connection.stopVPNTunnel()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if connection.status == .disconnected || connection.status == .invalid { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    /// Вид ошибки разбора для лога — без значений из ключа (у notAnIPv4 внутри
    /// имя сервера, поэтому `String(describing:)` здесь не годится).
    private static func logCode(_ error: Error) -> String {
        guard let keyError = error as? VPNKeyError else { return raw(error) }
        switch keyError {
        case .notAVPNKey: return "notAVPNKey"
        case .invalidBase64: return "invalidBase64"
        case .truncated: return "truncated"
        case .decompressionFailed: return "decompressionFailed"
        case .malformedJSON: return "malformedJSON"
        case .noCloakContainer: return "noCloakContainer"
        case .missingField(let field): return "missingField(\(field))"
        case .notAnIPv4: return "notAnIPv4"
        }
    }

    /// Текст ошибки разбора для экрана. ConfigKit — пакет без ресурсов, его
    /// `errorDescription` не локализуется (и остаётся для логов и тестов);
    /// перевод для интерфейса живёт здесь, в каталоге строк приложения.
    private static func explainParse(_ error: Error) -> String {
        guard let keyError = error as? VPNKeyError else {
            return (error as? LocalizedError)?.errorDescription ?? raw(error)
        }
        switch keyError {
        case .notAVPNKey:
            return String(localized: "В этом тексте нет ключа Amnezia: ключ начинается с vpn://")
        case .invalidBase64:
            return String(localized: "Ключ повреждён: не удалось раскодировать base64 (возможно, строка скопирована не целиком)")
        case .truncated:
            return String(localized: "Ключ скопирован не целиком — конец строки обрезан. Скопируйте ключ заново полностью")
        case .decompressionFailed:
            return String(localized: "Ключ повреждён: не удалось распаковать данные")
        case .malformedJSON(let detail):
            return String(localized: "Внутри ключа не JSON-конфигурация Amnezia (\(detail))")
        case .noCloakContainer:
            return String(localized: "В ключе нет протокола OpenVPN over Cloak — экспортируйте ключ для контейнера amnezia-openvpn-cloak")
        case .missingField(let field):
            return String(localized: "В конфигурации не хватает поля «\(field)»")
        case .notAnIPv4(let host):
            return String(localized: "Не удалось определить IPv4-адрес сервера «\(host)»")
        }
    }

    #if DEBUG
    /// DEBUG-мост: `make push-key` кладёт ключ в Documents приложения через
    /// devicectl, здесь он проходит ТОТ ЖЕ `importKey`, что и ключ с экрана импорта.
    /// Нужен, чтобы проверять импорт на телефоне с Mac, без рук. Ключ не входит
    /// ни в один вход сборки, а этого кода нет в Release — в TestFlight ключ
    /// попасть не может. Файл удаляется сразу после чтения.
    private func importDebugKeyIfPresent() async {
        guard let url = Self.findDebugKey() else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let key = try String(contentsOf: url, encoding: .utf8)
            if url.pathExtension == "ovpn" {
                // Диагностика: готовый .ovpn без Cloak (например, к временному
                // тестовому серверу). Мимо ConfigKit — там обязателен контейнер Cloak.
                let config = try Self.rawProfileConfig(key)
                try await apply(config: config)
                logger.log("debug .ovpn imported: profile=\(config.ovpnProfile.utf8.count) bytes")
                lastError = nil
                notice = String(localized: "Ключ импортирован: «\(config.description)»")
            } else {
                try await importKey(key, source: .debugBridge)
            }
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? Self.raw(error)
            lastError = String(localized: "Не удалось импортировать ключ: \(text)")
        }
    }

    /// Сырой .ovpn → ImportedConfig: адрес сервера берём из строки `remote`.
    private static func rawProfileConfig(_ ovpn: String) throws -> ImportedConfig {
        let remote = ovpn.split(whereSeparator: \.isNewline)
            .map { $0.split(separator: " ", omittingEmptySubsequences: true) }
            .first { $0.first == "remote" && $0.count >= 2 }
        guard let host = remote.map({ String($0[1]) }), ImportedConfig.isIPv4Literal(host) else {
            throw VPNKeyError.missingField("remote <IPv4> in .ovpn")
        }
        return ImportedConfig(ovpnProfile: ovpn, serverIP: host, dns1: "1.1.1.1", dns2: "1.0.0.1",
                              description: "DEBUG .ovpn → \(host)")
    }

    /// devicectl может положить файл как Documents/debug.vpnkey или как
    /// Documents/debug.vpnkey/<имя исходного файла> — ищем *.vpnkey / *.ovpn на двух уровнях.
    private static func findDebugKey() -> URL? {
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let enumerator = fm.enumerator(at: documents, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if enumerator.level > 2 { enumerator.skipDescendants(); continue }
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile, ["vpnkey", "ovpn"].contains(url.pathExtension) { return url }
        }
        return nil
    }
    #endif

    /// Сохраняет боевой конфиг в профиль туннеля.
    func apply(config: ImportedConfig) async throws {
        let manager = self.manager ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleID
        proto.serverAddress = config.serverIP
        proto.providerConfiguration = [
            TunnelConfigKeys.ovpnConfig: config.ovpnProfile,
            TunnelConfigKeys.serverIP: config.serverIP,
            TunnelConfigKeys.dns1: config.dns1,
            TunnelConfigKeys.dns2: config.dns2,
        ]

        manager.protocolConfiguration = proto
        manager.localizedDescription = Bundle.main.displayName
        manager.isEnabled = true
        // Авто-подключение (on-demand) сознательно выключено: при недоступном
        // сервере iOS переподключалась бы бесконечно, а смена ключа (стоп →
        // запись профиля) ломалась бы о немедленный перезапуск туннеля системой.
        manager.isOnDemandEnabled = false

        do {
            try await manager.saveToPreferences()
        } catch {
            // Сохранить не дали (например, «Не разрешать» в системном диалоге).
            // Объект в памяти уже изменён — перечитываем, чтобы прежний профиль
            // остался таким, каким лежит в настройках системы.
            try? await self.manager?.loadFromPreferences()
            refreshDerivedState()
            throw error
        }
        // Известная особенность NE: без повторного load свежесохранённый
        // профиль может не стартовать ("Missing protocol or protocol has
        // invalid type").
        try await manager.loadFromPreferences()

        self.manager = manager
        refreshDerivedState()
    }

    #if DEBUG
    /// Диагностика (`make dummy`): профиль-пустышка M1 — расширение поднимет
    /// фиктивный туннель с узким маршрутом (в providerConfiguration нет ovpnConfig —
    /// это и есть признак пустышки). Проверяет подпись, entitlements, App Group и
    /// загрузку фреймворка без участия сервера. ЗАТИРАЕТ боевой профиль — после
    /// неё ключ импортируется заново. Из интерфейса недоступна.
    func applyDummyProfile() async throws {
        let manager = self.manager ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleID
        proto.serverAddress = "dummy"
        proto.providerConfiguration = ["dummy": true]

        manager.protocolConfiguration = proto
        manager.localizedDescription = "\(Bundle.main.displayName) (dummy)"
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        self.manager = manager
        refreshDerivedState()
    }

    /// `make dummy`: записать пустышку и сразу поднять её.
    func connectDummy() async {
        do {
            try await applyDummyProfile()
            await connect(allowDummy: true)
        } catch {
            logger.log("dummy profile FAILED: \(Self.raw(error))")
            lastError = explain(error, retry: "make dummy")
        }
    }
    #endif

    // MARK: - Управление туннелем

    /// Единая точка входа кнопки «Подключить». Любая ошибка попадает под кнопку
    /// и в app.log: «мёртвой» кнопки без сообщения быть не должно.
    ///
    /// Без боевого профиля не подключаемся: профиль появляется только при импорте
    /// ключа (там же — системный диалог «…хочет добавить конфигурации VPN»).
    func connect(allowDummy: Bool = false) async {
        lastError = nil
        notice = nil
        userRequestedStop = false
        guard let manager, hasRealConfig || allowDummy else {
            logger.log("connect refused: no real profile")
            lastError = String(localized: "Сначала добавьте ключ: без него подключаться некуда.")
            return
        }
        do {
            // iOS держит включённым только один VPN-профиль. Если подключались
            // другим клиентом (AmneziaVPN), наш профиль выключен и старт упадёт
            // с configurationDisabled — включаем его обратно.
            if !manager.isEnabled {
                manager.isEnabled = true
                try await timed {
                    try await manager.saveToPreferences()
                    try await manager.loadFromPreferences()
                }
            }

            // Ошибка прошлого запуска не должна всплыть после нового.
            if let url = SharedPaths.lastErrorURL { try? FileManager.default.removeItem(at: url) }

            startRequestedAt = Date()
            try manager.connection.startVPNTunnel()
            logger.log("startVPNTunnel requested")
        } catch {
            logger.log("connect FAILED: \(Self.raw(Self.unwrap(error).error))")
            lastError = explain(error)
            // Устаревший профиль лечится перечитыванием — следующее нажатие сработает.
            try? await manager.loadFromPreferences()
        }
    }

    func stop() {
        userRequestedStop = true
        manager?.connection.stopVPNTunnel()
    }

    // MARK: - Статус

    private func statusChanged() {
        guard let manager else { return }
        let newStatus = manager.connection.status
        guard newStatus != status else { return }
        status = newStatus
        logger.log("status: \(newStatus.logName)")

        // Причину от системы пишем в лог всегда — и при остановке по кнопке:
        // так видно, дошёл ли stopTunnel до расширения или систему что-то убило.
        // Под кнопку — только когда отключились не по нашей команде.
        if newStatus == .disconnected {
            let show = !userRequestedStop && startRequestedAt != nil
            Task { await explainDisconnect(showToUser: show) }
        }
    }

    private func refreshDerivedState() {
        status = manager?.connection.status ?? .invalid
        let providerConfig = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        hasRealConfig = (providerConfig?[TunnelConfigKeys.ovpnConfig] as? String)?.isEmpty == false
    }

    /// Почему туннель отключился сам. Источники: причина от системы
    /// (fetchLastDisconnectError) и last_error.txt, который пишет расширение.
    private func explainDisconnect(showToUser: Bool) async {
        guard let connection = manager?.connection else { return }
        let systemError: NSError? = await withCheckedContinuation { continuation in
            connection.fetchLastDisconnectError { continuation.resume(returning: $0 as NSError?) }
        }
        logger.log("disconnect reason: \(systemError.map(Self.raw) ?? "none")")
        guard showToUser else { return }

        var parts: [String] = []
        if let systemError {
            parts.append(Self.describeDisconnect(systemError) + "\n[\(Self.raw(systemError))]")
        }
        if let url = SharedPaths.lastErrorURL,
           let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            // Текст расширения показываем как есть: он же лежит в tunnel.log.
            parts.append(text)
        }
        if !extensionWroteLogSince(startRequestedAt) {
            parts.append(String(localized:
                "Расширение туннеля не написало в лог ни строки — оно не запустилось или у него нет доступа к App Group."))
        }
        guard !parts.isEmpty else { return }
        lastError = parts.joined(separator: "\n\n")
    }

    private func extensionWroteLogSince(_ date: Date?) -> Bool {
        guard let date,
              let url = SharedPaths.logFileURL,
              let modified = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        else { return false }
        return modified >= date.addingTimeInterval(-1)
    }

    // MARK: - Расшифровка ошибок

    /// Ошибка шага сохранения профиля + сколько он длился. Мгновенный отказ
    /// означает, что системный диалог даже не показывался.
    private struct ProfileSaveError: Error {
        let underlying: Error
        let elapsed: TimeInterval
    }

    private func timed(_ step: () async throws -> Void) async throws {
        let started = Date()
        do {
            try await step()
        } catch {
            throw ProfileSaveError(underlying: error, elapsed: Date().timeIntervalSince(started))
        }
    }

    private static func unwrap(_ error: Error) -> (error: Error, elapsed: TimeInterval?) {
        if let saveError = error as? ProfileSaveError {
            return (saveError.underlying, saveError.elapsed)
        }
        return (error, nil)
    }

    /// Человеческое объяснение + сырой код. Строки системных ошибок NE не
    /// документированы, подсказка эвристическая — поэтому код показываем всегда.
    /// - Parameter retry: что сделать, чтобы повторить (уже локализованная строка).
    private func explain(_ error: Error, retry: String? = nil) -> String {
        let retry = retry ?? String(localized: "Нажмите «Подключить» ещё раз")
        let (underlying, elapsed) = Self.unwrap(error)
        let nsError = underlying as NSError
        let text = nsError.localizedDescription.lowercased()

        let hint: String
        if text.contains("permission denied") || text.contains("ipc failed") {
            if loadFailed || (elapsed ?? 1) < 0.5 {
                hint = String(localized:
                    "Система отказала сразу, без диалога: в подписи сборки нет права на Network Extension. Это проблема сборки — смотрите ворота entitlements в выводе make install.")
            } else {
                hint = String(localized:
                    "Вы нажали «Не разрешать» (или VPN запрещён профилем управления). \(retry) и выберите «Разрешить».")
            }
        } else if nsError.domain == NEVPNErrorDomain, let code = NEVPNError.Code(rawValue: nsError.code) {
            switch code {
            case .configurationInvalid:
                hint = String(localized: "Профиль VPN некорректен — обычно не совпал bundle id расширения.")
            case .configurationDisabled:
                hint = String(localized: "Профиль VPN выключен: активен другой VPN. Отключите его и повторите.")
            case .configurationStale:
                hint = String(localized: "Профиль VPN устарел — нажмите «Подключить» ещё раз.")
            case .configurationReadWriteFailed:
                hint = String(localized: "Система не дала прочитать или сохранить профиль VPN.")
            case .connectionFailed:
                hint = String(localized: "Система не смогла запустить туннель.")
            default:
                hint = String(localized: "Не удалось создать или запустить профиль VPN.")
            }
        } else {
            hint = String(localized: "Не удалось создать или запустить профиль VPN.")
        }
        return "\(hint)\n[\(Self.raw(underlying))]"
    }

    /// Коды NEVPNConnectionErrorDomain (NEVPNConnection.h). Ошибка из другого
    /// домена — это NSError, который расширение само передало системе.
    private static func describeDisconnect(_ error: NSError) -> String {
        guard error.domain == NEVPNConnectionErrorDomain else {
            return String(localized: "Туннель завершился с ошибкой: \(error.localizedDescription)")
        }
        switch error.code {
        case 12:
            return String(localized:
                "Расширение туннеля аварийно завершилось: не загрузился фреймворк, сбой подписи или нехватка памяти. Отчёт о падении: make crashlogs.")
        case 14:
            return String(localized:
                "Система не нашла расширение туннеля (bundle id / NSExtension) либо приложение только что переустановлено — попробуйте ещё раз.")
        case 4, 13:
            return String(localized: "Профиль VPN повреждён: удалите его в Настройки → VPN и подключитесь заново.")
        case 2:
            return String(localized: "Нет сети.")
        default:
            return String(localized: "Система разорвала VPN-соединение.")
        }
    }

    private static func raw(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }
}

extension NEVPNStatus {
    /// Текст статуса на экране — для всех значений `NEVPNStatus`.
    var localizedText: String {
        switch self {
        case .invalid: return String(localized: "Нет профиля VPN")
        case .disconnected: return String(localized: "Отключено")
        case .connecting: return String(localized: "Подключение…")
        case .connected: return String(localized: "Подключено")
        case .reasserting: return String(localized: "Переподключение…")
        case .disconnecting: return String(localized: "Отключение…")
        @unknown default: return String(localized: "Неизвестное состояние")
        }
    }

    /// Пояснение под статусом (когда оно нужно): что происходит и чего ждать.
    var localizedHint: String? {
        switch self {
        case .invalid:
            return String(localized:
                "Профиль VPN недоступен: его удалили в Настройках или не разрешили создать. Импортируйте ключ заново.")
        case .reasserting:
            return String(localized: "Сеть изменилась — соединение восстанавливается, ничего нажимать не нужно.")
        case .disconnecting:
            return String(localized: "Туннель закрывается, это занимает пару секунд.")
        default:
            return nil
        }
    }

    /// Имя статуса для app.log — не локализуется, чтобы лог читался одинаково
    /// с любого телефона.
    var logName: String {
        switch self {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
