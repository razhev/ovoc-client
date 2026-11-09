# План имплементации: OVoC Client (iOS-клиент OpenVPN over Cloak)

> Детализация исходного плана с последующими уточнениями. Датированные результаты ниже
> описывают соответствующие этапы; текущее состояние — в [PLAN.md](PLAN.md) и
> [CHANGELOG.md](../../CHANGELOG.md). IMPLEMENTATION_PROMPT.md сохранён как исторический документ.

## Контекст

Строим минимальный нативный iOS VPN-клиент к личному серверу AmneziaVPN (OpenVPN over Cloak) для себя и 3–5 родственников, раздача через TestFlight. Архитектура: SwiftUI-приложение + одно расширение `NEPacketTunnelProvider`, `OpenVPNAdapter.framework`, собираемый из зафиксированных исходников Amnezia с локальными исправлениями (Cloak вшит внутрь OpenVPN3), вся логика разбора ключа `vpn://` — в тестируемом на Mac SPM-пакете `ConfigKit`. Проект генерируется XcodeGen, вся сборка — CLI.

**Состояние окружения (проверено 2026-08-20):**
- Xcode 26.2 (17C52) ✅ — соответствует требованию Apple для TestFlight
- xcodegen, go, gh ✅; `gh auth status` — залогинен как razhev ✅
- `security find-identity` → **0 valid identities** — Apple Developer аккаунт ещё не одобрен/не подключён ⚠️
- Репозиторий: только PLAN.md, README.md, IMPLEMENTATION_PROMPT.md, .gitignore (секреты/фреймворки/xcodeproj уже закрыты). Кода нет — дублирования не будет.

Из-за отсутствия identities всё, что требует подписи и устройства, вынесено после **Фазы 0**, которую можно выполнить целиком прямо сейчас.

---

## Обзор фаз

| Фаза | Что делаем | Нужен аккаунт/телефон? | Ворота (без прохождения — дальше нельзя) |
|---|---|---|---|
| **0** | project.yml + скелеты таргетов (компиляция без подписи), весь ConfigKit + тесты, скрипты fetch/verify фреймворка, decode-vpnkey.py, Makefile, README | **Нет** | `swift test` зелёный; `xcodebuild` без подписи собирается; `verify-framework.sh` — 3 PASS; сигнатура `setPTCloak` зафиксирована |
| **0.5** (опц., пока ждём Apple) | Подключение фреймворка compile-only + полный код `PacketTunnelProvider` по реальным заголовкам | **Нет** | Оба таргета компилируются с фреймворком без подписи |
| **M1** | Подписи, установка на iPhone, пустышка-туннель | **Да** | Настройки → VPN: «Подключено» (значок VPN — в Пункте управления); логи расширения видны в LogView |
| **M2** | Фреймворк загружается в процессе расширения на устройстве | Да | «OpenVPNAdapter loaded» в логе; пустышка по-прежнему работает |
| **M3** | Настоящее соединение на зашитом конфиге (главный риск) | Да + реальный ключ | Сайт-определитель показывает IP сервера; 10 мин стабильно; чистый reconnect |
| **M4** | Импорт `vpn://` в приложении (без вшитого ключа) | Да | Чистая установка + вставка ключа воспроизводит M3 |
| **M5** | Доводка: ошибки под кнопкой, шаринг логов, ru/en, иконка | Да | Телефон на русском → интерфейс русский; мёртвый сервер → читаемая ошибка |
| **M6** | TestFlight: архив, загрузка, внешняя группа, публичная ссылка | Да + App Store Connect | Родственник ставит по ссылке и видит IP сервера |

---

## Фаза 0 — всё, что не требует подписи и устройства (агент, можно сейчас)

### Шаг 0.1 — Каркас проекта: `project.yml`, скелеты таргетов, Makefile

> Имена ниже — текущие. До переименования 2026-09-24 проект, таргет и приложение назывались
> PersonalVPN, bundle ID — `com.razhev.personalvpn`.

**Файлы:**

- **`project.yml`** — единый источник правды для XcodeGen:
  - `options`: `deploymentTarget: iOS "16.0"`
  - общие settings: `SWIFT_VERSION: "5.0"`, `SUPPORTED_PLATFORMS: iphoneos`, `TARGETED_DEVICE_FAMILY: 1`, `DEVELOPMENT_TEAM: ""` (плейсхолдер до M0), `CODE_SIGN_STYLE: Automatic`, `ITSAppUsesNonExemptEncryption: false` в Info.plist приложения
  - target **OVoCClient** (iOS app, bundle `com.razhev.ovocclient`, видимое имя «OVoC Client»): sources `App/` + `Shared/`, зависимость от таргета PacketTunnel (embed appex), пакет ConfigKit, entitlements-файл `App/OVoCClient.entitlements`
  - target **PacketTunnel** (app-extension, bundle `com.razhev.ovocclient.tunnel`): sources `PacketTunnel/` + `Shared/`, `NSExtensionPointIdentifier: com.apple.networkextension.packet-tunnel`, entitlements `PacketTunnel/PacketTunnel.entitlements`
  - фреймворк в project.yml **не** подключаем на этом шаге (он появится в 0.5/M2) — иначе сборка упадёт до его скачивания

  *Пояснение для новичка: entitlements — это подписанные «разрешения» приложения (право на VPN, право на общую папку). App Group — общая папка двух процессов (приложение ↔ расширение): через неё ходят логи и конфиг.*

- **Entitlements** (оба таргета, одинаковые по смыслу):
  - `com.apple.developer.networking.networkextension` = `[packet-tunnel-provider]`
  - `com.apple.security.application-groups` = `[group.com.razhev.ovocclient]`

