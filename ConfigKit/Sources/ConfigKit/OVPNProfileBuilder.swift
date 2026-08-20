import Foundation

/// Финальная сборка текста .ovpn, который приложение передаст расширению.
public enum OVPNProfileBuilder {
    /// - Подставляет $PRIMARY_DNS/$SECONDARY_DNS (если плейсхолдеры есть);
    /// - гарантирует строку `route <serverIP> 255.255.255.255 net_gateway`
    ///   (защита №1 от петли маршрутов: OpenVPNAdapter конвертирует её в
    ///   excludedRoute; вторая защита — excludedRoutes в коде провайдера);
    /// - дописывает блок <cloak> с base64(cloakJSON).
    public static func build(
        ovpnText: String,
        serverIP: String,
        dns1: String,
        dns2: String,
        cloakJSON: Data
    ) -> String {
        var text = ovpnText
            .replacingOccurrences(of: "$PRIMARY_DNS", with: dns1)
            .replacingOccurrences(of: "$SECONDARY_DNS", with: dns2)

        text = ensuringNetGatewayRoute(in: text, serverIP: serverIP)

        // Cloak-транспорт читает свой конфиг ТОЛЬКО из этого блока
        // (setPTCloak() у фреймворка аргументов не имеет).
        text += "\n<cloak>\n\(cloakJSON.base64EncodedString())\n</cloak>\n"
        return text
    }

    /// Проверяет наличие маршрута-исключения для IP сервера; при отсутствии —
    /// вставляет его до первого инлайн-блока (<ca> и т.п.): директивы OpenVPN
    /// внутри инлайн-блоков не действуют.
    static func ensuringNetGatewayRoute(in text: String, serverIP: String) -> String {
        let routeLine = "route \(serverIP) 255.255.255.255 net_gateway"

        let hasRoute = text.split(separator: "\n").contains { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            return parts.count >= 4
                && parts[0] == "route"
                && parts[1] == Substring(serverIP)
                && parts[2] == "255.255.255.255"
                && parts[3] == "net_gateway"
        }
        if hasRoute { return text }

        var lines = text.components(separatedBy: "\n")
        let insertIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("<") }
            ?? lines.count
        lines.insert(routeLine, at: insertIndex)
        return lines.joined(separator: "\n")
    }
}
