# Промпт для агента: детальное планирование имплементации

> **Как использовать.** Открой Claude Code (или другой сильный кодинг-агент) в корне этого репозитория — лучше в plan mode — и вставь текст ниже целиком, начиная с «Роль». Промпт самодостаточен: он рассчитан на агента без контекста предыдущих сессий, в том числе на другой машине.

---

## Роль

Ты — ведущий iOS-инженер и наставник. Проект: минимальный нативный iOS VPN-клиент для личного сервера AmneziaVPN с протоколом **OpenVPN over Cloak** (репозиторий `razhev/personal-ios-client`, приватный). Пользователь — опытный человек, но **новичок в iOS-разработке**: когда вводишь новую концепцию (entitlement, App Group, provisioning и т.п.), поясняй её в 1–2 предложениях. Решения принимай сам и прозрачно объясняй; вопросы задавай только там, где выбор реально за пользователем.

Твоя задача в этой сессии — **составить детальный план имплементации** (не писать код приложения, пока план не утверждён). Точная постановка — в разделе «Задача».

## Первым делом (обязательно, по порядку)

1. Прочитай **`PLAN.md` целиком** — это утверждённый план проекта: контекст, архитектура, структура файлов, этапы M0–M6 с проверками, риски. Он — источник правды; твой план имплементации детализирует его, а не заменяет.
2. Проверь окружение на текущей машине (промпт могут запускать с разных машин):
   - `xcodebuild -version` — нужен Xcode 26+ (требование Apple для загрузки в TestFlight с апреля 2026);
   - `which xcodegen go gh` — XcodeGen обязателен; Go нужен только для запасного пути сборки Cloak; `gh auth status` — доступ к GitHub;
   - `security find-identity -v -p codesigning` — если 0 identities, платный Apple Developer аккаунт ещё не одобрен/не подключён к Xcode → в плане всё, что требует подписи и устройства, выноси в отдельную фазу (см. «Фаза 0» ниже).
3. Посмотри текущее состояние репозитория (`git log --oneline`, `ls`) — не дублируй уже сделанное.

## Зафиксированные решения — НЕ пересматривать

(Итог многочасового исследования исходников Amnezia, правил Apple и прецедентов; отклоняться можно только обнаружив фактическую ошибку — тогда останови планирование и покажи пользователю доказательства.)

1. **SwiftUI-приложение + одно расширение `NEPacketTunnelProvider`** (appex). Никакого Qt, никакого форка приложения amnezia-client.
2. **Архитектура «PluggableTransports»**: Cloak уже вшит внутрь OpenVPN3 в готовом бинарном `OpenVPNAdapter.framework` от Amnezia. Мы НЕ запускаем Cloak как локальный прокси и НЕ используем `remote 127.0.0.1` + локальный листенер. Со стороны Swift: дописать в текст `.ovpn` блок `\n<cloak>\n<base64(cloakJSON)>\n</cloak>\n` и вызвать `setPTCloak` на `OpenVPNConfiguration`.
3. **Проект генерируется XcodeGen** из `project.yml`; вся сборка/установка — CLI (`xcodebuild`, `xcrun devicectl`), никаких ручных кликов в Xcode (кроме одноразового логина в аккаунт).
4. **Device-only**: `SUPPORTED_PLATFORMS: iphoneos`. NE не работает в симуляторе, у фреймворка нет simulator-slice — симулятор не поддерживаем вовсе.
5. **`ConfigKit`** — локальный SPM-пакет (platforms: iOS 16, macOS 13) со ВСЕЙ логикой разбора ключа; тестируется на Mac через `swift test` без телефона и подписи.
6. Расширение **ничего не парсит**: приложение при импорте собирает готовый текст `.ovpn` (с уже дописанным `<cloak>`) и передаёт через `providerConfiguration` (+ `serverIP`, `dns1`, `dns2`). App Group — для логов и хранения конфига.
7. Deployment target **iOS 16.0**; `SWIFT_VERSION: "5.0"` (не Swift 6 language mode — избегаем strict-concurrency трения с ObjC-делегатами).
8. Bundle ID: `com.razhev.ovocclient` (app), `com.razhev.ovocclient.tunnel` (extension), App Group `group.com.razhev.ovocclient`. Имя приложения — OVoC Client (OpenVPN over Cloak Client), проект и таргет — `OVoCClient`. До 2026-09-24 — рабочее имя PersonalVPN и bundle `com.razhev.personalvpn`.
9. Раздача: **TestFlight, внешняя группа с публичной ссылкой** (fallback — внутренние тестеры). Загрузка: `xcodebuild -exportArchive` + App Store Connect API key. Без fastlane, без altool (мёртв в Xcode 26).
10. Структура каталогов и список файлов — в PLAN.md, раздел «Структура проекта». Следуй ей.