- **`Shared/SharedPaths.swift`** — `enum SharedPaths`: `appGroupID`, `containerURL`, `logFileURL` (`tunnel.log`), `lastErrorURL` (`last_error.txt`), `configURL` (`config.json`).
- **`Shared/TunnelIPC.swift`** — `enum TunnelConfigKeys`: строковые ключи `ovpnConfig`, `serverIP`, `dns1`, `dns2` для `providerConfiguration`.
- **`App/OVoCClientApp.swift`**, **`App/ContentView.swift`** — минимальный SwiftUI: кнопка «Подключить» (пока без действия), текст статуса. `Assets.xcassets` с плейсхолдером.
- **`PacketTunnel/PacketTunnelProvider.swift`** — скелет: `startTunnel` поднимает **пустышку** (`NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.8.0.1")`, адрес `10.8.0.2/24`, `includedRoutes = [NEIPv4Route(dest: "10.8.0.0", mask: "255.255.255.0")]` — **узкий маршрут, НИКОГДА не default route**), пишет строку в лог App Group. Это ровно то, что нужно для M1 — пишем сразу.
- **`Shared/RingLogger.swift`** (с M1 — в `Shared/`: расширение пишет `tunnel.log`, приложение — `app.log`) — `final class RingLogger`: `init(fileURL:maxBytes:category:)` (лимит ~256 КБ, ротация усечением половины), `func log(_:)` (файл + `os.Logger` subsystem `com.razhev.ovocclient`, уровень `.notice`), `func startMemoryHeartbeat()` — раз в 30 сек строка с footprint из `task_vm_info` (следим за лимитом 50 МБ).
- **`Makefile`** — цели: `gen` (xcodegen), `build` (см. проверку ниже), `test` (`cd ConfigKit && swift test`), `fetch` / `verify` (скрипты фреймворка), позже `install` / `archive` / `upload` / `logs`.

**Команды/проверка:**
```
xcodegen generate
xcodebuild -project OVoCClient.xcodeproj -scheme OVoCClient \
  -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```
Ожидаем: `BUILD SUCCEEDED` — оба таргета компилируются и линкуются без подписи. Это доказывает корректность project.yml до появления аккаунта.

**Действует:** агент. Пользователь — никто.

### Шаг 0.2 — Скрипты фреймворка + фиксация API (критический шаг фазы)

**Файлы:**

- **`scripts/fetch-framework.sh`**:
  - `curl -L` → `https://github.com/amnezia-vpn/3rd-build-ga/releases/download/v1.0.42/openvpnadapter.zip` в кэш
  - переменная `EXPECTED_SHA256`: при первом запуске пустая → скрипт печатает вычисленный хэш и требует вписать его в скрипт (фиксация); при последующих — сравнивает и падает при расхождении
  - распаковка в `build/cache/prebuilt-v1.0.42/OpenVPNAdapter.framework` только для сравнения;
    рабочий бинарник приложения не перезаписывается
  - закомментированный запасной источник: repo `3rd-prebuilt`, ветка `feature/special-handshake`, путь `openvpn/apple/OpenVPNAdapter-ios/OpenVPNAdapter.framework`
- **`scripts/verify-framework.sh`** — проверки с явным PASS/FAIL и ненулевым exit при провале:
  1. `lipo -info` бинаря → **только** arm64;
  2. `nm -gU` → есть `Cloak_dial` и `Initialize_cloak_c_client`;
  3. `grep -r setPTCloak Frameworks/OpenVPNAdapter.framework/Headers/` → найден; скрипт **печатает полную строку объявления**.
  4. `framework-provenance.py` сверяет квитанцию сборки: закреплённые коммиты, SHA-256 патча и бинарника.
- **`scripts/build-framework-source.sh`** — основной путь: закреплённые исходники адаптера и OpenVPN3,
  AEAD-патч, прежняя закреплённая Go-библиотека Cloak, xcodebuild framework-таргета, privacy manifest и квитанция сборки. Новые транспортные патчи сборки 8 откачены в сборке 9.
  Готовый `v1.0.42` неработоспособен, поэтому собирать из исходников обязательно.

**Команды/проверка:** `make framework && make verify`. Затем **читаем реальные заголовки** и фиксируем в `docs/FRAMEWORK-API.md`:
- точную сигнатуру `setPTCloak` (свойство/метод, тип аргумента);
- сигнатуру делегата `configureTunnelWithNetworkSettings` и **тип completion** (форк менял API в марте 2026 — код провайдера пишем только по этим заголовкам, не по памяти);
- имена событий/ошибок (`OpenVPNAdapterEvent`, `OpenVPNAdapterErrorFatalKey`).

Если проверка провалилась, пересобираем `make framework`. Проверка запускается также
перед build/install/release-check/testflight; `RELEASE_CHECK=0` её не отключает.

**Действует:** агент.

### Шаг 0.3 — `ConfigKit`: пакет целиком + юнит-тесты

**Файлы (`ConfigKit/`):**

- **`Package.swift`** — platforms `[.iOS(.v16), .macOS(.v13)]`, target с `linkerSettings: [.linkedLibrary("z")]`.
- **`Sources/ConfigKit/Zlib.swift`**:
  - `func qUncompress(_ data: Data) throws -> Data` — читает 4 байта big-endian (длина несжатого), инфлейтит zlib-поток RFC1950 через libz (`inflateInit_`/`inflate`). **Не** Compression.framework (там raw deflate без заголовка — молча не совпадёт);
  - `func qCompress(_ data: Data, level: Int32 = 8) -> Data` — обратная операция, нужна тестам для синтеза ключей;
  - `enum ZlibError: Error` — `truncatedHeader`, `inflateFailed(code:)`, `lengthMismatch`.
