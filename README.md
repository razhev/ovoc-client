# OVoC Client

**OVoC Client** (OpenVPN over Cloak Client) — минимальный нативный iOS-клиент для личного сервера
**AmneziaVPN** (протокол **OpenVPN over Cloak**).
Для установки себе и нескольким родственникам через **TestFlight**. Не для публикации в App Store (пока).

Репозиторий — `personal-ios-client`; до 2026-09-24 приложение называлось PersonalVPN.

## Что где

- **[PLAN.md](PLAN.md)** — полный план разработки: архитектура, этапы (M0–M6) с проверками, риски.
- **[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)** — детальный план имплементации по шагам (Фаза 0 → M6), тест-стратегия, план коммитов, открытые вопросы.
- **[docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md)** — инструкция по тестированию на iPhone: подготовка аккаунта и телефона, чек-лист первого запуска, каналы отладки, таблица «симптом → что делать».
- **[docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)** — раздача через TestFlight по шагам: запись приложения и API-ключ в App Store Connect, `make testflight`, внешняя группа с публичной ссылкой, текст для Beta App Review, сообщение родственникам, памятка «90 дней».
- **[docs/FRAMEWORK-API.md](docs/FRAMEWORK-API.md)** — зафиксированный API `OpenVPNAdapter.framework`, выписанный из реальных заголовков. По нему пишется код провайдера.
- **[IMPLEMENTATION_PROMPT.md](IMPLEMENTATION_PROMPT.md)** — самодостаточный промпт для агента (выжимка исследования).

## Статус

Фазы 0 и 0.5 (всё, что не требует подписи и устройства): каркас проекта, ConfigKit с тестами,
скрипты фреймворка, полный `PacketTunnelProvider` — **готово**.

**M1 + M2 пройдены 2026-09-20** (iPhone 16 Pro, iOS 26.6.2): подписанная сборка ставится на
телефон командой `make install`, пустышка-туннель поднимается, App Group работает из обоих
процессов, `OpenVPNAdapter.framework` загружается в процессе расширения (4 МБ памяти при лимите
~50 МБ), обычный интернет при этом работает, отключение и повторное подключение — тоже.

**M3 пройден по основным проверкам 2026-09-20**: реальное соединение OpenVPN over Cloak
работает — сайт-определитель показывает IP сервера, сайты открываются, соединение держалось
11+ минут без единой ошибки и переподключения, память расширения до 18 МБ при лимите ~50 МБ,
на сервере 0 ошибок расшифровки. Для этого пришлось найти и исправить дефект готового
фреймворка Amnezia (разбор — в [docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md)); фреймворк
теперь собирается из исходников: `make framework`.

**M4 сделан 2026-09-24**: ключ добавляется в самом приложении — экран «Добавить ключ»
(вставка из буфера или файл из «Файлов»; можно вставить сообщение с ключом целиком). Без ключа
приложение предлагает импорт, а не подключение; ключ меняется кнопкой-ключом в тулбаре (поднятый
VPN при этом сначала отключается). Клиент раздаётся **пустым**: вшитого ключа нет, каждый добавляет
свой. Отладочный `make push-key` оставлен — он идёт через тот же код импорта, что и экран, и
вырезан из Release (`make release-check` это проверяет).

**Переименование 2026-09-24**: PersonalVPN → **OVoC Client**. Проект, таргет и схема — `OVoCClient`;
bundle ID — `com.razhev.ovocclient` (расширение `com.razhev.ovocclient.tunnel`, App Group
`group.com.razhev.ovocclient`). Для iOS это новое приложение: старое PersonalVPN удаляется с
телефона руками, ключ импортируется заново ([docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md),
«Переход с PersonalVPN»). Проверено на телефоне в тот же день: `make install` сам завёл новые
App ID и App Group, импорт ключа вставкой → «Подключено», в логах `connected`, heartbeat с
трафиком в обе стороны, ни одного `Transport error`.

Отключение кнопкой разобрано 2026-09-24: ложная фатальная ошибка #20 адаптера при `stopTunnel`
и двоичный мусор в `tunnel.log` (сырой `close` в Go-плагине Cloak) — причины и что сделано в
провайдере описаны в [docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md).

**M5 сделан 2026-09-26** (на Mac; проверка на телефоне — по сценарию в
[docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md), «Этап F»): интерфейс на русском и английском
(`App/Localizable.xcstrings`, русский — базовый), понятный текст для всех состояний VPN с
пояснением под статусом, ошибка под кнопкой — подсказка + сырой код в квадратных скобках,
«Поделиться» на экране «Логи» отдаёт сразу `tunnel.log` + `app.log` (+ `last_error.txt`),
иконка (`make icon`). Авто-подключение не делали — почему, см. docs/IMPLEMENTATION.md, M5.

**M6 подготовлен 2026-09-26**: `make testflight` (архив Release → загрузка в App Store Connect
через API-ключ, без fastlane/altool), `Config/ExportOptions.plist`, инструкция для ручных шагов
и тексты для ревью/родственников — [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md). Сама загрузка ещё
не выполнялась: нужны запись приложения и API-ключ в App Store Connect (шаг 6.1, делается руками).

Ещё не проверено (хвост гейта M3): утечка IPv6, переключение Wi-Fi ↔ LTE.

## Команды

