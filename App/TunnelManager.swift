import Foundation
import NetworkExtension
import ConfigKit

/// Обёртка NETunnelProviderManager: профиль VPN в настройках системы,
/// старт/стоп туннеля, наблюдение за статусом.
///
/// Профиль — это то, что появляется в Настройках iOS после первого
/// «Разрешить» (системный диалог «…хочет добавить конфигурацию VPN»).
@MainActor
final class TunnelManager: ObservableObject {

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?
    /// true, когда в профиле лежит боевой конфиг (а не пустышка M1).
    @Published private(set) var hasRealConfig = false

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    private static let tunnelBundleID = "com.razhev.personalvpn.tunnel"

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            Task { @MainActor in self?.statusChanged(connection) }
        }
    }

    // MARK: - Загрузка/сохранение профиля

    /// Подтягивает существующий профиль (если есть) при запуске приложения.
    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first
            refreshDerivedState()
        } catch {
            lastError = "Не удалось загрузить профиль VPN: \(error.localizedDescription)"
        }
    }

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

    func start() {
        guard let manager else { return }
        do {
            try manager.connection.startVPNTunnel()
            lastError = nil
        } catch {
            lastError = "Не удалось запустить туннель: \(error.localizedDescription)"
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    var hasProfile: Bool { manager != nil }

    // MARK: - Статус

    private func statusChanged(_ connection: NEVPNConnection) {
        status = connection.status
        if status == .disconnected {
            readLastErrorFile()
        }
    }

    private func refreshDerivedState() {
        status = manager?.connection.status ?? .invalid
        let providerConfig = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        hasRealConfig = (providerConfig?[TunnelConfigKeys.ovpnConfig] as? String)?.isEmpty == false
    }

    /// Расширение пишет фатальные ошибки в App Group — показываем под кнопкой.
    private func readLastErrorFile() {
        guard let url = SharedPaths.lastErrorURL,
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else { return }
        lastError = text
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