- **`Sources/ConfigKit/VPNKeyDecoder.swift`**:
  - `public enum VPNKeyError: Error, LocalizedError` — `notAVPNKey`, `invalidBase64`, `decompressionFailed`, `malformedJSON(String)`, `noCloakContainer`, `missingField(String)` — каждая с человекочитаемым русским описанием (пойдёт на экран импорта);
  - `public static func decode(_ key: String) throws -> AmneziaConfig` — срез `vpn://`, base64url **без паддинга** → Data (паддинг восстанавливаем сами), `qUncompress`; при неудаче распаковки — запасной путь: тот же Data как plain JSON.
- **`Sources/ConfigKit/AmneziaModels.swift`** — Codable-модели: `AmneziaConfig {hostName, description?, dns1?, dns2?, defaultContainer?, containers}`, `AmneziaContainer {container, openvpn?, cloak?, shadowsocks?}`. **Двойной разбор**: `openvpn.last_config` и `cloak.last_config` — JSON-СТРОКИ, парсятся вторым проходом: `OpenVPNLastConfig {config, clientId?}`; Cloak — в словарь `[String: JSONValue]` (свой enum, сохраняющий число/строку как есть — исходные типы полей в ключе не гарантированы). Рядом с `last_config` в объекте `cloak` могут лежать `port`, `transport_proto` — модель их видит.
- **`Sources/ConfigKit/CloakTransform.swift`** — `public static func makeCloakJSON(cloak:hostName:) throws -> Data`, порт `setupCloak` из `ios_controller.mm`:
  - `NumConn = 1` (число, принудительно — защита памяти расширения);
  - `RemoteHost` ← первое непустое `remote` / `RemoteHost` / `hostName`, `RemotePort` ← `port`; ключи `remote`, `port`, `transport_proto` — удалить;
  - **типы**: только `NumConn` и `StreamTimeout` — числа (`"300"` → `300`); все остальные значения — строки (`UID`/`PublicKey` — base64-строки как есть). Иначе Go `json.Unmarshal` на той стороне сломается;
  - результат — канонический JSON `Data`.
- **`Sources/ConfigKit/OVPNProfileBuilder.swift`** — `public static func build(ovpnText:serverIP:dns1:dns2:cloakJSON:) -> String`:
  - подстановка `$PRIMARY_DNS`/`$SECONDARY_DNS` (дефолты 1.1.1.1 / 1.0.0.1); оба случая: плейсхолдеры есть / их нет;
  - проверка/вставка строки `route <serverIP> 255.255.255.255 net_gateway` (защита от петли №1 — OpenVPNAdapter конвертирует её в excludedRoute);
  - дописывание `\n<cloak>\n<base64(cloakJSON)>\n</cloak>\n` (base64 стандартный).
- **`Sources/ConfigKit/ImportedConfig.swift`** — `public struct ImportedConfig {ovpnProfile, serverIP, dns1, dns2, description}` (в App Group не сохраняется — см. M4) + фабрика `make(from key: String, resolve: (String) throws -> String) throws -> ImportedConfig` — резолвер хоста инжектируется (в приложении — getaddrinfo, в тестах — стаб), если `hostName` — домен, IP фиксируется при импорте.

**Тестовая стратегия — конкретные кейсы (`Tests/ConfigKitTests/`)**, синтетический ключ собирается прямо в тесте (JSON → qCompress → base64url → `vpn://`), реальный ключ в тесты **не попадает никогда**:

