import Foundation
import NetworkExtension
import ConfigKit

/// Обёртка NETunnelProviderManager: профиль VPN в настройках системы,
/// старт/стоп туннеля, наблюдение за статусом.
///
/// Профиль — это то, что появляется в Настройках iOS после первого
/// «Разрешить» (системный диалог «…хочет добавить конфигурации VPN»).
@MainActor
final class TunnelManager: ObservableObject {

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?
    /// Нейтральное сообщение под кнопкой (например, «ключ импортирован»).
    @Published private(set) var notice: String?
    /// true, когда в профиле лежит боевой конфиг (а не пустышка M1).
    @Published private(set) var hasRealConfig = false

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

    private static let tunnelBundleID = "com.razhev.personalvpn.tunnel"

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
        #endif
    }

    #if DEBUG
    /// DEBUG-мост M3 (экрана импорта ещё нет — он появится в M4). `make push-key`
    /// кладёт ключ в Documents приложения через devicectl; здесь он проходит тот же
    /// путь, что пройдёт при импорте в M4: ConfigKit → профиль туннеля. Ключ не
    /// входит ни в один вход сборки, а этого кода нет в Release — в TestFlight
    /// ключ попасть не может. Файл удаляется сразу после чтения.
    private func importDebugKeyIfPresent() async {
        guard let url = Self.findDebugKey() else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let key = try String(contentsOf: url, encoding: .utf8)
            let config = try await Task.detached(priority: .userInitiated) {
                try ImportedConfig.make(fromKey: key)
            }.value
            try await apply(config: config)
            // В лог — только размеры: ни ключ, ни адреса туда не попадают.
            logger.log("debug key imported: profile=\(config.ovpnProfile.utf8.count) bytes")
            lastError = nil
            notice = "Ключ импортирован: «\(config.description)»"
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? Self.raw(error)
            logger.log("debug key import FAILED: \(text)")
            lastError = "Не удалось импортировать ключ: \(text)"
        }
    }

    /// devicectl может положить файл как Documents/debug.vpnkey или как
    /// Documents/debug.vpnkey/<имя исходного файла> — ищем *.vpnkey на двух уровнях.
    private static func findDebugKey() -> URL? {
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let enumerator = fm.enumerator(at: documents, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if enumerator.level > 2 { enumerator.skipDescendants(); continue }
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile, url.pathExtension == "vpnkey" { return url }
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
        manager.localizedDescription = "PersonalVPN"
        manager.isEnabled = true

        try await manager.saveToPreferences()
        // Известная особенность NE: без повторного load свежесохранённый
        // профиль может не стартовать ("Missing protocol or protocol has
        // invalid type").
        try await manager.loadFromPreferences()

        self.manager = manager
        refreshDerivedState()
    }

    /// Профиль-пустышка для M1: расширение поднимет фиктивный туннель
    /// (в providerConfiguration нет ovpnConfig — это и есть признак пустышки).
    func applyDummyProfile() async throws {
        let manager = self.manager ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleID
        proto.serverAddress = "dummy"
        proto.providerConfiguration = ["dummy": true]

        manager.protocolConfiguration = proto
        manager.localizedDescription = "PersonalVPN (тест)"
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        self.manager = manager
        refreshDerivedState()
    }

    // MARK: - Управление туннелем

    /// Единая точка входа кнопки «Подключить». Любая ошибка попадает под кнопку
    /// и в app.log: M1 существует, чтобы увидеть ошибки подписи и entitlements,
    /// «мёртвой» кнопки без сообщения быть не должно.
    func connect() async {
        lastError = nil
        notice = nil
        userRequestedStop = false
        do {
            if manager == nil {
                // Профиля ещё нет (M1) — создаём пустышку; здесь появляется
                // системный диалог «…хочет добавить конфигурации VPN».
                try await timed { try await self.applyDummyProfile() }
            }
            guard let manager else { return }

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
            try? await manager?.loadFromPreferences()
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
        logger.log("status: \(newStatus.localizedText)")

        if newStatus == .disconnected, !userRequestedStop, startRequestedAt != nil {
            Task { await explainDisconnect() }
        }
    }

    private func refreshDerivedState() {
        status = manager?.connection.status ?? .invalid
        let providerConfig = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        hasRealConfig = (providerConfig?[TunnelConfigKeys.ovpnConfig] as? String)?.isEmpty == false
    }

    /// Почему туннель отключился сам. Источники: причина от системы
    /// (fetchLastDisconnectError) и last_error.txt, который пишет расширение.
    private func explainDisconnect() async {
        guard let connection = manager?.connection else { return }
        let systemError: NSError? = await withCheckedContinuation { continuation in
            connection.fetchLastDisconnectError { continuation.resume(returning: $0 as NSError?) }
        }

        var parts: [String] = []
        if let systemError {
            logger.log("disconnect reason: \(Self.raw(systemError))")
            parts.append(Self.describeDisconnect(systemError) + "\n[\(Self.raw(systemError))]")
        }
        if let url = SharedPaths.lastErrorURL,
           let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            parts.append(text)
        }
        if !extensionWroteLogSince(startRequestedAt) {
            parts.append("Расширение туннеля не написало в лог ни строки — оно не запустилось "
                         + "или у него нет доступа к App Group.")
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
    private func explain(_ error: Error) -> String {
        let (underlying, elapsed) = Self.unwrap(error)
        let nsError = underlying as NSError
        let text = nsError.localizedDescription.lowercased()

        let hint: String
        if text.contains("permission denied") || text.contains("ipc failed") {
            if loadFailed || (elapsed ?? 1) < 0.5 {
                hint = "Система отказала сразу, без диалога: в подписи сборки нет права на "
                     + "Network Extension. Это проблема сборки — смотрите ворота entitlements "
                     + "в выводе make install."
            } else {
                hint = "Вы нажали «Не разрешать» (или VPN запрещён профилем управления). "
                     + "Нажмите «Подключить» ещё раз и выберите «Разрешить»."
            }
        } else if nsError.domain == NEVPNErrorDomain, let code = NEVPNError.Code(rawValue: nsError.code) {
            switch code {
            case .configurationInvalid:
                hint = "Профиль VPN некорректен — обычно не совпал bundle id расширения."
            case .configurationDisabled:
                hint = "Профиль VPN выключен: активен другой VPN. Отключите его и повторите."
            case .configurationStale:
                hint = "Профиль VPN устарел — нажмите «Подключить» ещё раз."
            case .configurationReadWriteFailed:
                hint = "Система не дала прочитать или сохранить профиль VPN."
            case .connectionFailed:
                hint = "Система не смогла запустить туннель."
            default:
                hint = "Не удалось создать или запустить профиль VPN."
            }
        } else {
            hint = "Не удалось создать или запустить профиль VPN."
        }
        return "\(hint)\n[\(Self.raw(underlying))]"
    }

    /// Коды NEVPNConnectionErrorDomain (NEVPNConnection.h). Ошибка из другого
    /// домена — это NSError, который расширение само передало системе.
    private static func describeDisconnect(_ error: NSError) -> String {
        guard error.domain == NEVPNConnectionErrorDomain else {
            return "Туннель завершился с ошибкой: \(error.localizedDescription)"
        }
        switch error.code {
        case 12:
            return "Расширение туннеля аварийно завершилось: не загрузился фреймворк, сбой "
                 + "подписи или нехватка памяти. Отчёт о падении: make crashlogs."
        case 14:
            return "Система не нашла расширение туннеля (bundle id / NSExtension) либо "
                 + "приложение только что переустановлено — попробуйте ещё раз."
        case 4, 13:
            return "Профиль VPN повреждён: удалите его в Настройки → VPN и подключитесь заново."
        case 2:
            return "Нет сети."
        default:
            return "Система разорвала VPN-соединение."
        }
    }

    private static func raw(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }
}

extension NEVPNStatus {
    var localizedText: String {
        switch self {
        case .invalid: return "Нет профиля VPN"
        case .disconnected: return "Отключено"
        case .connecting: return "Подключение…"
        case .connected: return "Подключено"
        case .reasserting: return "Переподключение…"
        case .disconnecting: return "Отключение…"
        @unknown default: return "Неизвестно"
        }
    }
}
