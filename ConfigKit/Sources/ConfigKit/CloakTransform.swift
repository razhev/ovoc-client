import Foundation

/// Приведение Cloak-конфига к виду, который ждёт Go-часть внутри фреймворка.
/// Порт setupCloak() из ios_controller.mm (amnezia-client, тег 4.8.21.0).
public enum CloakTransform {
    /// Тот же порядок приоритетов для подключения и для маршрута-исключения.
    static func remoteHost(fields: [String: JSONValue], hostName: String) -> String {
        for key in ["remote", "RemoteHost"] {
            if let host = fields[key]?.asString, !host.isEmpty { return host }
        }
        return hostName
    }

    /// Итоговый JSON для блока <cloak> в профиле.
    ///
    /// Правила (менять нельзя — по ним работает Go json.Unmarshal на той стороне):
    /// - NumConn = 1 принудительно (числом) — защита лимита памяти расширения 50 МБ;
    /// - remote → RemoteHost, port → RemotePort; сами remote/port/transport_proto удаляются;
    /// - ТИПЫ: только NumConn и StreamTimeout — числа; все остальные значения — строки
    ///   (UID/PublicKey остаются base64-строками как есть). "StreamTimeout":"300"
    ///   строкой сломал бы разбор на стороне Go — поэтому приводим к числу.
    public static func makeCloakJSON(fields: [String: JSONValue], hostName: String) throws -> Data {
        var dict = fields

        dict["NumConn"] = .number(1)
        dict["RemoteHost"] = .string(remoteHost(fields: fields, hostName: hostName))
        if let port = dict["port"]?.asString, !port.isEmpty {
            dict["RemotePort"] = .string(port)
        }
        dict.removeValue(forKey: "remote")
        dict.removeValue(forKey: "port")
        dict.removeValue(forKey: "transport_proto")

        var out: [String: Any] = [:]
        for (key, value) in dict {
            if key == "NumConn" || key == "StreamTimeout" {
                // Значение по умолчанию 300 — как в cloak_configurator.cpp.
                out[key] = value.asInt ?? 300
            } else if let string = value.asString {
                out[key] = string
            }
            // Не-скалярные значения (вложенные объекты/массивы) Cloak-конфигу
            // не свойственны — молча пропускаем, чтобы не сломать Go-разбор.
        }

        return try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    }
}
