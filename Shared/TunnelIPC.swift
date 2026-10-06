import Foundation

/// Ключи словаря `providerConfiguration` (`NETunnelProviderProtocol`),
/// через который приложение передаёт расширению готовый конфиг.
///
/// Расширение не распаковывает ключ (лимит памяти 50 МБ): приложение при импорте
/// собирает финальный текст .ovpn — с подставленным DNS, строкой route для IP
/// сервера и дописанным блоком <cloak> — и кладёт его сюда целиком.
enum TunnelConfigKeys {
    /// Полный текст .ovpn-профиля (инлайн-сертификаты + блок <cloak>).
    /// Отсутствие ключа означает режим «пустышки» (M1).
    static let ovpnConfig = "ovpnConfig"
    /// IPv4-адрес сервера — добавляется в excludedRoutes (защита от петли маршрутов).
    static let serverIP = "serverIP"
    static let dns1 = "dns1"
    static let dns2 = "dns2"
    static let serviceBypassPolicy = ServiceBypassPolicy.configurationKey
}
