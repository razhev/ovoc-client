# Разработка OVoC Client

Команды, устройство проекта и отладка на устройстве. Для пользователя приложения достаточно
[README.ru.md](../README.ru.md); история изменений — в [CHANGELOG.md](../CHANGELOG.md),
план и как он выполнялся — в [history/PLAN.md](history/PLAN.md). Как оформить правку и
подписать форк своим аккаунтом — [CONTRIBUTING.md](../CONTRIBUTING.md#как-помочь-проекту).

## Команды

Требуются: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
Для `make framework` нужен также `go` в `PATH` с поддержкой выбора toolchain:
скрипт закрепляет `GOTOOLCHAIN=go1.22.2`. Первая сборка требует сети для загрузки
исходников, Go 1.22.2 и модулей. Cloak собирается из исходников вместе с адаптером.

```bash
make gen        # сгенерировать OVoCClient.xcodeproj из project.yml
make build      # собрать оба таргета БЕЗ подписи — быстрая проверка компиляции
make test       # ConfigKit, reconnect, IPv6, UTF-8 логов и происхождение framework — на Mac
make test-cloak-refcount # после make framework: гонка ссылок Connection под ThreadSanitizer
make test-cloak-send # после make framework: очередь Cloak, ошибки и остановка под ASan/UBSan
make framework  # исходники OpenVPNAdapter + Cloak, наши патчи, Go race tests и C++ send-тест
make framework-manifest # положить privacy manifest в уже собранный фреймворк (make framework делает сам)
make fetch      # готовый бинарь v1.0.42 — НЕРАБОЧИЙ (дефект метки GCM), только для сравнения
make verify     # arm64, Cloak, API + квитанция исходников, всех патчей и архива Cloak

make devices    # какие iPhone видит Mac и готовы ли они к установке
make ddi        # смонтировать на телефон образ разработчика (VPN на Mac выключить)
make install    # подписанная сборка → установка на подключённый iPhone → запуск
make push-key   # DEBUG: доставить Secrets/my.vpnkey в приложение тем же кодом, что экран импорта
make release-check # ворота Release: нет DEBUG-моста и файлов ключа; privacy manifest и лицензии на месте
make strings-check # каталог строк ru/en сходится с кодом (App/Localizable.xcstrings)
make icon       # перерисовать иконку 1024×1024 скриптом (scripts/make-app-icon.swift)
make scene      # пересобрать сцену главного экрана App/Scene/scene.html (нужен Node.js)
make testflight # Release-архив → загрузка в TestFlight (API-ключ в Secrets/asc.env, см. docs/TESTFLIGHT.md)
make logs       # забрать логи с телефона в build/logs/latest/
make crashlogs  # то же + отчёты о падениях расширения/приложения
```

`OVoCClient.xcodeproj` пересоздаётся каждым `make gen` — все настройки подписи живут в
`project.yml`, в интерфейсе Xcode ничего не настраиваем.

`make framework` запускает Go-тесты реестра соединений с `-race` и C++-тест очереди
отправки; `make test-cloak-refcount` запускается отдельно. Эти нативные проверки
не входят в `make test`. Версии исходников и состав квитанции описаны в
[FRAMEWORK-API.md](FRAMEWORK-API.md#происхождение-бинаря).

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
- `OpenVPNAdapter.framework` от Amnezia, **собранный из исходников с нашими патчами**
  (`make framework`, `patches/`): в их готовом бинаре клиент не записывает метку
  подлинности GCM, и сервер отбрасывает каждый пакет. Cloak скомпилирован
  внутрь OpenVPN3 как транспорт; его Go-библиотека тоже пересобирается с защитой
  реестра соединений. Исправления C++ защищают счётчики ссылок и выносят отправку
  из цикла OpenVPN в последовательную фоновую очередь. Со стороны Swift:
  `setPTCloak()` + блок `<cloak>` в тексте профиля.
- **ConfigKit** — локальный SPM-пакет со всей логикой разбора ключа `vpn://…`
  (zlib-распаковка, двойной разбор `last_config`, типы Cloak-полей, сборка
  профиля). Тестируется на Mac: `make test`.
- Маршруты и DNS остаются на месте при resetTun/reconnect; старые настройки заменяются
  новыми без промежуточного снятия. При окончательном отключении их снимает iOS.
  Автотесты этой границы находятся в `Tests/TunnelRuntimeTests`, проверка отсутствия утечки
  на телефоне — [«Регрессия P1»](DEVICE-TESTING.md).
- Импорт выбирает фактический endpoint Cloak (`remote` → `RemoteHost` → `hostName`) и
  фиксирует один IPv4 в транспорте и маршруте исключения. После смены IP домена ключ нужно
  импортировать заново. Профили, сохранённые до этого исправления с доменом или отдельным
  адресом Cloak, тоже нужно переимпортировать.
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

Подробности и разбор типовых ошибок — [DEVICE-TESTING.md](DEVICE-TESTING.md).

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