## Технический справочник (выжимка исследования — сэкономит тебе часы)

### Компоненты и откуда их брать

| Что | Откуда | Примечание |
|---|---|---|
| `OpenVPNAdapter.framework` (OpenVPN3 + mbedTLS + Cloak внутри) | Прежде всего: https://github.com/amnezia-vpn/3rd-build-ga/releases/download/v1.0.42/openvpnadapter.zip | Готовый бинарь, iOS arm64 only. Зафиксировать SHA-256 при первом скачивании |
| Запасной источник фреймворка | репозиторий `amnezia-vpn/3rd-prebuilt`, ветка `feature/special-handshake`, путь `openvpn/apple/OpenVPNAdapter-ios/OpenVPNAdapter.framework` | |
| Крайний случай — сборка из исходников | `git clone --recursive -b master-amnezia https://github.com/amnezia-vpn/OpenVPNAdapter` → xcodebuild их framework-таргета | SPM у форка сломан (OpenVPN3 — сабмодуль), podspec указывает на чужой upstream — только клон + их `.xcodeproj`. В HEAD есть фиксы марта 2026 |
| Go-часть Cloak (уже внутри фреймворка) | `amnezia-vpn/Cloak`, ветка `master-amnezia`, пакет `cmd/ck-ovpn-plugin` | Пересобирать НЕ нужно, если `nm` находит символы (см. ворота ниже) |

**Ворота проверки фреймворка (до любой интеграции):** `lipo -info` → только arm64; `nm -gU <бинарь>` содержит `Cloak_dial` и `Initialize_cloak_c_client`; в `Headers/` есть `setPTCloak`. **Точную сигнатуру `setPTCloak` и тип completion у делегата `configureTunnelWithNetworkSettings` зафиксируй из реальных заголовков** — форк менял API в марте 2026; не пиши код провайдера по памяти/блогам.

### Формат ключа `vpn://…` (экспорт Amnezia)

- `vpn://` + **base64url без паддинга** от `qCompress(JSON, 8)` = **4 байта big-endian** (длина несжатого) + **zlib-поток RFC1950** (с заголовком). Запасной вариант при неудаче распаковки — обычный base64 JSON.
- Распаковка через **libz** (`linkedLibrary("z")`). НЕ через `Compression.framework` — его `COMPRESSION_ZLIB` — это raw deflate БЕЗ zlib-заголовка, формат молча не совпадёт.
- Схема JSON: `{hostName, description, dns1, dns2, defaultContainer, containers: [...]}`. Нужный контейнер: `"container": "amnezia-openvpn-cloak"`, внутри ключи `openvpn`, `cloak`, `shadowsocks`.
- **`openvpn.last_config` и `cloak.last_config` — это JSON-СТРОКИ, их парсят вторым проходом.** `openvpn.last_config` → `{config: "<полный текст .ovpn с инлайн <ca><cert><key><tls-auth>>", clientId}`. `cloak.last_config` → `{Transport, ProxyMethod:"openvpn", EncryptionMethod, UID, PublicKey, ServerName, NumConn, BrowserSig, StreamTimeout, RemoteHost, RemotePort}`; рядом с `last_config` в объекте `cloak` могут лежать `port`, `transport_proto`.
- В тексте `.ovpn` могут быть плейсхолдеры `$PRIMARY_DNS` / `$SECONDARY_DNS` — подставить из `dns1`/`dns2` (по умолчанию 1.1.1.1 / 1.0.0.1). Обработать оба случая: плейсхолдеры есть / их нет.

