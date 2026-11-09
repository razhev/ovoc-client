# Contributing to OVoC Client

English · [Русский](#как-помочь-проекту)

Thank you for helping. OVoC Client is a small project with one maintainer, so this page tells
you what fits the project and how to make a change that is easy to review. Issues and pull
requests are welcome in English or Russian.

## What the project is

A native iPhone app for connecting to your own OpenVPN over Cloak server with an Amnezia
`vpn://` key. No servers, accounts or analytics of its own; distributed through TestFlight.

Not planned right now, so please ask in an issue before working on them:

- other protocols (AmneziaWG, WireGuard, plain OpenVPN);
- iPad, Mac or Apple TV versions;
- publishing in the App Store (the README explains why);
- anything that sends data from the phone to a third party.

## Reporting a bug

Use the **Bug report** template. Attach the files from the app's Logs screen (Share sends them
all). They contain the server address but never the key; remove the address if you prefer.

**Never paste a `vpn://` key, an `.ovpn` profile or a screenshot that shows either.** Anyone
who has the key can use your server. If you posted one by mistake, revoke it on the server and
issue a new one; deleting the comment is not enough.

Security problems go through [SECURITY.md](SECURITY.md), not through issues.

## Building and testing

The short version is in the [README](README.md#build-from-source), the full one in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) (in Russian). Without an Apple Developer account you
can still run everything that does not need a phone:

```bash
make test           # ConfigKit, tunnel runtime and framework provenance tests on the Mac
make strings-check  # every Russian string in App/*.swift is in the catalog and translated
make framework      # build OpenVPNAdapter and Cloak from source (needs Go and network)
make build          # compile both targets without signing
```

CI runs `make test` and `make strings-check` on every pull request. A VPN only works on a real
iPhone, and the Network Extension entitlement needs a paid Apple Developer account.

### Running a fork on your own iPhone

Bundle IDs, the App Group and the Team ID belong to the maintainer's account. To sign your own
build, replace them in:

- `project.yml`: `DEVELOPMENT_TEAM`, `bundleIdPrefix` and both `PRODUCT_BUNDLE_IDENTIFIER`;
- `App/OVoCClient.entitlements` and `PacketTunnel/PacketTunnel.entitlements`: the App Group;
- `Shared/SharedPaths.swift` (`appGroupID`) and `App/TunnelManager.swift` (`tunnelBundleID`);
- `scripts/install-device.sh`, `push-key.sh`, `launch-app.sh`, `debug-command.sh`,
  `device-logs.sh`: `APP_BUNDLE_ID` and `APP_GROUP_ID`;
- `Config/ExportOptions.plist`: `teamID`, only if you upload to TestFlight.

Other `com.razhev.ovocclient` strings in the code are log and queue labels and can stay. Do not
commit these replacements.

## Making a change

- Start from `main` and keep one topic per pull request.
- Open an issue first for anything larger than a bug fix, so we agree on the approach before
  you spend time on it.
- Russian is the base language of the interface. A new UI string is written in Russian in the
  code and gets an English translation in `App/Localizable.xcstrings`. Log messages are in
  English.
- If the change touches the tunnel (`PacketTunnel/`, `Shared/`, `patches/`), say in the pull
  request how you tested it on a device. [docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md) has
  the checks the project uses.
- User-visible changes get a line in [CHANGELOG.md](CHANGELOG.md).
- Commit messages are in English and start with a type, as in the history: `feat:`, `fix:`,
  `docs:`, `chore:`, `test:`.
- No real keys, server addresses or Apple account identifiers in code, tests or logs. Tests
  build synthetic keys (`ConfigKit/Tests/ConfigKitTests/SyntheticKey.swift`).

## License

The project is licensed under GPL-3.0. By sending a pull request you agree that your change is
distributed under the same license.

---

# Как помочь проекту

Спасибо за помощь. Проект ведёт один человек, поэтому здесь описано, что в него вписывается и
как сделать правку, которую легко проверить. Issues и pull requests принимаются на русском или
английском.

## Что это за проект

Нативное приложение для iPhone, которое подключается к вашему собственному серверу OpenVPN over
Cloak по ключу Amnezia `vpn://`. Своих серверов, аккаунтов и аналитики нет; раздаётся через
TestFlight.

Сейчас не планируется — прежде чем браться, спросите в issue:

- другие протоколы (AmneziaWG, WireGuard, обычный OpenVPN);
- версии для iPad, Mac или Apple TV;
- публикация в App Store (почему — в README);
- всё, что отправляет данные с телефона третьим лицам.

## Как сообщить об ошибке

Используйте шаблон **Bug report**. Приложите файлы с экрана «Логи» в приложении («Поделиться»
отдаёт их все). В них есть адрес сервера, но никогда нет ключа; адрес можно вырезать.

**Никогда не вставляйте ключ `vpn://`, профиль `.ovpn` или скриншот, где они видны.** Любой,
у кого есть ключ, может пользоваться вашим сервером. Если ключ опубликован по ошибке, отзовите
его на сервере и выпустите новый: удалить комментарий недостаточно.

Об уязвимостях — через [SECURITY.md](SECURITY.md), а не через issues.

## Сборка и тесты

Кратко — в [README.ru.md](README.ru.md#сборка-из-исходников), подробно — в
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Без аккаунта Apple Developer можно запустить всё,
что не требует телефона:

```bash
make test           # тесты ConfigKit, сетевых настроек туннеля и происхождения фреймворка на Mac
make strings-check  # каждая русская строка App/*.swift есть в каталоге и переведена
make framework      # собрать OpenVPNAdapter и Cloak из исходников (нужны Go и сеть)
make build          # собрать оба таргета без подписи
```

CI запускает `make test` и `make strings-check` на каждый pull request. VPN работает только на
настоящем iPhone, а entitlement Network Extension требует платного аккаунта Apple Developer.

### Свой форк на своём iPhone

Bundle ID, App Group и Team ID принадлежат аккаунту автора. Чтобы подписать свою сборку,
замените их в файлах:

- `project.yml`: `DEVELOPMENT_TEAM`, `bundleIdPrefix` и оба `PRODUCT_BUNDLE_IDENTIFIER`;
- `App/OVoCClient.entitlements` и `PacketTunnel/PacketTunnel.entitlements`: App Group;
- `Shared/SharedPaths.swift` (`appGroupID`) и `App/TunnelManager.swift` (`tunnelBundleID`);
- `scripts/install-device.sh`, `push-key.sh`, `launch-app.sh`, `debug-command.sh`,
  `device-logs.sh`: `APP_BUNDLE_ID` и `APP_GROUP_ID`;
- `Config/ExportOptions.plist`: `teamID`, только если загружаете в TestFlight.

Остальные строки `com.razhev.ovocclient` в коде — метки логов и очередей, их можно не трогать.
Эти замены не коммитьте.

## Как оформить правку

- Ветка от `main`, одна тема на pull request.
- Для всего крупнее исправления ошибки сначала заведите issue, чтобы договориться о подходе до
  того, как вы потратите время.
- Базовый язык интерфейса — русский. Новая строка интерфейса пишется в коде по-русски и
  получает английский перевод в `App/Localizable.xcstrings`. Сообщения в логах — по-английски.
- Если правка затрагивает туннель (`PacketTunnel/`, `Shared/`, `patches/`), напишите в pull
  request, как проверяли её на телефоне. Проверки проекта — в
  [docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md).
- Заметные пользователю изменения — строкой в [CHANGELOG.md](CHANGELOG.md).
- Сообщения коммитов — по-английски, с типом в начале, как в истории: `feat:`, `fix:`,
  `docs:`, `chore:`, `test:`.
- Никаких настоящих ключей, адресов серверов и идентификаторов аккаунта Apple в коде, тестах и
  логах. Тесты собирают синтетические ключи (`ConfigKit/Tests/ConfigKitTests/SyntheticKey.swift`).

## Лицензия

Проект распространяется по GPL-3.0. Отправляя pull request, вы соглашаетесь, что ваша правка
распространяется по той же лицензии.
