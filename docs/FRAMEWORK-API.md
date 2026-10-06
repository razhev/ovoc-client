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

Эта таблица описывает исходный бинарник, по которому исследовался API. В приложении
используется сборка из исходников с исправлением AEAD (`make framework`).
`make verify` проверяет arm64, символы Cloak, API и квитанцию
`Frameworks/OpenVPNAdapter.build.json`: коммиты, хэш текущего патча и хэш бинарника.
Без квитанции или при несовпадении требуется пересборка. Готовый `v1.0.42` проверку не проходит;
`make fetch` сохраняет его только в `build/cache/prebuilt-v1.0.42` для сравнения.

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

Что эти методы делают в ядре (`OpenVPN3/openvpn/client/cliconnect.hpp`, проверено по исходникам
сборки `make framework`):

| Метод | Ядро | События |
|---|---|---|
| `reconnect(afterTimeInterval: n)` | таймер n сек → `new_client()`: старая сессия останавливается, tun разбирается (`tun_builder_teardown` → `resetTun` → наш `configureTunnel(nil)`), новая сессия собирает tun заново из свежего PUSH_REPLY | `RECONNECTING` → … → `CONNECTED` |
| `pause(withReason:)` | сессия останавливается с разборкой tun адаптера; системные маршруты сохраняет наш провайдер, io_context живёт | `PAUSE` |
| `resume()` | `new_client()` — полное рукопожатие заново | `RESUME`, `RECONNECTING` → `CONNECTED` |
| `disconnect()` | `graceful_stop()`: explicit-exit-notify, стоп | `DISCONNECTED` |

На iOS у ядра **нет** объекта lifecycle (есть только `MacLifeCycle` для macOS): сон, пробуждение
и смену интерфейса оно не видит; переподключается только по ошибке транспорта либо по тишине
(`ping` / `ping-restart` с сервера). Смена сети — забота провайдера.

## OpenVPNReachability

```swift
let reachability = OpenVPNReachability()                 // SCNetworkReachability (internet + wifi)
reachability.reachabilityStatus                          // .notReachable / .reachableViaWiFi / .reachableViaWWAN
reachability.isTracking
reachability.startTracking { (status: OpenVPNReachabilityStatus) in … }  // колбэк — на главном run loop
reachability.stopTracking()
```
Планирование/отмена трекера уходят на главную очередь через `dispatch_async`; колбэк приходит
из `SCNetworkReachability` на главном run loop расширения. С 2026-10-06 провайдер этот класс
не использует: сеть отслеживает `NWPathMonitor` на `stateQueue`. `NetworkPathSnapshot` сравнивает
доступность, физический интерфейс и его адреса, игнорируя виртуальные интерфейсы и изменения
наших DNS/маршрутов. При наличии IPv4 смена временного IPv6-адреса не считается сменой сети.
Переход между Wi-Fi с одинаковыми адресами может не изменить снимок; остановку трафика
проверяет отдельная проба. Решение о reconnect принимает `ReconnectCoordinator`.

## OpenVPNAdapterDelegate (точные Swift-сигнатуры)

