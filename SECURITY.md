# Security policy

English · [Русский](#политика-безопасности)

OVoC Client holds a VPN key and carries all of a phone's traffic, so a security bug here can
expose the key or the traffic it was meant to protect. Please report such bugs privately.

## Reporting a vulnerability

Use GitHub's private reporting: **[Report a vulnerability](https://github.com/razhev/ovoc-client/security/advisories/new)**
(the Security tab → Report a vulnerability). Only the maintainer sees the report.

- Do not open a public issue for it.
- Do not send a real `vpn://` key. A synthetic key, or the steps to build one, is enough.
- Include the build number (TestFlight or the About screen), the iOS version, what an attacker
  can do, steps to reproduce, and logs if they help.

This is a one-person project maintained in spare time. You can expect a first reply within
7 days. After that we agree on a fix and a publication date; the fix ships as a TestFlight
build, and then a security advisory is published with credit to you, unless you prefer
otherwise.

## In scope

- The `vpn://` key or the generated OpenVPN profile leaving the iOS VPN configuration: in logs,
  files, the App Group container, crash reports or anything another app can read.
- Traffic leaving the tunnel when it should not: DNS, IPv6, traffic during a reconnect, or the
  "Outside VPN" exceptions matching more than the addresses listed in the catalog.
- A crafted key or profile that makes the app or the extension run code, crash repeatedly, or
  connect to a server other than the one in the key.
- The project's patches to OpenVPN 3 and Cloak in [`patches/`](patches) and the scripts that
  build the framework from source.

## Out of scope

- Bugs in OpenVPN 3, Cloak, OpenVPNAdapter or the AmneziaVPN server themselves. Report them to
  those projects (links in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)); if the app
  needs a new build because of them, a regular issue is fine.
- What the owner of the VPN server can see. The server is theirs; that is how a VPN works.
- A network blocking or recognising Cloak traffic. Open a regular issue for that.

## Supported versions

Fixes go into the next TestFlight build only. Older builds are not patched; TestFlight expires
every build after 90 days.

---

# Политика безопасности

OVoC Client хранит ключ VPN и пропускает через себя весь трафик телефона, поэтому ошибка
безопасности здесь может раскрыть ключ или тот трафик, который он должен защищать. Сообщайте о
таких ошибках закрыто.

## Как сообщить об уязвимости

Через закрытые отчёты GitHub: **[Report a vulnerability](https://github.com/razhev/ovoc-client/security/advisories/new)**
(вкладка Security → Report a vulnerability). Отчёт видит только автор проекта.

- Не открывайте об этом публичный issue.
- Не присылайте настоящий ключ `vpn://`. Достаточно синтетического ключа или шагов, как его
  собрать.
- Укажите номер сборки (в TestFlight или на экране «О приложении»), версию iOS, что может
  сделать атакующий, шаги воспроизведения и логи, если они помогают.

Проект ведёт один человек в свободное время. Первый ответ — в течение 7 дней. Дальше
договариваемся об исправлении и дате публикации; исправление выходит сборкой TestFlight, после
этого публикуется security advisory с благодарностью вам, если вы не против.

## Что относится к безопасности

- Ключ `vpn://` или собранный из него профиль OpenVPN выходит за пределы VPN-конфигурации iOS:
  в логи, файлы, контейнер App Group, отчёты о падениях или куда-то, где его прочтёт другое
  приложение.
- Трафик идёт мимо туннеля, когда не должен: DNS, IPv6, трафик во время переподключения, или
  исключения «Без VPN» захватывают больше адресов, чем перечислено в каталоге.
- Специально собранный ключ или профиль заставляет приложение или расширение выполнить код,
  падать раз за разом или подключаться не к тому серверу, что указан в ключе.
- Патчи проекта к OpenVPN 3 и Cloak в [`patches/`](patches) и скрипты сборки фреймворка из
  исходников.

## Что не относится

- Ошибки в самих OpenVPN 3, Cloak, OpenVPNAdapter или сервере AmneziaVPN. Сообщайте о них в
  эти проекты (ссылки — в [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)); если из-за них
  нужна новая сборка приложения, хватит обычного issue.
- То, что видит владелец VPN-сервера. Сервер принадлежит ему, так устроен любой VPN.
- Блокировка или распознавание трафика Cloak сетью. Для этого заведите обычный issue.

## Какие версии исправляются

Исправления выходят только в следующей сборке TestFlight. Старые сборки не исправляются;
TestFlight и так отключает каждую сборку через 90 дней.