| # | Тест | Проверяем |
|---|---|---|
| 1 | `testDecodeQCompressedKey` | полный путь: vpn:// → base64url без паддинга → qUncompress → модель; hostName/containers на месте |
| 2 | `testDecodePlainBase64Fallback` | ключ без zlib (plain base64 JSON) — запасной путь срабатывает |
| 3 | `testBase64URLPaddingVariants` | длины ключа с 0/1/2 недостающими символами паддинга |
| 4 | `testDNSPlaceholdersSubstituted` | `$PRIMARY_DNS`/`$SECONDARY_DNS` в .ovpn → значения dns1/dns2 |
| 5 | `testNoPlaceholdersProfileUntouched` | профиль без плейсхолдеров не изменяется (кроме route/cloak) |
| 6 | `testDNSDefaultsWhenAbsent` | dns1/dns2 нет в ключе → 1.1.1.1 / 1.0.0.1 |
| 7 | `testRouteInsertedWhenMissing` | строки `route ... net_gateway` нет → вставлена с IP сервера |
| 8 | `testRoutePreservedWhenPresent` | строка уже есть → не дублируется |
| 9 | `testCloakNumConnForcedTo1` | во входе NumConn=4 → на выходе число 1 |
| 10 | `testCloakStreamTimeoutStringToNumber` | вход `"StreamTimeout":"300"` → выход `300` (число) |
| 11 | `testCloakUIDStaysString` | UID/PublicKey — base64-строки без изменений и без перекодирования |
| 12 | `testCloakRemoteHostPortMapping` | `remote`→`RemoteHost`, `port`→`RemotePort`; `remote`/`port`/`transport_proto` удалены |
| 13 | `testCloakRemoteHostFallsBackToHostName` | поля `remote` нет → `RemoteHost` = hostName |
| 14 | `testCloakBlockAppendedAndDecodable` | блок `<cloak>` в конце профиля; base64 декодируется обратно в тот же JSON |
| 15 | `testNestedLastConfigDoubleParse` | `last_config` как JSON-строка парсится вторым проходом; текст .ovpn с инлайн `<ca>` извлечён дословно |
| 16 | `testHostNameDomainResolved` | hostName-домен + стаб-резолвер → `serverIP` = результат резолва, попадает и в route |
| 17 | `testGarbageInputTypedErrors` | «мусор» (не vpn://, битый base64, битый zlib, не-JSON, JSON без cloak-контейнера) → соответствующая типизированная ошибка, не crash |
| 18 | `testContainerSelection` | выбирается контейнер `amnezia-openvpn-cloak` (по `defaultContainer` и без него) |
| 19 | `testQCompressRoundTrip` | qCompress → qUncompress — идентичность (валидирует сам тестовый синтезатор) |

**Проверка шага:** `cd ConfigKit && swift test` — всё зелёное на Mac. До написания парсера агент сверяет схему по эталонам через raw.githubusercontent.com: `exportController.cpp` (~строка 93, кодирование vpn://), `cloak_configurator.cpp` (поля Cloak), `ios_controller.mm` (~строка 566, setupCloak), `template.ovpn` (вид профиля).

**Действует:** агент.

### Шаг 0.4 — `scripts/decode-vpnkey.py` + документация

- **`scripts/decode-vpnkey.py`** — dev-утилита (stdlib-only: `base64`, `zlib`, `json`): вход `vpn://…` (аргумент или stdin), выход — читаемый JSON с **развёрнутыми** вложенными `last_config`; пишет только в stdout или в `Secrets/` (напоминание в help). Понадобится в M3 для ручной сверки реального ключа.
- **README.md** — дополняется: команды make, как гонять тесты, как скачать/проверить фреймворк, каналы логов (`log collect --device-name … --last 10m`, Console.app по subsystem).
- **`docs/IMPLEMENTATION.md`** — копия этого плана (после утверждения).

**Проверка:** `python3 scripts/decode-vpnkey.py` на синтетическом ключе из теста → корректный JSON. **Действует:** агент.

### Фаза 0.5 (опционально, пока ждём Apple) — фреймворк compile-only + полный провайдер

Смысл: максимально сократить будущие M2–M3, пока аккаунт не одобрен. Всё компилируется, ничего не запускается.

- **`project.yml`**: подключить `Frameworks/OpenVPNAdapter.framework` к таргету PacketTunnel (link + embed в приложение, code-sign-on-copy). `make gen && make build` (без подписи) — линковка с SDK 26 проверяется уже здесь.
- **`PacketTunnel/PacketTunnelProvider.swift`** — полная реализация **строго по заголовкам из `docs/FRAMEWORK-API.md`** (шаг 0.2):
  - `startTunnel`: конфиг из `providerConfiguration` → `OpenVPNConfiguration` (`fileContent` = готовый .ovpn, `tunPersist` остаётся `false`, вызов `setPTCloak`) → `adapter.apply(...)` (ошибки — в лог дословно) → **сторожевой таймер 30 сек** (Cloak-рукопожатие многосекундное; системное убийство ≈60 c недокументировано) → `adapter.connect(using: packetBridge)`. Логин/пароль не нужны (сертификаты в профиле);
  - `PacketFlowBridge` — отдельный мост потока пакетов, с учётом пакетов и IPv6-фильтром;
  - `configureTunnel(nil)` подтверждается без снятия системных маршрутов и DNS; новые настройки заменяют старые напрямую. Проверка P1 на физическом iPhone ещё не выполнена;
  - делегат `configureTunnelWithNetworkSettings`: `dnsSettings.matchDomains = [""]` всегда; DNS-fallback (адаптер → строки `dhcp-option DNS` из конфига → dns1/dns2); **`NEIPv4Route(serverIP, 255.255.255.255)` в `excludedRoutes`** (вторая половина защиты от петли — `tunnelRemoteAddress` будет `127.0.0.1`, автоисключение iOS не сработает); затем `setTunnelNetworkSettings`;
  - `handleEvent`: `.connected` → снять таймер, завершить старт; `.disconnected` → завершить стоп либо `cancelTunnelWithError`;
  - `handleError`: фатальность по `OpenVPNAdapterErrorFatalKey`; фатальные → `last_error.txt` (App Group);
  - `stopTunnel`: `adapter.disconnect()` + страховочный таймер 5 сек; `sleep`/`wake` — простой проброс;
  - переключатель пустышка/реальный туннель — по наличию ключа `ovpnConfig` в `providerConfiguration` (пустышка остаётся для M1).
  - Сверка с production-образцом: `amnezia-client` @ `4.8.21.0`, `client/platforms/ios/PacketTunnelProvider+OpenVPN.swift`.
- **`App/TunnelManager.swift`** — `@MainActor final class TunnelManager: ObservableObject`: `loadOrCreate()` (поиск/создание `NETunnelProviderManager`), `apply(config: ImportedConfig)` (заполнение `NETunnelProviderProtocol.providerConfiguration` по `TunnelConfigKeys`), `start()/stop()`, подписка на `NEVPNStatusDidChange` → `@Published var status`.

**Проверка:** `make build` (без подписи) — BUILD SUCCEEDED с фреймворком и полным провайдером. **Действует:** агент.

---

## Фазы, требующие аккаунт/устройство (по milestones PLAN.md)

### M1 — Подписи + пустышка-туннель на устройстве (1–2 сессии)

Пошаговая инструкция с чек-листом и таблицей «симптом → причина → что делать» — в **[DEVICE-TESTING.md](../DEVICE-TESTING.md)**.

| Шаг | Кто | Что |
|---|---|---|
| 1.1 | **Пользователь** | Дождаться одобрения Apple Developer (Individual); на портале принять соглашения. Xcode → Settings → Accounts → добавить Apple ID. Сообщить агенту **Team ID** (developer.apple.com → Membership, 10 символов) |
| 1.2 | **Пользователь** | Подключить iPhone кабелем; на телефоне: Trust This Computer; открыть Xcode → Window → Devices and Simulators (после «Preparing…» в настройках телефона появится пункт Developer Mode); Settings → Privacy & Security → **Developer Mode** → включить (перезагрузка). *Developer Mode — переключатель iOS 16+, без него телефон не принимает сборки не из App Store* |
| 1.3 | Агент | Вписать Team ID в `project.yml` (`DEVELOPMENT_TEAM`). В UI Xcode ничего не настраивать: `.xcodeproj` пересоздаётся каждым `make gen` |
| 1.4 | Агент+Пользователь | `make install` (`scripts/install-device.sh`): подписанная сборка **под подключённый телефон** — `xcodebuild -destination "id=<UDID>" -allowProvisioningUpdates -allowProvisioningDeviceRegistration` → проверка, что entitlements попали в подпись app и appex → `xcrun devicectl device install app` + `process launch` (без отладчика). Пользователь у Mac: диалог Связки ключей → «Всегда разрешать». Если на телефоне iOS 16 — `ios-deploy` |
| 1.5 | **Пользователь** | Первое нажатие «Подключить» → системное окно «…хочет добавить конфигурации VPN» → Allow |
| 1.6 | Агент+Пользователь | `make logs` — агент сам читает `tunnel.log` / `app.log` с телефона; довести `ContentView`/`LogView` до проверки M1 |

*Почему телефон раньше сборки: у новой команды нет зарегистрированных устройств, а без них Apple не выпускает development-профиль — сборка с `generic/platform=iOS` падает с «Your team has no devices». Сборка по UDID с `-allowProvisioningDeviceRegistration` регистрирует телефон сама; Xcode заодно выпускает сертификат, оба App ID и App Group (для packet-tunnel портал самообслуживаемый).*

**Проверка (из PLAN.md):** статус «Подключено», в Настройки → VPN профиль «Подключено», значок VPN в Пункте управления (на iPhone с Face ID в статус-баре его нет); пустышка, узкий маршрут `10.8.0.0/24`; выключение убирает значок; обычный интернет работает; LogView показывает строки, записанные расширением (доказательство App Group). Типичный камень — ошибки entitlements/профилей: читаем точный текст `xcodebuild`, чиним в `project.yml`.

### M2 — Фреймворк в процессе расширения (1 сессия; +1–2 при запасном пути)

- Если 0.5 не делалась — выполнить её содержимое сейчас (по шагам 0.2 → 0.5).
- Агент: в `startTunnel` (ветка пустышки) создать `OpenVPNAdapter()` и записать в лог «OpenVPNAdapter loaded»; `make install`; убедиться, что расширение не падает при загрузке фреймворка (ошибки встраивания/подписи вылезают здесь, не в M3).
- *Фаза 0.5 уже слинковала расширение с фреймворком, поэтому dyld грузит его при любом старте appex — M1 и M2 проходят одной установкой (маркер в логе уже есть). Приложение фреймворк только встраивает (`link: false`), в его процесс Go-runtime не попадает.*
- **Проверка:** `verify-framework.sh` — 3 PASS; пустышка подключается; в логе «OpenVPNAdapter loaded».

### M3 — Настоящее соединение на зашитом конфиге (2–4 сессии; главный риск-этап)

| Шаг | Кто | Что |
|---|---|---|
| 3.1 | **Пользователь** | Экспортировать `vpn://`-ключ из рабочей Amnezia, положить в `Secrets/my.vpnkey` (в .gitignore) |
| 3.2 | Агент | `decode-vpnkey.py Secrets/my.vpnkey > Secrets/my-decoded.json`; вручную сверить реальную схему с моделями ConfigKit (расхождения → сначала чинить ConfigKit + тесты) |
| 3.3 | Агент | DEBUG-мост: при старте DEBUG-сборки, если в `Secrets/` лежит ключ — прогнать через ConfigKit и записать готовый `ImportedConfig` в профиль туннеля (импортёра-экрана ещё нет). Если `hostName` — домен, IP резолвится и фиксируется здесь |
| 3.4 | Агент | Переключить провайдер на реальный туннель. Установка **только через CLI, без отладчика Xcode** (баг Go golang/go#57651: под отладчиком Cloak ~5 fps и выглядит зависшим; отладка только логами) |
| 3.5 | Агент+Пользователь | Прогон проверки; при разборе полётов — `tunnel.log` через LogView/`log collect` |

**Проверка (из PLAN.md):** «Подключить» → несколько секунд «Подключение» (рукопожатие Cloak) → «Подключено»; сайт-определитель IP показывает **IP сервера**; сайты грузятся (петли нет, DNS в туннеле); 10 минут стабильно (heartbeat памяти комфортно < 50 МБ); чистое отключение; переподключение.

**Если «подключено, но трафика нет» на iOS 26** — известный баг amnezia-client#2072: файловое логирование у нас всегда включено (совпадает с обходом); если не помогло — `build-framework-source.sh` (HEAD `master-amnezia` с мартовскими фиксами), повторить ворота verify и M2.

### M4 — Импорт ключа в приложении (сделан 2026-09-24)

Решения, принятые перед реализацией (отличаются от первоначального плана):
- **Вшитого ключа нет.** Клиент раздаётся пустым, ключ каждый добавляет сам: ключи раздаются
  по одному на человека, а в будущем клиент может пригодиться любому владельцу сервера
  OpenVPN over Cloak. Ресурс `App/Resources/default.vpnkey` не поддерживается; `make
  release-check` наоборот проверяет, что в бандле нет ни файла ключа, ни строки `vpn://…`.
- **DEBUG-мост оставлен** (`make push-key`, `make connect/disconnect`, `make dummy`): он позволяет
  проверять импорт на телефоне без рук и идёт через тот же `TunnelManager.importKey`, что и
  экран. В Release его нет — `make release-check` собирает обе конфигурации и проверяет метки.
- **config.json не пишется**: профиль с приватным ключом живёт только в `providerConfiguration`;
  `ImportedConfig.save/load` и `SharedPaths.configURL` удалены.
- **Профиль-пустышка M1 из интерфейса убрана**: без ключа кнопка «Подключить» не показывается.
  Пустышка осталась диагностикой `make dummy` (затирает боевой профиль).

Что сделано:
- **ConfigKit**: `VPNKeyText` + `VPNKeyDecoder.decode(pastedText:)` — ключ внутри сообщения,
  переносы строк, невидимые символы, латинский хвост после ключа (перебор кандидатов);
  `qUncompress` — потоковый inflate, отличает обрезанный ключ (`VPNKeyError.truncated`,
  «скопирован не целиком») от испорченного и ограничивает заявленный размер. 16 новых тестов
  (`PastedTextTests`), всего 41.
- **`App/ImportView.swift`**: `PasteButton` (без системного запроса «Разрешить вставку»), поле,
  файл из «Файлов» (`fileImporter`, до 1 МБ); текст готовит к диалогу «…хочет добавить
  конфигурации VPN»; поле очищается после импорта и при закрытии.
- **`TunnelManager.importKey`** — единственный путь импорта: разбор в `Task.detached` (DNS,
  если hostName — домен) → поднятый VPN отключается и ждём «Отключено» → `apply`; при отказе
  сохранить профиль (в т.ч. «Не разрешать») прежний профиль перечитывается из настроек и не
  портится. В `app.log` — только размеры и вид ошибки.
- **`ContentView`**: нет боевого профиля → «Ключ не добавлен» + кнопка «Добавить ключ»;
  кнопка-ключ в тулбаре для смены.

**Проверка (2026-09-24):** `make test` 41 зелёный; `make build`, `make verify` 3×PASS,
`make release-check` 5×PASS (с подложенным `default.vpnkey` — FAIL, как и должно). На телефоне
через мост тем же кодом: мусор → `notAVPNKey`, обрезанный → `truncated`, ключ AWG →
`noCloakContainer`, приложение не падает, старый профиль цел; настоящий ключ → `import OK` →
`connected`, heartbeat со счётчиками пакетов, без `Transport error`; повторный импорт при
поднятом VPN → `tunnel is up — stopping` → `import OK`. Чистая установка + вставка ключа
на экране → IP сервера — см. DEVICE-TESTING.md, этап E.

### M5 — Доводка (сделано на Mac 2026-09-26; проверка на телефоне — DEVICE-TESTING.md, этап F)

Что сделано:
- **Статусы**: `NEVPNStatus.localizedText` для всех шести значений + `localizedHint` — пояснение
  под статусом для `invalid` (профиль удалили/не разрешили → импортировать ключ заново),
  `reasserting` (сеть сменилась, ничего нажимать не нужно), `disconnecting`. Ошибка под кнопкой
  осталась в принятом виде: подсказка + сырой код `[домен код: текст]`, источники —
  `fetchLastDisconnectError` и `last_error.txt` расширения.
- **Логи**: «Поделиться» на экране «Логи» отдаёт все имеющиеся файлы сразу (`tunnel.log`,
  `app.log`, `last_error.txt`), а не только открытую вкладку — причина сбоя обычно видна лишь по
  двум логам вместе.
- **Локализация ru/en**: `App/Localizable.xcstrings` (String Catalog), русский — базовый
  (`developmentLanguage: ru` в `project.yml`; ключ каталога = русская строка из кода), английский —
  перевод. Литералы `Text(...)` SwiftUI берёт из каталога сами, строки `TunnelManager` — через
  `String(localized:)`. Тексты ошибок разбора ключа переводятся в приложении
  (`TunnelManager.explainParse`), `ConfigKit` остаётся пакетом без ресурсов (его
  `errorDescription` — для логов и тестов). **Строки для `app.log` не локализуются**
  (`NEVPNStatus.logName`). Ворота: `make strings-check` (`scripts/check-localization.py`) —
  каждый русский литерал `App/*.swift` есть в каталоге и переведён, мёртвых ключей нет; в
  `upload-testflight.sh` вызывается автоматически.
- **Иконка**: `make icon` → `scripts/make-app-icon.swift` (CoreGraphics/CoreText, без
  зависимостей) рисует одну картинку 1024×1024 без альфа-канала в
  `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; для iOS 17+ этого достаточно. Акцентный
  цвет `#3D9EF2` — общий для иконки и `AccentColor.colorset`.
- **Авто-подключение (`isOnDemandEnabled`) — не делаем**, в `apply` оно явно выключено.
  Причины: (1) при недоступном сервере iOS переподключается бесконечно и заметно жрёт батарею;
  (2) смена ключа устроена как «стоп → ждём Отключено → запись профиля» — с on-demand система
  перезапускала бы туннель сразу после стопа, и `stopAndWait` ломался бы; (3) нужны
  `onDemandRules` + переключатель + отдельная проверка на телефоне — не укладывается в доводку.
  Если понадобится: правило `NEOnDemandRuleConnect` с `interfaceTypeMatch = .any`, переключатель
  выключен по умолчанию, при включении — предупреждение из PLAN.md.

**Проверка на Mac (2026-09-26):** `make build` — BUILD SUCCEEDED; `make test` — 41 тест, 0 ошибок;
`make release-check` — 5×PASS, в бандле `ru.lproj`/`en.lproj/Localizable.strings` и `Assets.car` с
иконкой; `make strings-check` — PASS, 66 строк. **На телефоне** (телефон на русском → русский
интерфейс; сервер выключен → под кнопкой читаемая ошибка; экспорт логов) — сценарий в
DEVICE-TESTING.md, этап F; ещё не выполнялся.

### M6 — TestFlight (инструменты готовы 2026-09-26; загрузка ещё не выполнялась)

| Шаг | Кто | Что | Состояние |
|---|---|---|---|
| 6.1 | **Пользователь** | App Store Connect: создать запись приложения (bundle `com.razhev.ovocclient` — после первой загрузки сборки он не меняется); Users and Access → Integrations → **API key** (роль App Manager), `.p8` → `~/.private_keys/`; Key ID + Issuer ID → `Secrets/asc.env` | **ждёт** — по шагам в docs/TESTFLIGHT.md |
| 6.2 | Агент | `Config/ExportOptions.plist` (method `app-store-connect`, destination upload, автоподпись, `manageAppVersionAndBuildNumber=false`) + `scripts/upload-testflight.sh` = `make testflight`: проверки окружения/реквизитов → ворота `release-check` + `strings-check` → `xcodebuild archive` → `-exportArchive` с `-authenticationKey*`. Без fastlane, без altool. `ITSAppUsesNonExemptEncryption=false` уже в `project.yml`/`Info.plist`, скрипт это сверяет на архиве | сделано; первый запуск — после 6.1 |
| 6.3 | **Пользователь** | В App Store Connect: внешняя группа тестеров + публичная ссылка; заметки Beta App Review — готовый текст в docs/TESTFLIGHT.md, приложить отдельный тестовый ключ | **ждёт** |
| 6.4 | Агент | docs/TESTFLIGHT.md: текст заметок для ревью, шаблон сообщения родственникам (ru), памятка «перезаливать ≤90 дней» (скрипт печатает дату и ведёт `build/testflight/uploads.log`), запасной вариант с внутренними тестерами, таблица ошибок | сделано |

**Подготовка к первой загрузке (2026-09-27).**
- Privacy manifest у приложения, расширения и фреймворка. Причины выбраны по сканированию бинарей Release: C617.1 и 35F9.1; манифест фреймворка — `Config/OpenVPNAdapter-PrivacyInfo.xcprivacy`, в фреймворк его кладёт `make framework-manifest`.
- `LICENSE` (GPL-3.0), `THIRD_PARTY_LICENSES.md`, тексты лицензий в `App/Licenses`.
- `App/AboutView.swift`: экран «О приложении» и карточка «Что с данными» (правило 5.4) на экране импорта.
- `PRIVACY.md`.
- `make release-check` проверяет manifest и лицензии; `make testflight` предупреждает о пустых `OVoCSourceCodeURL` / `OVoCPrivacyPolicyURL`.
- `ITSAppUsesNonExemptEncryption=false` перепроверен по таблице Apple и оставлен.

Ручные шаги — docs/TESTFLIGHT.md, «Первая загрузка».

Номер сборки поднимается руками: `CURRENT_PROJECT_VERSION` в `project.yml` перед каждой
загрузкой (скрипт отказывается заливать номер, который уже заливался).

**Проверка:** сборка «Ready to Test»; свой телефон ставит по публичной ссылке; один родственник подключается и видит IP сервера. Fallback при буксующем ревью — внутренние тестеры (без ревью, Apple ID в команду).

---

## План коммитов

Маленькие осмысленные коммиты, `git push` после каждого логического блока (репозиторий — точка синхронизации между машинами). Ожидаемая последовательность Фазы 0:

1. `docs: add implementation plan (docs/IMPLEMENTATION.md)`
2. `build: project.yml + Makefile + target skeletons (compiles unsigned)`
3. `feat(tunnel): dummy tunnel provider + RingLogger + shared App Group paths`
4. `build(scripts): fetch-framework.sh with pinned SHA-256 + verify-framework.sh`
5. `docs: record framework API surface (setPTCloak, delegate signatures)` — файл `docs/FRAMEWORK-API.md`
6. `feat(configkit): package + zlib qUncompress/qCompress`
7. `feat(configkit): vpn:// decoder + Amnezia models (double-parse last_config)`
8. `feat(configkit): cloak transform + ovpn profile builder + ImportedConfig`
9. `test(configkit): full unit suite (19 cases)` — может идти вперемешку с 6–8, тесты пишутся рядом с кодом
10. `feat(scripts): decode-vpnkey.py` + `docs: README build/test/debug instructions`
11. (0.5) `build: link OpenVPNAdapter.framework (compile-only)`
12. (0.5) `feat(tunnel): full PacketTunnelProvider per framework headers`

Дальше — по одному-двум коммитам на шаг милестоунов (`feat(app): tunnel manager + connect button`, `feat(app): key import screen`, `chore(release): testflight upload script`, …). Секреты (`Secrets/`, `*.vpnkey`, `*.ovpn`) не коммитятся никогда; реальный ключ не появляется ни в коде, ни в тестах, ни в логах коммитов.

---

## Открытые вопросы

| Вопрос | Блокирует? | Когда закроется |
|---|---|---|
| ~~**Team ID**~~ — закрыт 2026-09-19: аккаунт одобрен, Team ID вписан в `project.yml` | — | — |
| Точная сигнатура `setPTCloak` и тип completion делегата | Блокирует написание кода провайдера (0.5/M2) | Шаг 0.2 — из реальных заголовков скачанного фреймворка |
| Пригодность релиза v1.0.42 (символы Cloak, линковка с SDK 26) | Может переключить на запасной источник/сборку из исходников | Шаг 0.2 (символы/заголовки) и M2 (загрузка на устройстве) |
| Реальный `vpn://`-ключ пользователя | Блокирует M3 (шаг 3.1), не раньше | Пользователь экспортирует из Amnezia к началу M3 |
| ~~Версия iOS на рабочем iPhone~~ — закрыт 2026-09-19: iPhone 16 Pro, iOS 26.6.2 → штатный путь через `devicectl` | — | — |
| App Store Connect: запись приложения + API key (Key ID, Issuer ID) | Блокирует только первый `make testflight` (инструменты готовы) | Пользователь создаёт по docs/TESTFLIGHT.md, шаг 6.1; реквизиты — в `Secrets/asc.env` (не в git) |
| ~~Имя «PersonalVPN» — финальное?~~ — закрыт 2026-09-24: приложение — **OVoC Client** (OpenVPN over Cloak Client), проект `OVoCClient`, bundle `com.razhev.ovocclient` | — | — |

---

## Верификация (сквозная, из PLAN.md)

- **Mac, без телефона:** `make test` — ConfigKit, Runtime/Shared и Python-проверки происхождения фреймворка; `make build` (unsigned) — BUILD SUCCEEDED; `make verify` — 4 PASS.
- **iPhone:** `make install` → «Подключить» → значок VPN → сайт-определитель показывает IP сервера → сайты открываются → 10 минут стабильно (память < 50 МБ в heartbeat) → чистое отключение.
- **Раздача:** сборка «Ready to Test» → установка по публичной ссылке → родственник подключается.

Каждый этап заканчивается своей проверкой; без её прохождения к следующему не переходим. Ошибки (упавшие тесты, FAIL в verify, ошибки xcodebuild) показываются пользователю дословно.

## Первые действия после утверждения

1. Сохранить этот план в `docs/IMPLEMENTATION.md`, закоммитить и запушить.
2. Выполнить Фазу 0 по шагам 0.1 → 0.4 (при затяжном ожидании Apple — продолжить 0.5).
3. Параллельно пользователю: следить за статусом заявки Apple Developer; после одобрения — логин в Xcode и Team ID (шаг 1.1).
# Дополнение от 6 октября 2026 года

Экспериментальные исключения российских сервисов реализованы для сборки 0.1.0 (4).
Состояние аппаратной приёмки и ограничения — в [плане](../RU-SERVICES-BYPASS-PLAN.md)
и [проверке устройств](../DEVICE-TESTING.md#проверка-исключений-российских-сервисов).

`Shared/ServiceBypassPolicy.swift` и `IPNetwork.swift` валидируют конфигурацию и каталог;
`Shared/Resources/ServiceBypassCatalog.json` копируется в оба bundle.
`ServiceBypassProfileUpdate` работает через тестируемую границу хранилища; системная
обёртка в `App` сохраняет копию профиля и перечитывает фактическое состояние.
`TunnelManager` блокирует конкурирующие импорт, запись исключений и подключение.
При импорте ключа поле исключений сохраняется. Отсутствие поля означает прежнее поведение.

Расширение читает каталог один раз на старт и сохраняет снимок на reconnect.
`PacketTunnel/Runtime/ServiceBypassRoutes.swift` добавляет IPv4/IPv6-исключения в копию
настроек адаптера после установки DNS и IPv6-раковины. Исходные маршруты сохраняются;
пересечения с DNS/адресами туннеля отклоняются. Обработки каждого пакета и сетевого
обновления каталогов нет. `enforceRoutes` не меняется до аппаратного эксперимента.

Экран «Без VPN» объясняет прямое подключение и экспериментальный статус. Выбор меняется
только при отключённом VPN, defaults off. Начиная со сборки 7, `ServiceBypassSelectionModel`
сразу сохраняет каждый переключатель и синхронно блокирует повторные действия и закрытие
до завершения записи. Промежуточные события профиля не затирают текущий выбор; после ошибки
показаны фактическое состояние и сообщение. Подробности свёрнуты, отдельной кнопки сохранения нет.
Обновлены disclosure и Privacy Policy; опубликованная копия синхронизирована при выпуске
сборки 4. Статус кода не равен подтверждению полной работоспособности сервисов:
аппаратная проверка отложена пользователем.

### Расширение каталога и общий переключатель — 2026-10-10

`BypassService` содержит восемь групп. Политика версии 1 продолжает хранить явное
множество идентификаторов, поэтому обновление не включает новые группы автоматически.
«Исключить все» записывает все текущие идентификаторы или пустой набор той же транзакцией
автосохранения. Состояние общего переключателя вычисляется из фактического выбора;
при частичном выборе он выключен, а счётчик показывает выбранные группы.
`DisclosureGroup` можно раскрыть при подключении или сохранении; заблокированы только
изменения. Главный экран сокращает сводку для четырёх и более выбранных сервисов.

Каталог `2026-10-10.1`: 99 исходных записей, 96 после нормализации. Для общих CDN
и хостингов добавлены точечные DNS-снимки, для Мосэнергосбыта и финансовой части Ozon —
проверенные собственные сети. DNS/реестровые источники и ограничения перечислены
в [описании каталога](../SERVICE-BYPASS-CATALOG.md). Изменений пакетного транспорта нет.

10 октября новый интерфейс проверен на iPhone: выбор всех/части/ни одного сервиса,
сохранение и раскрытие при подключённом VPN работают. Логи подтверждают применение
96 маршрутов для восьми групп. Проверка Ozon дала смешанный результат: первоначальная
ошибка сети с VPN, успешная главная после отключения, затем поиск и изображения с
задержкой после переподключения. Исправление Ozon и прямой маршрут каждого запроса
не подтверждены; остальные мобильные сервисы не проверялись. Подробный результат —
в [DEVICE-TESTING.md](../DEVICE-TESTING.md).

### Банковские исключения — 2026-10-11

Добавлены стабильные идентификаторы `tbank` и `sber`, названия ru/en и две группы
каталога `2026-10-11.1`. Всего десять групп и 104 нормализованных маршрута.
Схема политики не меняется: прежний набор из восьми групп не включает банки после
обновления. Общий переключатель и счётчик используют `BypassService.allCases`.
Тесты проверяют сохранение всех 1024 комбинаций выбора, миграцию прежнего набора,
независимость банковских исключений и соседние адреса общих провайдеров.
Пройдены 100 тестов, локализация 137 строк и Debug/Release-проверки. Банковские
сценарии на iPhone и выпуск новой сборки в TestFlight в эту проверку не входят.
