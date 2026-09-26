import Foundation

/// Типизированные ошибки импорта. Русские описания показываются
/// пользователю на экране вставки ключа как есть.
public enum VPNKeyError: Error, LocalizedError, Equatable {
    case notAVPNKey
    case invalidBase64
    /// Ключ начинается правильно, но обрывается: скопирован не целиком.
    case truncated
    case decompressionFailed
    case malformedJSON(String)
    case noCloakContainer
    case missingField(String)
    case notAnIPv4(String)

    public var errorDescription: String? {
        switch self {
        case .notAVPNKey:
            return "В этом тексте нет ключа Amnezia: ключ начинается с vpn://"
        case .invalidBase64:
            return "Ключ повреждён: не удалось раскодировать base64 (возможно, строка скопирована не целиком)"
        case .truncated:
            return "Ключ скопирован не целиком — конец строки обрезан. Скопируйте ключ заново полностью"
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
    /// Вставленный текст → конфигурация. Принимает ключ «как его прислали»: внутри
    /// сообщения, с переносами строк и невидимыми символами (см. `VPNKeyText`).
    /// Перебирает кандидатов от длинного к короткому; ошибку сообщает по самому
    /// длинному — он ближе всего к тому, что человек считал ключом.
    public static func decode(pastedText text: String) throws -> AmneziaConfig {
        var firstError: Error?
        for candidate in VPNKeyText.candidates(in: text) {
            do {
                return try decode(candidate)
            } catch {
                firstError = firstError ?? error
            }
        }
        throw firstError ?? VPNKeyError.notAVPNKey
    }

    /// vpn:// → base64url без паддинга → qUncompress(zlib) → JSON.
    /// Запасной путь: если распаковка не удалась — те же байты как plain JSON
    /// (старые/сторонние экспорты бывают без сжатия).
    public static func decode(_ key: String) throws -> AmneziaConfig {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("vpn://") else { throw VPNKeyError.notAVPNKey }

        let encoded = String(trimmed.dropFirst("vpn://".count))
        guard let raw = decodeBody(encoded) else { throw VPNKeyError.invalidBase64 }

        let zlibError: ZlibError?
        do {
            let unpacked = try qUncompress(raw)
            do {
                return try JSONDecoder().decode(AmneziaConfig.self, from: unpacked)
            } catch {
                throw VPNKeyError.malformedJSON(shortDescription(of: error))
            }
        } catch let error as ZlibError {
            zlibError = error
        }
        // Распаковка не удалась — пробуем как несжатый JSON.
        if let config = try? JSONDecoder().decode(AmneziaConfig.self, from: raw) {
            return config
        }
        // Обрезанный ключ: оборванный zlib-поток либо несжатый JSON без конца.
        if zlibError?.isTruncation == true || raw.first == UInt8(ascii: "{") {
            throw VPNKeyError.truncated
        }
        throw VPNKeyError.decompressionFailed
    }

    /// Длина base64 ≡ 1 (mod 4) невозможна: строка обрезана посреди четвёрки или
    /// к ней прилип лишний символ. Если алфавит при этом верный, последний символ
    /// всё равно не несёт ни одного целого байта — отбрасываем его и разбираем
    /// дальше: обрезанный ключ получит честное «скопирован не целиком».
    private static func decodeBody(_ encoded: String) -> Data? {
        if let data = base64URLDecode(encoded) { return data }
        guard encoded.allSatisfy(VPNKeyText.isBase64URL) else { return nil }
        return base64URLDecode(String(encoded.dropLast()))
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
        // Только имена полей: значения из ключа в текст ошибки не попадают.
        switch error {
        case DecodingError.keyNotFound(let key, _):
            return "нет поля \(key.stringValue)"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "неожиданный тип поля \(path)"
        default:
            return "данные не разбираются как JSON"
        }
    }
}
