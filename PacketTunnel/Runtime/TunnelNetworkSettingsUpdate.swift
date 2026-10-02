import NetworkExtension

/// Граница между resetTun адаптера и настройками системного интерфейса.
/// Адаптер пересоздаёт свои сокеты при reconnect и присылает nil до новых
/// настроек. Системные маршруты и DNS должны всё это время оставаться на месте.
enum TunnelNetworkSettingsUpdate {
    static func apply(
        _ settings: NEPacketTunnelNetworkSettings?,
        using configure: (NEPacketTunnelNetworkSettings, @escaping (Error?) -> Void) -> Void,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let settings else {
            // В том числе при stop: системный интерфейс снимает сама iOS после
            // завершения провайдера. Успех разблокирует resetTun адаптера и не
            // порождает его ложную фатальную ошибку TUNSetupFailed (#20).
            completionHandler(nil)
            return
        }
        configure(settings, completionHandler)
    }
}
