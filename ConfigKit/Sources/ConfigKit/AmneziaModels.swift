import Foundation

/// Верхний уровень JSON из ключа vpn:// (см. exportController.cpp:
/// serverConfig + containers + defaultContainer + dns1/dns2).
public struct AmneziaConfig: Decodable {
    public let hostName: String
    public let description: String?
    public let dns1: String?
    public let dns2: String?
    public let defaultContainer: String?
    public let containers: [AmneziaContainer]

    /// Контейнер OpenVPN over Cloak. Имя контейнера в Amnezia — "amnezia-openvpn-cloak".
    public func cloakContainer() throws -> AmneziaContainer {
        let name = "amnezia-openvpn-cloak"
        if let container = containers.first(where: { $0.container == name }) {
            return container
        }
        throw VPNKeyError.noCloakContainer
    }
}

public struct AmneziaContainer: Decodable {
    public let container: String
    public let openvpn: ProtocolSection?
    public let cloak: ProtocolSection?
    public let shadowsocks: ProtocolSection?
}

/// Секция протокола внутри контейнера. Ключевая особенность формата:
/// `last_config` — это JSON-СТРОКА, её парсят ВТОРЫМ проходом.
/// Рядом с ней могут лежать обычные поля (port, transport_proto…).
public struct ProtocolSection: Decodable {
    public let fields: [String: JSONValue]

    public init(from decoder: Decoder) throws {
        fields = try [String: JSONValue](from: decoder)
    }

    public init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    public var lastConfigString: String? {
        if case .string(let s)? = fields["last_config"] { return s }
        return nil
    }

    /// Второй проход: last_config (строка) → словарь JSON-значений.
    public func lastConfigObject() throws -> [String: JSONValue] {
        guard let raw = lastConfigString else {
            throw VPNKeyError.missingField("last_config")
        }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw VPNKeyError.malformedJSON("last_config — не JSON-объект")
        }
        return object
    }

    /// Содержимое last_config, поверх которого наложены соседние скалярные поля
    /// секции (кроме самой last_config). Так делает клиент Amnezia: например,
    /// port из секции cloak перекрывает RemotePort из last_config.
    public func effectiveFields() throws -> [String: JSONValue] {
        var merged = try lastConfigObject()
        for (key, value) in fields where key != "last_config" {
            merged[key] = value
        }
        return merged
    }
}

/// Второй проход для openvpn.last_config: {"config": "<текст .ovpn>", "clientId": …}
public struct OpenVPNLastConfig: Decodable {
    public let config: String
}

extension ProtocolSection {
    /// Полный текст .ovpn-профиля (с инлайн <ca><cert><key><tls-auth>).
    public func ovpnConfigText() throws -> String {
        let object = try lastConfigObject()
        guard case .string(let text)? = object["config"], !text.isEmpty else {
            throw VPNKeyError.missingField("openvpn.last_config.config")
        }
        return text
    }
}
