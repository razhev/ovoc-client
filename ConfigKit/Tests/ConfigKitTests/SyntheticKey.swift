import Foundation
@testable import ConfigKit

/// Синтезатор ключей vpn:// для тестов: JSON → qCompress → base64url → vpn://.
/// Реальный ключ пользователя в тесты НЕ попадает никогда — только вот такие
/// собранные на месте.
enum SyntheticKey {

    /// Профиль в духе server_scripts/openvpn_cloak/template.ovpn:
    /// DNS-плейсхолдеры + route net_gateway + remote 127.0.0.1 + инлайн-сертификаты.
    static let sampleOVPN = """
    client
    dev tun
    proto tcp
    resolv-retry infinite
    nobind
    persist-key
    persist-tun
    cipher AES-256-GCM
    auth SHA512
    verb 3
    tls-client
    redirect-gateway def1 bypass-dhcp

    dhcp-option DNS $PRIMARY_DNS
    dhcp-option DNS $SECONDARY_DNS

    route 203.0.113.10 255.255.255.255 net_gateway
    remote 127.0.0.1 1194

    <ca>
    -----BEGIN CERTIFICATE-----
    FAKE+CA/BASE64==
    -----END CERTIFICATE-----
    </ca>
    <cert>
    -----BEGIN CERTIFICATE-----
    FAKE+CERT/BASE64==
    -----END CERTIFICATE-----
    </cert>
    <key>
    -----BEGIN PRIVATE KEY-----
    FAKE+KEY/BASE64==
    -----END PRIVATE KEY-----
    </key>
    <tls-auth>
    -----BEGIN OpenVPN Static key V1-----
    00112233445566778899aabbccddeeff
    -----END OpenVPN Static key V1-----
    </tls-auth>
    """

    /// Тот же профиль, но без плейсхолдеров DNS и без строки route.
    static let sampleOVPNNoPlaceholdersNoRoute = """
    client
    dev tun
    proto tcp
    redirect-gateway def1 bypass-dhcp
    dhcp-option DNS 9.9.9.9
    remote 127.0.0.1 1194

    <ca>
    -----BEGIN CERTIFICATE-----
    FAKE+CA/BASE64==
    -----END CERTIFICATE-----
    </ca>
    """

    /// Содержимое cloak.last_config — поля как в cloak_configurator.cpp.
    static func cloakLastConfig(
        numConn: Any = 4,
        streamTimeout: Any = 300,
        extra: [String: Any] = [:],
        removeKeys: [String] = []
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "Transport": "direct",
            "ProxyMethod": "openvpn",
            "EncryptionMethod": "aes-gcm",
            "UID": "dGVzdC11aWQ=",
            "PublicKey": "cHVibGljK2tleQ==",
            "ServerName": "example-mask.com",
            "NumConn": numConn,
            "BrowserSig": "chrome",
            "StreamTimeout": streamTimeout,
            "RemoteHost": "203.0.113.10",
            "RemotePort": "8443",
        ]
        for (key, value) in extra { dict[key] = value }
        for key in removeKeys { dict.removeValue(forKey: key) }
        return dict
    }

    /// Верхнеуровневый JSON ключа (структура exportController.cpp).
    static func serverJSON(
        hostName: String = "203.0.113.10",
        description: String = "Test Server",
        dns1: String? = "10.11.12.13",
        dns2: String? = "10.11.12.14",
        defaultContainer: String? = "amnezia-openvpn-cloak",
        containers: [[String: Any]]? = nil,
        ovpnText: String = sampleOVPN,
        cloakLast: [String: Any]? = nil,
        cloakSiblings: [String: Any] = ["port": "443", "transport_proto": "tcp"]
    ) -> [String: Any] {
        var json: [String: Any] = [
            "hostName": hostName,
            "description": description,
            "containers": containers ?? [
                cloakContainer(ovpnText: ovpnText, cloakLast: cloakLast, cloakSiblings: cloakSiblings)
            ],
        ]
        if let dns1 { json["dns1"] = dns1 }
        if let dns2 { json["dns2"] = dns2 }
        if let defaultContainer { json["defaultContainer"] = defaultContainer }
        return json
    }

    static func cloakContainer(
        ovpnText: String = sampleOVPN,
        cloakLast: [String: Any]? = nil,
        cloakSiblings: [String: Any] = ["port": "443", "transport_proto": "tcp"]
    ) -> [String: Any] {
        var cloakSection: [String: Any] = [
            "last_config": jsonString(cloakLast ?? cloakLastConfig())
        ]
        for (key, value) in cloakSiblings { cloakSection[key] = value }
        return [
            "container": "amnezia-openvpn-cloak",
            "openvpn": ["last_config": jsonString(["config": ovpnText, "clientId": "test-client"])],
            "cloak": cloakSection,
        ]
    }

    static func jsonString(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    static func key(from json: [String: Any], compressed: Bool = true) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: json)
        let payload = compressed ? try qCompress(data, level: 8) : data
        return "vpn://" + base64url(payload)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Достаёт словарь Cloak из блока <cloak> собранного профиля.
    static func cloakDict(fromProfile profile: String) throws -> [String: Any] {
        guard let start = profile.range(of: "<cloak>\n"),
              let end = profile.range(of: "\n</cloak>") else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "нет блока <cloak>"])
        }
        let base64 = String(profile[start.upperBound..<end.lowerBound])
        guard let data = Data(base64Encoded: base64) else {
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "битый base64 в <cloak>"])
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
