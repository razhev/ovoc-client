import Foundation

/// Итог импорта: всё, что нужно расширению, в готовом виде.
/// Приложение сохраняет это в App Group (config.json) и кладёт
/// в providerConfiguration профиля туннеля.
public struct ImportedConfig: Codable, Equatable {
    /// Полный текст .ovpn: DNS подставлен, route для IP сервера гарантирован,
    /// блок <cloak> дописан.
    public let ovpnProfile: String
    /// IPv4 сервера — для excludedRoutes (если hostName был доменом,
    /// адрес разрешён и зафиксирован в момент импорта).
    public let serverIP: String
    public let dns1: String
    public let dns2: String
    public let description: String

    public init(ovpnProfile: String, serverIP: String, dns1: String, dns2: String, description: String) {
        self.ovpnProfile = ovpnProfile
        self.serverIP = serverIP
        self.dns1 = dns1
        self.dns2 = dns2
        self.description = description
    }

    /// Полный конвейер импорта: ключ vpn:// → готовый конфиг.
    /// - Parameter resolve: резолвер домена в IPv4. Инжектируется, чтобы тесты
    ///   работали без сети; приложение использует `systemResolveIPv4`.
    public static func make(
        fromKey key: String,
        resolve: (String) throws -> String = ImportedConfig.systemResolveIPv4
    ) throws -> ImportedConfig {
        let config = try VPNKeyDecoder.decode(key)
        let container = try config.cloakContainer()

        guard let openvpn = container.openvpn else {
            throw VPNKeyError.missingField("openvpn")
        }
        guard let cloak = container.cloak else {
            throw VPNKeyError.missingField("cloak")
        }

        let ovpnText = try openvpn.ovpnConfigText()
        let cloakFields = try cloak.effectiveFields()

        // Значения по умолчанию — как в PLAN.md.
        let dns1 = config.dns1?.isEmpty == false ? config.dns1! : "1.1.1.1"
        let dns2 = config.dns2?.isEmpty == false ? config.dns2! : "1.0.0.1"

        // Для маршрутов нужен именно IPv4-литерал; RemoteHost в Cloak-конфиге
        // при этом остаётся исходным hostName (Go-сторона резолвит его сама).
        let serverIP: String
        if isIPv4Literal(config.hostName) {
            serverIP = config.hostName
        } else {
            let resolved = try resolve(config.hostName)
            guard isIPv4Literal(resolved) else {
                throw VPNKeyError.notAnIPv4(config.hostName)
            }
            serverIP = resolved
        }

        let cloakJSON = try CloakTransform.makeCloakJSON(fields: cloakFields, hostName: config.hostName)
        let profile = OVPNProfileBuilder.build(
            ovpnText: ovpnText,
            serverIP: serverIP,
            dns1: dns1,
            dns2: dns2,
            cloakJSON: cloakJSON
        )

        return ImportedConfig(
            ovpnProfile: profile,
            serverIP: serverIP,
            dns1: dns1,
            dns2: dns2,
            description: config.description ?? config.hostName
        )
    }

    // MARK: - Сохранение (App Group)

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> ImportedConfig {
        try JSONDecoder().decode(ImportedConfig.self, from: Data(contentsOf: url))
    }

    // MARK: - DNS

    public static func isIPv4Literal(_ string: String) -> Bool {
        var addr = in_addr()
        return string.withCString { inet_pton(AF_INET, $0, &addr) } == 1
    }

    /// Синхронный резолв A-записи через getaddrinfo (работает и на macOS).
    public static func systemResolveIPv4(_ host: String) throws -> String {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
            ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        defer { if result != nil { freeaddrinfo(result) } }

        guard status == 0, let first = result else {
            throw VPNKeyError.notAnIPv4(host)
        }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            if info.pointee.ai_family == AF_INET, let sockaddr = info.pointee.ai_addr {
                var addr = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    return String(cString: buffer)
                }
            }
            current = info.pointee.ai_next
        }
        throw VPNKeyError.notAnIPv4(host)
    }
}
