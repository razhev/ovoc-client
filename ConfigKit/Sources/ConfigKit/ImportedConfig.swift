import Foundation

/// Итог импорта: всё, что нужно расширению, в готовом виде.
/// Приложение кладёт это в providerConfiguration профиля туннеля — и больше
/// никуда: профиль содержит приватный ключ, вторая копия на диске не нужна.
public struct ImportedConfig: Codable, Equatable {
    /// Полный текст .ovpn: DNS подставлен, route для IP сервера гарантирован,
    /// блок <cloak> дописан.
    public let ovpnProfile: String
    /// Фактический IPv4 Cloak — одновременно для RemoteHost и excludedRoutes.
    /// Если endpoint был доменом, адрес зафиксирован в момент импорта.
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
        try make(from: VPNKeyDecoder.decode(key), resolve: resolve)
    }

    /// То же для текста, вставленного человеком: ключ внутри сообщения, с
    /// переносами строк и т.п. — см. `VPNKeyDecoder.decode(pastedText:)`.
    /// Этим входом пользуется экран импорта.
    public static func make(
        fromPastedText text: String,
        resolve: (String) throws -> String = ImportedConfig.systemResolveIPv4
    ) throws -> ImportedConfig {
        try make(from: VPNKeyDecoder.decode(pastedText: text), resolve: resolve)
    }

    private static func make(
        from config: AmneziaConfig,
        resolve: (String) throws -> String
    ) throws -> ImportedConfig {
        let container = try config.cloakContainer()

        guard let openvpn = container.openvpn else {
            throw VPNKeyError.missingField("openvpn")
        }
        guard let cloak = container.cloak else {
            throw VPNKeyError.missingField("cloak")
        }

        let ovpnText = try openvpn.ovpnConfigText()
        var cloakFields = try cloak.effectiveFields()

        // Значения по умолчанию — как в docs/history/PLAN.md.
        let dns1 = config.dns1?.isEmpty == false ? config.dns1! : "1.1.1.1"
        let dns2 = config.dns2?.isEmpty == false ? config.dns2! : "1.0.0.1"

        // Cloak может подключаться к remote/RemoteHost, отличному от hostName.
        // Разрешаем именно его и фиксируем один IPv4 в транспорте и маршруте:
        // повторный DNS в Go мог бы выбрать другой адрес и создать петлю.
        let remoteHost = CloakTransform.remoteHost(fields: cloakFields, hostName: config.hostName)
        let serverIP: String
        if isIPv4Literal(remoteHost) {
            serverIP = remoteHost
        } else {
            let resolved = try resolve(remoteHost)
            guard isIPv4Literal(resolved) else {
                throw VPNKeyError.notAnIPv4(remoteHost)
            }
            serverIP = resolved
        }

        cloakFields["remote"] = .string(serverIP)
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
