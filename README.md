# personal-ios-client

Минимальный нативный iOS-клиент для личного сервера **AmneziaVPN** (протокол **OpenVPN over Cloak**).
Для установки себе и нескольким родственникам через **TestFlight**. Не для публикации в App Store (пока).

## Что где

- **[PLAN.md](PLAN.md)** — полный план разработки: архитектура, этапы (M0–M6) с проверками, риски.
- **[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)** — детальный план имплементации по шагам (Фаза 0 → M6), тест-стратегия, план коммитов, открытые вопросы.
- **[docs/FRAMEWORK-API.md](docs/FRAMEWORK-API.md)** — зафиксированный API `OpenVPNAdapter.framework`, выписанный из реальных заголовков. По нему пишется код провайдера.
- **[IMPLEMENTATION_PROMPT.md](IMPLEMENTATION_PROMPT.md)** — самодостаточный промпт для агента (выжимка исследования).

## Статус

Фаза 0 (всё, что не требует подписи и устройства): каркас проекта, ConfigKit с тестами,
скрипты фреймворка — **готово**. Дальше по [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md):
M1 (пустышка-туннель на iPhone) — ждёт одобрения Apple Developer аккаунта.

## Команды

Требуются: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make gen      # сгенерировать PersonalVPN.xcodeproj из project.yml
make build    # собрать оба таргета БЕЗ подписи (до одобрения аккаунта)
make test     # юнит-тесты ConfigKit — на Mac, телефон не нужен
make fetch    # скачать OpenVPNAdapter.framework (SHA-256 зафиксирован)
make verify   # ворота: arm64? символы Cloak? setPTCloak в заголовках?
```

Разобрать ключ Amnezia в читаемый JSON (вывод сохранять только в `Secrets/`):

```bash
python3 scripts/decode-vpnkey.py Secrets/my.vpnkey > Secrets/my-decoded.json
```

## Архитектура (коротко)

- SwiftUI-приложение + одно расширение `NEPacketTunnelProvider`. Device-only
  (VPN не работает в симуляторе), deployment target iOS 16.0.
- Готовый бинарный `OpenVPNAdapter.framework` от Amnezia: Cloak скомпилирован
  внутрь OpenVPN3 как транспорт. Со стороны Swift: `setPTCloak()` + блок
  `<cloak>` в тексте профиля.
- **ConfigKit** — локальный SPM-пакет со всей логикой разбора ключа `vpn://…`
  (zlib-распаковка, двойной разбор `last_config`, типы Cloak-полей, сборка
  профиля). Тестируется на Mac: `make test`.
- Расширение ничего не парсит: приложение при импорте собирает готовый текст
  `.ovpn` и передаёт его через `providerConfiguration`. App Group — для логов
  и конфига.

## Отладка на устройстве (M1+)

К процессу расширения **нельзя подключать отладчик Xcode** — Go-код Cloak под
отладчиком деградирует до ~5 fps и выглядит зависшим (golang/go#57651).
Каналы отладки:

- экран Logs в приложении (файл `tunnel.log` из App Group, кнопка «Поделиться»);
- Console.app с фильтром по subsystem `com.razhev.personalvpn`;
- `log collect --device-name "<iPhone>" --last 10m` по кабелю.

## Секреты

`Secrets/`, `*.vpnkey`, `*.ovpn` — в `.gitignore`. Реальные ключи не коммитятся
и не попадают в код/тесты (тесты синтезируют ключи сами).

## Лицензионная заметка

Проект линкует `OpenVPNAdapter` / `OpenVPN3` (AGPL-3.0). Для личной раздачи
через TestFlight обязательств не возникает; исходники предоставляются по запросу.