Требуются: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make gen        # сгенерировать OVoCClient.xcodeproj из project.yml
make build      # собрать оба таргета БЕЗ подписи — быстрая проверка компиляции
make test       # юнит-тесты ConfigKit — на Mac, телефон не нужен
make framework  # собрать OpenVPNAdapter.framework из исходников Amnezia + наш патч (основной способ)
make fetch      # готовый бинарь v1.0.42 — НЕРАБОЧИЙ (дефект метки GCM), только для сравнения
make verify     # ворота: arm64? символы Cloak? setPTCloak в заголовках?

make devices    # какие iPhone видит Mac и готовы ли они к установке
make ddi        # смонтировать на телефон образ разработчика (VPN на Mac выключить)
make install    # подписанная сборка → установка на подключённый iPhone → запуск
make push-key   # DEBUG: доставить Secrets/my.vpnkey в приложение тем же кодом, что экран импорта
make release-check # ворота Release: нет DEBUG-моста, нет файлов ключа в бандле
make strings-check # каталог строк ru/en сходится с кодом (App/Localizable.xcstrings)
make icon       # перерисовать иконку 1024×1024 скриптом (scripts/make-app-icon.swift)
make scene      # пересобрать сцену главного экрана App/Scene/scene.html (нужен Node.js)
make testflight # Release-архив → загрузка в TestFlight (API-ключ в Secrets/asc.env, см. docs/TESTFLIGHT.md)
make logs       # забрать логи с телефона в build/logs/latest/
make crashlogs  # то же + отчёты о падениях расширения/приложения
```

`OVoCClient.xcodeproj` пересоздаётся каждым `make gen` — все настройки подписи живут в
`project.yml`, в интерфейсе Xcode ничего не настраиваем.

Разобрать ключ Amnezia в читаемый JSON (вывод сохранять только в `Secrets/`):

```bash
python3 scripts/decode-vpnkey.py Secrets/my.vpnkey > Secrets/my-decoded.json
```

Только структура ключа, без секретов (можно показывать в чате):

```bash
python3 scripts/decode-vpnkey.py --schema Secrets/my.vpnkey
```

## Архитектура (коротко)

- SwiftUI-приложение + одно расширение `NEPacketTunnelProvider`. Device-only
  (VPN не работает в симуляторе), deployment target iOS 16.0.
- `OpenVPNAdapter.framework` от Amnezia, **собранный из исходников с нашим патчем**
  (`make framework`, `patches/`): в их готовом бинаре клиент не записывает метку
  подлинности GCM, и сервер отбрасывает каждый пакет. Cloak скомпилирован
  внутрь OpenVPN3 как транспорт. Со стороны Swift: `setPTCloak()` + блок
  `<cloak>` в тексте профиля.
- **ConfigKit** — локальный SPM-пакет со всей логикой разбора ключа `vpn://…`
  (zlib-распаковка, двойной разбор `last_config`, типы Cloak-полей, сборка
  профиля). Тестируется на Mac: `make test`.
- Расширение ничего не парсит: приложение при импорте собирает готовый текст
  `.ovpn` и передаёт его через `providerConfiguration` — это единственное место,
  где лежит профиль с приватным ключом. App Group — только для логов.

## Отладка на устройстве (M1+)

К процессу расширения **нельзя подключать отладчик Xcode** — Go-код Cloak под
отладчиком деградирует до ~5 fps и выглядит зависшим (golang/go#57651). Поэтому
на телефон ставим только через `make install`, не кнопкой Run. Каналы отладки:

- экран «Логи» в приложении: `tunnel.log` (расширение) и `app.log` (приложение)
  из App Group; «Поделиться» отдаёт оба файла сразу (и `last_error.txt`, если есть);
- `make logs` / `make crashlogs` — те же файлы и отчёты о падениях на Mac, без sudo;
- Console.app с фильтром по subsystem `com.razhev.ovocclient`;
- `sudo log collect --device-name "<iPhone>" --last 10m` по кабелю.

Подробности и разбор типовых ошибок — [docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md).

## Секреты

`Secrets/`, `*.vpnkey`, `*.ovpn` — в `.gitignore`. Реальные ключи не коммитятся
и не попадают в код/тесты (тесты синтезируют ключи сами).

## Дизайн «Печка»

Мультяшная дизайн-система в духе советских мультфильмов 60-х: вместо замков,
ключей и щитов — изба, русская печь, ушат с тестом и колобок. Источник правды —
холст Design «Печка — мультяшный OVoC Client» (экраны, цвета, шрифты, голос,
компоненты, иконки, движение, иконка приложения).

- `App/Pechka.swift` — цвета, шрифты, кнопки, плашки, карточки, край панели;
  `App/PechkaIcons.swift` — иконки (те же SVG-пути, что на холсте).
- Сцена главного экрана — `App/Scene/scene.html` в `WKWebView` (`App/SceneView.swift`):
  SVG + CSS-анимации, собранные `make scene` из `scripts/pechka/scene.mjs` —
  того же кода, что рисует холст. «ПЫХ!» проигрывается при переходе в «Подключено».
- Голос: шутка — только в заголовке («Испеклось!»), статус в плашке — прямо
  («VPN включён»), кнопки — глаголом.
- Шрифты Marmelad, Rubik, PT Mono — `App/Fonts` (Google Fonts, лицензия OFL, тексты рядом).

## Лицензионная заметка

Проект линкует `OpenVPNAdapter` / `OpenVPN3` (AGPL-3.0). Для личной раздачи
через TestFlight обязательств не возникает; исходники предоставляются по запросу.
