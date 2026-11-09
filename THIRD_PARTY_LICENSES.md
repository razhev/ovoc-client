# Лицензии: OVoC Client и сторонние компоненты

**OVoC Client** распространяется по **GNU General Public License v3** (текст — [LICENSE](LICENSE)).
Другой лицензии у приложения быть не может: внутри — AGPL-3.0-код OpenVPNAdapter/OpenVPN3 и
GPL-3.0-код Cloak, а `ConfigKit/Sources/ConfigKit/CloakTransform.swift` — порт `setupCloak()` из
amnezia-client (GPL-3.0). GPLv3 §13 разрешает объединять GPLv3- и AGPLv3-код; условия AGPL
продолжают действовать для его частей.

Что это значит на практике: каждому, кто получил сборку (в том числе внешнему тестеру
TestFlight), доступен полный исходный код этой сборки. Исходники приложения — этот репозиторий;
исходник выпущенной сборки помечен тегом вида `v0.1.0-build15`
([список тегов](https://github.com/razhev/ovoc-client/tags)). Исходники фреймворка — коммиты
ниже и патчи из [patches/](patches): три для OpenVPN 3 (метка AEAD, счётчик ссылок Connection,
очередь отправки Cloak) и один для Cloak (реестр соединений). Сборка —
[scripts/build-framework-source.sh](scripts/build-framework-source.sh) и
[scripts/build-cloak-source.sh](scripts/build-cloak-source.sh).

В приложении список компонентов и полные тексты лицензий — экран «О приложении» (нажать на
название на главном экране). Тексты лежат в [App/Licenses](App/Licenses) и [App/Fonts](App/Fonts).

## Компоненты

| Компонент | Версия / коммит | Лицензия | Текст в приложении |
|---|---|---|---|
| OVoC Client (этот репозиторий) | — | GPL-3.0 | `OVoCClient-GPL-3.0.txt` |
| [OpenVPNAdapter](https://github.com/amnezia-vpn/OpenVPNAdapter), форк Amnezia | `8bb3da5` (ветка `master-amnezia`) | AGPL-3.0 | `OpenVPNAdapter-AGPL-3.0.txt` |
| [OpenVPN 3](https://github.com/amnezia-vpn/openvpn3), форк Amnezia | `e901077` («3.8.5») + патчи AEAD, Connection refcount и очереди отправки | AGPL-3.0 с разрешением линковки с OpenSSL | `OpenVPN3-LICENSE.txt`, `OpenVPNAdapter-NOTICE.txt` |
| mbed TLS | 2.7.12 (в составе OpenVPNAdapter) | Apache-2.0 | `OpenVPNAdapter-NOTICE.txt` |
| asio | 1.16.0 (в составе OpenVPNAdapter) | BSL-1.0 | `OpenVPNAdapter-NOTICE.txt` |
| LZ4 (`lib/`) | 1.8.3 (в составе OpenVPNAdapter) | BSD-2-Clause | `OpenVPNAdapter-NOTICE.txt` |
| [Cloak](https://github.com/cbeuw/Cloak), форк [amnezia-vpn/Cloak](https://github.com/amnezia-vpn/Cloak) | `884ac4f` + патч реестра соединений, собран из исходников Go 1.22.2 | GPL-3.0 | `OVoCClient-GPL-3.0.txt` |
| Go (рантайм и стандартная библиотека плагина) | go1.22.2 | BSD-3-Clause | `Go-LICENSE.txt` |
| andybalholm/brotli | v1.0.6 | MIT | `Cloak-Go-modules.txt` |
| cbeuw/connutil | v0.0.0-20200411215123-966bfaa51ee3 | Apache-2.0 | `Cloak-Go-modules.txt` |
| cloudflare/circl | v1.3.7 | BSD-3-Clause | `Cloak-Go-modules.txt` |
| gorilla/websocket | v1.5.1 | BSD-2-Clause | `Cloak-Go-modules.txt` |
| juju/ratelimit | v1.0.2 | LGPL-3.0 с исключением для статической линковки | `Cloak-Go-modules.txt` |
| klauspost/compress | v1.17.4 | BSD-3-Clause (+ лицензии вложенных пакетов) | `Cloak-Go-modules.txt` |
| refraction-networking/utls | v1.6.4 | BSD-3-Clause | `Cloak-Go-modules.txt` |
| sirupsen/logrus | v1.9.3 | MIT | `Cloak-Go-modules.txt` |
| golang.org/x/crypto, x/net, x/sys | v0.22.0, v0.21.0, v0.19.0 | BSD-3-Clause + PATENTS | `Cloak-Go-modules.txt` |
| Шрифты Marmelad, Rubik, PT Mono | Google Fonts | OFL-1.1 | `OFL-marmelad.txt`, `OFL-rubik.txt`, `OFL-ptmono.txt` |

Откуда тексты (2026-09-27): `OpenVPNAdapter-AGPL-3.0.txt`, `OpenVPNAdapter-NOTICE.txt` (сводный
файл upstream: OpenVPN 3, mbed TLS, asio, LZ4) и `OpenVPN3-LICENSE.txt` — из исходников
`build/OpenVPNAdapter-src` на коммитах выше; `Go-LICENSE.txt` — из дистрибутива Go;
`Cloak-Go-modules.txt` — файлы `LICENSE`/`PATENTS` модулей из кэша Go-модулей, версии — те, что
записаны в бинаре плагина; GPL-3.0 — канонический текст FSF.

Плагин Cloak собирается из исходников, а не берётся готовым бинарём Amnezia:
`amnezia-vpn/Cloak` на коммите `884ac4f` с патчем
[patches/cloak-connection-registry.patch](patches/cloak-connection-registry.patch), Go 1.22.2
закреплён в скрипте. Хеши исходников, патчей и архива записываются в квитанцию фреймворка —
[docs/FRAMEWORK-API.md](docs/FRAMEWORK-API.md#происхождение-бинаря).

OpenVPN® is a registered trademark of OpenVPN Inc. OVoC Client не связан с Amnezia и OpenVPN Inc.
