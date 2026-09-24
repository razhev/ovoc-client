# OpenVPNAdapter.framework — зафиксированный API

> Источник правды для кода `PacketTunnelProvider`. Всё ниже выписано из **реальных
> заголовков** скачанного бинаря (не из блогов и не по памяти). При смене
> фреймворка (другой релиз / сборка из исходников) — перепроверить и обновить.

## Происхождение бинаря

| | |
|---|---|
| Источник | `https://github.com/amnezia-vpn/3rd-build-ga/releases/download/v1.0.42/openvpnadapter.zip` |
| SHA-256 архива | `c6d6b3f745265771bdcb4bcdebb3ff5e39fe4bfee54958a86b5d3229f1151c10` (зафиксирован в `scripts/fetch-framework.sh`) |
| Внутри архива | `openvpnadapter/ios/` и `openvpnadapter/macos/` — берём **строго ios/** (macOS-вариант — fat x86_64+arm64 и не подходит) |
| Версия фреймворка | 0.8.0 (CFBundleShortVersionString), собран ~февраль 2025 |
| Архитектура | arm64 only, `LC_VERSION_MIN_IPHONEOS`: minos 10.0, SDK 17.5 |
| Символы Cloak | `Cloak_dial`, `Initialize_cloak_c_client` — присутствуют (`nm -gU`) |

Ворота проверки: `make verify` (три PASS обязательны перед любой интеграцией).

## Главное отличие от upstream (ss-abramchuk)

1. **`setPTCloak` — метод БЕЗ аргументов**: `- (void)setPTCloak;` (Swift: `setPTCloak()`).
   Он лишь переключает транспорт OpenVPN3 на Cloak. Сами настройки Cloak фреймворк
   читает **только из блока `<cloak>base64(JSON)</cloak>` внутри текста профиля**
   (`fileContent`). Никакого отдельного параметра с конфигом нет.
2. **Completion делегата `configureTunnelWithNetworkSettings` принимает `NSError?`,
   а НЕ `OpenVPNAdapterPacketFlow?`** (в upstream — packetFlow). Поток пакетов
   передаётся один раз в `connect(using:)`.

## OpenVPNConfiguration (используемое нами подмножество)

```objc
@property (nullable, nonatomic) NSData *fileContent;   // текст .ovpn как Data (не String!)
@property (nonatomic) BOOL tunPersist;                 // держать tun при переподключениях
- (void)setPTCloak;                                    // включить Cloak-транспорт
```

Прочее доступное (не используем в v1, но знать полезно): `settings` (профиль
парами ключ/значение), `server`/`port`/`proto` (переопределение remote),
`connectionTimeout`, `clockTick`, `tlsCertProfile`, `minTLSVersion`.

## OpenVPNAdapter

```swift
let adapter = OpenVPNAdapter()
adapter.delegate = self                                            // weak
let eval = try adapter.apply(configuration: cfg)                   // до connect; бросает NSError
adapter.connect(using: packetFlow)                                 // id<OpenVPNAdapterPacketFlow>
adapter.disconnect()
adapter.pause(withReason:) / adapter.resume()
adapter.reconnect(afterTimeInterval:)
// readonly: sessionName, connectionInformation, interfaceStatistics, transportStatistics
```

## OpenVPNAdapterDelegate (точные Swift-сигнатуры)

```swift
func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter,
                    configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
                    completionHandler: @escaping (Error?) -> Void)
// networkSettings == nil означает «очистить настройки». Приходит из resetTun адаптера:
// перед каждым подключением (tun_builder_new) и при разборке tun (tun_builder_teardown,
// в том числе после stopTunnel). Ошибка в completion → ФАТАЛЬНАЯ #20
// OpenVPNAdapterErrorTUNSetupFailed с системной ошибкой в NSUnderlyingErrorKey.
// Во время остановки setTunnelNetworkSettings(nil) у iOS проваливается —
// мы отвечаем nil, иначе штатное отключение выглядит как фатальная ошибка.
// Мы: дополняем settings (matchDomains, excludedRoutes, DNS-fallback) →
//     setTunnelNetworkSettings(networkSettings) { completionHandler($0) }

func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter,
                    handleEvent event: OpenVPNAdapterEvent, message: String?)

func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error)
// фатальность: (error as NSError).userInfo[OpenVPNAdapterErrorFatalKey] as? Bool == true

// @optional
func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logMessage: String)
func openVPNAdapterDidReceiveClockTick(_ openVPNAdapter: OpenVPNAdapter)
```

## OpenVPNAdapterEvent (полный список)

`disconnected, connected, reconnecting, authPending, resolve, wait, waitProxy,
connecting, getConfig, assignIP, addRoutes, echo, info, warn, pause, resume,
relay, compressionEnabled, unsupportedFeature, unknown`

Нам важны: `.connected` (снять сторожевой таймер, завершить старт),
`.disconnected` (завершить стоп / cancelTunnelWithError), `.reconnecting` (лог).

## Ошибки

```objc
NSString *const OpenVPNAdapterErrorDomain;
NSString *const OpenVPNIdentityErrorDomain;
NSString *const OpenVPNAdapterErrorFatalKey;    // NSNumber(bool) в userInfo
NSString *const OpenVPNAdapterErrorMessageKey;  // текст OpenVPN в userInfo
```
Плюс enum `OpenVPNAdapterError` (~78 кодов) — в лог пишем дословно domain/code/message.

## OpenVPNAdapterPacketFlow

Протокол в точности повторяет два метода `NEPacketTunnelFlow`
(`readPackets(completionHandler:)` / `writePackets(_:withProtocols:)`), поэтому мост —
пустое расширение:

```swift
extension NEPacketTunnelFlow: OpenVPNAdapterPacketFlow {}
```

## Схема работы провайдера (следствие API)

```
startTunnel:
  cfg.fileContent = ovpnText.data(using: .utf8)   // текст уже содержит <cloak>
  cfg.tunPersist = true
  cfg.setPTCloak()
  try adapter.apply(configuration: cfg)           // ошибки — дословно в лог
  запустить сторожевой таймер 30 сек
  adapter.connect(using: packetFlow)

делегат configureTunnel...:
  networkSettings.dnsSettings.matchDomains = [""]
  добавить NEIPv4Route(serverIP /32) в excludedRoutes   // tunnelRemoteAddress будет 127.0.0.1!
  DNS-fallback: адаптер → dhcp-option DNS из конфига → dns1/dns2
  setTunnelNetworkSettings(...) { completionHandler($0) }

handleEvent .connected → снять таймер, completionHandler(nil) старта
handleError fatal      → last_error.txt + cancelTunnelWithError (только в фазах starting/connected;
                         во время стопа — только строка в логе)
stopTunnel             → adapter.disconnect() + страховочный таймер 5 сек
```