```swift
func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter,
                    configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
                    completionHandler: @escaping (Error?) -> Void)
// networkSettings == nil означает «очистить настройки». Приходит из resetTun адаптера:
// перед каждым подключением (tun_builder_new) и при разборке tun (tun_builder_teardown,
// в том числе после stopTunnel). Ошибка в completion → ФАТАЛЬНАЯ #20
// OpenVPNAdapterErrorTUNSetupFailed с системной ошибкой в NSUnderlyingErrorKey.
// На resetTun ВСЕГДА отвечаем completionHandler(nil), НЕ вызывая
// setTunnelNetworkSettings(nil): иначе при reconnect исчезнут маршруты и DNS
// и появится окно трафика мимо VPN. resetTun может прийти ДО RECONNECTING,
// поэтому решение не зависит от reasserting или счётчика reconnect.
// Новые настройки заменяют старые напрямую; при окончательном завершении
// провайдера системный интерфейс и маршруты снимает iOS.
// Мы: дополняем settings (matchDomains, excludedRoutes, DNS-fallback,
//     IPv6-раковина при отсутствии ipv6Settings) →
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

Нам важны: `.connected` (начать проверку трафика), `.disconnected` (завершить стоп либо
разрешить замену адаптера), `.reconnecting` (подтвердить начало попытки). После `.connected`
завершаем системный старт и снимаем `reasserting` **до** проверки через виртуальный интерфейс.
Проверка подтверждает здоровье сессии отдельно, сохраняя дедлайн и бюджет восстановления.

## Ошибки

```objc
NSString *const OpenVPNAdapterErrorDomain;
NSString *const OpenVPNIdentityErrorDomain;
NSString *const OpenVPNAdapterErrorFatalKey;    // NSNumber(bool) в userInfo
NSString *const OpenVPNAdapterErrorMessageKey;  // текст OpenVPN в userInfo
```
Плюс enum `OpenVPNAdapterError` (~78 кодов) — в лог пишем дословно domain/code/message.

## OpenVPNAdapterPacketFlow

Протокол повторяет два метода `NEPacketTunnelFlow`
(`readPackets(completionHandler:)` / `writePackets(_:withProtocols:)`). Наш
`PacketFlowBridge` выдаёт каждому адаптеру отдельный `AdapterFlow` и сохраняет единый
`PacketReadPump`: в исходниках фреймворка каждый `establishTunnel` вызывает `startReading`,
а прежняя рекурсивная цепочка чтения не отменяется. Pump держит только один системный read
и последний callback. Поколение не позволяет старому адаптеру заново читать после замены.
**Фреймворк хранит packetFlow слабо** — провайдер удерживает `adapterFlow` весь срок работы.
Мост считает пакеты, диагностирует
петлю маршрутов и отбрасывает IPv6 только в режиме раковины. Когда сервер выдал
IPv6-настройки, IPv6 проходит в адаптер. Режим обновляется после успешного
применения новых настроек, до completion делегата.

## Схема работы провайдера (следствие API)

```
startTunnel:
  cfg.fileContent = ovpnText.data(using: .utf8)   // текст уже содержит <cloak>
  // cfg.tunPersist остаётся false: внутренний tun адаптера пересоздаётся
  cfg.setPTCloak()
  try adapter.apply(configuration: cfg)           // ошибки — дословно в лог
  запустить сторожевой таймер 30 сек
  запустить NWPathMonitor и ReconnectCoordinator
  удержать packetBridge.makeAdapterFlow() в adapterFlow (у фреймворка weak-ссылка)
  adapter.connect(using: adapterFlow)

делегат configureTunnel...:
  networkSettings == nil → completion(nil), системные маршруты и DNS остаются
  phase не starting/connected → отказ применять запоздавшие настройки
  networkSettings.dnsSettings.matchDomains = [""]
  добавить NEIPv4Route(serverIP /32) в excludedRoutes   // tunnelRemoteAddress будет 127.0.0.1!
  DNS-fallback: адаптер → dhcp-option DNS из конфига → dns1/dns2
  ipv6Settings == nil → NEIPv6Settings(fd00:6f76:6f63::2/64) + NEIPv6Route.default()  // раковина
  setTunnelNetworkSettings(...) { completionHandler($0) }

handleEvent .connected → completion(nil) старта / reasserting=false → проверка трафика через туннель
смена/потеря сети → reasserting=true сразу; без сети ждём, при наличии объединяем изменения за 2 с
reconnect → дедлайн 30 с, включающий рукопожатие и проверку трафика; задержки повтора 5/10 с
третья попытка → disconnect → ждём DISCONNECTED до 5 с → новый адаптер; зависший stop → ошибка
handleEvent .reconnecting → не продлевает дедлайн уже начатой попытки
15 с исходящих пакетов без входящих → контрольная проба; отсутствие трафика само по себе не ошибка
handleError fatal      → last_error.txt + cancelTunnelWithError (только в фазах starting/connected;
                         во время стопа — только строка в логе)
stopTunnel             → adapter.disconnect() + страховочный таймер 5 сек
```

Проверка трафика — UDP DNS-запрос `NS .` к двум (если доступны) DNS-серверам текущих настроек,
последовательно, до 4 с на каждый. Имена посещаемых сайтов не передаются. Проверяются ID и
вопрос в ответе; DNS-ошибка тоже подтверждает двустороннюю передачу. iOS 18+: `NWConnection`
с `requiredInterface = provider.virtualInterface`; iOS 16–17: `createUDPSessionThroughTunnel`.
IP транспорта исключён из целей пробы, IPv6 не используется при включённой IPv6-раковине.
Входящий пакет, успешно переданный в системный поток после начала текущей проверки, тоже
подтверждает работоспособность; неудача отдельного DNS-запроса не должна разрывать рабочий VPN.
Без свежего входящего трафика и ответа DNS проверка неуспешна. Короткие wake с недавним
входящим трафиком не запускают лишние пробы.

По логам устройства от 2026-10-06 ядро иногда перестаёт обрабатывать и reconnect, и stop
после потери сети. В таком случае Swift завершает сессию с ошибкой после ограниченного
восстановления; перезапуск зависшего процесса через VPN On Demand в эту реализацию не входит.
