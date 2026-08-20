import Foundation

/// Типизированные ошибки импорта. Русские описания показываются
/// пользователю на экране вставки ключа как есть.
public enum VPNKeyError: Error, LocalizedError, Equatable {
    case notAVPNKey
    case invalidBase64
    case decompressionFailed
    case malformedJSON(String)
    case noCloakContainer
    case missingField(String)
    case notAnIPv4(String)

    public var errorDescription: String? {
        switch self {
        case .notAVPNKey:
            return "Это не ключ Amnezia: строка должна начинаться с vpn://"
        case .invalidBase64:
            return "Ключ повреждён: не удалось раскодировать base64 (возможно, строка скопирована не целиком)"
        case .decompressionFailed:
            return "Ключ повреждён: не удалось распаковать данные"
        case .malformedJSON(let detail):
            return "Внутри ключа не JSON-конфигурация Amnezia (\(detail))"
        case .noCloakContainer:
            return "В ключе нет протокола OpenVPN over Cloak — экспортируйте ключ для контейнера amnezia-openvpn-cloak"
        case .missingField(let field):
            return "В конфигурации не хватает поля «\(field)»"
        case .notAnIPv4(let host):
            return "Не удалось определить IPv4-адрес сервера «\(host)»"
        }
    }
}

public enum VPNKeyDecoder {
    /// vpn:// → base64url без паддинга → qUncompress(zlib) → JSON.
    /// Запасной путь: если распаковка не удалась — те же байты как plain JSON
    /// (старые/сторонние экспорты бывают без сжатия).
    public static func decode(_ key: String) throws -> AmneziaConfig {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("vpn://") else { throw VPNKeyError.notAVPNKey }

        let encoded = String(trimmed.dropFirst("vpn://".count))
        guard let raw = base64URLDecode(encoded) else { throw VPNKeyError.invalidBase64 }

        if let unpacked = try? qUncompress(raw) {
            do {
                return try JSONDecoder().decode(AmneziaConfig.self, from: unpacked)
            } catch {
                throw VPNKeyError.malformedJSON(shortDescription(of: error))
            }
        }
        // Распаковка не удалась — пробуем как несжатый JSON.
        guard let config = try? JSONDecoder().decode(AmneziaConfig.self, from: raw) else {
            throw VPNKeyError.decompressionFailed
        }
        return config
    }

    /// base64url (алфавит -_ вместо +/) без паддинга; обычный base64 тоже принимаем.
    static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "=", with: "")
        switch s.count % 4 {
        case 2: s += "=="
        case 3: s += "="
        case 1: return nil
        default: break
        }
        return Data(base64Encoded: s)
    }

    private static func shortDescription(of error: Error) -> String {
        if case DecodingError.keyNotFound(let key, _) = error {
            return "нет поля \(key.stringValue)"
        }
        return String(describing: type(of: error))
    }
}