### Трансформация Cloak-конфига перед вставкой в `<cloak>` (порт `setupCloak` из `ios_controller.mm`)

- `NumConn = 1` (число!) — принудительно, это защита памяти;
- `RemoteHost` ← значение поля `remote` (если есть), `RemotePort` ← `port`; ключи `remote`, `port`, `transport_proto` — удалить;
- **Типы критичны для Go `json.Unmarshal`:** только `NumConn` и `StreamTimeout` — числа; **все остальные значения — строки** (`UID`/`PublicKey` остаются base64-строками). `"StreamTimeout": "300"` строкой — сломает разбор на стороне Go.
- Итоговый JSON → base64 (стандартный) → в блок `<cloak>`.

### `PacketTunnelProvider`: обязательные детали

- `startTunnel`: прочитать конфиг из `providerConfiguration` → `OpenVPNConfiguration.fileContent` = текст `.ovpn`; `tunPersist = true`; вызвать `setPTCloak`; `adapter.apply(...)` (ошибки — дословно в лог); **сторожевой таймер 30 сек** (Cloak-рукопожатие многосекундное; системный таймер убийства недокументирован ≈60 c) → `adapter.connect(using: packetFlow)`. Логин/пароль не нужны (сертификаты в профиле). Мост потока пакетов: `extension NEPacketTunnelFlow: OpenVPNAdapterPacketFlow {}`.
- Делегат `configureTunnelWithNetworkSettings`: `dnsSettings.matchDomains = [""]` (всегда); если адаптер не отдал DNS — распарсить строки `dhcp-option DNS` из конфига, иначе `dns1`/`dns2`; **добавить `NEIPv4Route(serverIP, 255.255.255.255)` в `excludedRoutes`**; затем `setTunnelNetworkSettings`.
- **Петля маршрутов — риск №1.** `tunnelRemoteAddress` окажется `127.0.0.1` (CloakTransport игнорирует endpoint из строки `remote`), автоисключение сервера у iOS не сработает. Защита двойная: строка `route <serverIP> 255.255.255.255 net_gateway` в профиле (OpenVPNAdapter конвертирует её в excludedRoute — проверено по исходникам) + явное добавление в делегате. Парсер обязан проверить/вставить эту строку; если `hostName` — доменное имя, разрешить в IP при импорте и зафиксировать.
- `handleEvent`: `.connected` → снять таймер, завершить старт; `.disconnected` → завершить стоп либо `cancelTunnelWithError`. `handleError`: фатальность — по `OpenVPNAdapterErrorFatalKey`; фатальные — в `last_error.txt` (App Group). `stopTunnel`: `adapter.disconnect()` + страховочный таймер 5 сек. `sleep`/`wake` — простой проброс (v1).
- Лимит памяти расширения **50 МБ** (жёсткий, процесс-wide). Отсюда: NumConn=1, расширение без парсинга, маленькие буферы логов, heartbeat-строка с памятью раз в 30 сек.

### Ловушки разработки

- **Не подключать отладчик Xcode** к процессу расширения: известный баг Go на iOS/arm64 (golang/go#57651) — код Cloak под отладчиком работает как ~5 fps и выглядит зависшим. Отладка только логами.
- Логи: `RingLogger` → файл в App Group (с ротацией) + `os.Logger`; экран LogView в приложении с кнопкой «Поделиться»; на Mac — Console.app по subsystem или `log collect --device-name ... --last 10m`.
- **Пустышка-туннель в M1** — только узкий маршрут (например `10.8.0.0/24`), НИКОГДА не default route: мёртвый туннель с default route оставит телефон без интернета.
- `xcrun devicectl` требует iOS 17+ на подключённом устройстве (deployment target при этом 16.0 — это про телефон разработчика, не родственников).
- Известный баг iOS 26 (amnezia-client#2072): «подключено, но трафика нет, если выключено логирование» → лечение: собрать фреймворк из исходников `master-amnezia` HEAD. Файловое логирование держим всегда включённым.
- `ITSAppUsesNonExemptEncryption = false` в Info.plist приложения (стандартная криптография — экспортное исключение).
- **Секреты:** `Secrets/`, `*.vpnkey`, `*.ovpn` — в `.gitignore`, никогда не коммитить и не вставлять в код/тесты реальный ключ. Тесты используют синтетические ключи, собранные прямо в тесте.

### Эталонные исходники для сверки (читать через raw.githubusercontent.com / GitHub API, клонировать не нужно)

- `amnezia-client` @ тег **`4.8.21.0`** (последняя рабочая реализация Cloak на iOS; в 5.x протокол помечен устаревшим):
  - `client/platforms/ios/PacketTunnelProvider+OpenVPN.swift` — production-образец провайдера (DNS-fallback, matchDomains, excludedRoutes, статусы);
  - `client/platforms/ios/ios_controller.mm` — `setupCloak()` (~строка 566) и сборка `providerConfiguration`;
  - `client/server_scripts/openvpn_cloak/template.ovpn` — как выглядит профиль (включая `route $REMOTE_HOST ... net_gateway`);
  - `client/ui/controllers/exportController.cpp` (~строка 93) — точное кодирование `vpn://`;
  - `client/configurators/cloak_configurator.cpp` — поля Cloak-конфига.
- `amnezia-vpn/OpenVPNAdapter` @ `master-amnezia`: `Sources/OpenVPNAdapter/library/OpenVPNConfiguration.mm` (`setPTCloak`), заголовки делегата.
- Документация-ориентир по использованию адаптера: README `ss-abramchuk/OpenVPNAdapter` (upstream, архивный — только как справка по API-паттерну).

## Задача

Составь **детальный план имплементации** и оформи его как документ (если ты в plan mode — веди в плановом файле; после утверждения сохрани копию в `docs/IMPLEMENTATION.md` и запушь).

Требования к плану:

1. **Фазы с учётом ожидания Apple.** Заявка на Apple Developer подана, но пока не одобрена. Поэтому первой идёт **«Фаза 0 — всё, что не требует подписи и устройства»**: `project.yml` + скелет обоих таргетов (проверка компиляции: `xcodebuild build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`), весь `ConfigKit` с юнит-тестами (`swift test` на Mac), `scripts/fetch-framework.sh` + `verify-framework.sh` (скачивание и проверка символов — чисто Mac-операции, можно прямо сейчас), `decode-vpnkey.py`, `Makefile`, README-инструкции. Дальше фазы, требующие аккаунт/устройство, — по milestones M1–M6 из PLAN.md.
2. **Гранулярность:** для каждого шага — какие файлы создаются/меняются и что в них (сигнатуры ключевых типов/функций, без полного кода), какие команды выполняются, **проверка** («что увидим»), и кто действует — агент или пользователь (пользовательские действия: логин в Xcode, подключение iPhone, Trust, Developer Mode, экспорт ключа из Amnezia, создание записи в App Store Connect).
3. **Тестовая стратегия ConfigKit:** перечисли конкретные тест-кейсы (успешная распаковка; plain-base64 fallback; DNS-плейсхолдеры есть/нет; вставка/проверка `route`; правила типов Cloak, включая кейс `"StreamTimeout":"300"` → 300; hostName-домен → резолв; мусор на входе → типизированная ошибка).
4. **План коммитов:** маленькие осмысленные коммиты, push после каждого логического блока (репозиторий — точка синхронизации между машинами).
5. **Открытые вопросы** — отдельным списком, с пометкой, что блокирует, а что нет (например: Team ID появится после одобрения; точная сигнатура `setPTCloak` — после скачивания фреймворка; реальный ключ пользователя нужен к фазе M3).

## Правила работы (и на этапе планирования, и после)

- Не изобретай API — всё, что касается фреймворка, фиксируй из его реальных заголовков.
- Ошибки показывай честно (упавшие тесты, невыполненные проверки) — без приукрашивания.
- Каждый этап заканчивается верификацией из PLAN.md; не переходи дальше, пока она не пройдена.
- Секреты — см. выше; при работе с реальным ключом пользователя всё кладётся только в `Secrets/`.
- Пиши код с комментариями там, где происходит неочевидное (трансформации формата, маршруты, таймеры), — пользователь будет по нему учиться.

Когда план готов — покажи его пользователю на утверждение. После утверждения приступай к «Фазе 0».
