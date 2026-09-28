# Лицензии: OVoC Client и сторонние компоненты

**OVoC Client** распространяется по **GNU General Public License v3** (текст — [LICENSE](LICENSE)).
Другой лицензии у приложения быть не может: внутри — AGPL-3.0-код OpenVPNAdapter/OpenVPN3 и
GPL-3.0-код Cloak, а `ConfigKit/Sources/ConfigKit/CloakTransform.swift` — порт `setupCloak()` из
amnezia-client (GPL-3.0). GPLv3 §13 разрешает объединять GPLv3- и AGPLv3-код; условия AGPL
продолжают действовать для его частей.

Что это значит на практике: каждому, кто получил сборку (в том числе внешнему тестеру
TestFlight), доступен полный исходный код этой сборки. Исходники приложения — этот репозиторий
(тег/коммит сборки пишет `make testflight` в `build/testflight/uploads.log`). Исходники фреймворка —
коммиты ниже + [patches/openvpn3-aead-auth-tag.patch](patches/openvpn3-aead-auth-tag.patch), сборка —
[scripts/build-framework-source.sh](scripts/build-framework-source.sh).

В приложении список компонентов и полные тексты лицензий — экран «О приложении» (нажать на
название на главном экране). Тексты лежат в [App/Licenses](App/Licenses) и [App/Fonts](App/Fonts).

## Компоненты

| Компонент | Версия / коммит | Лицензия | Текст в приложении |
|---|---|---|---|
| OVoC Client (этот репозиторий) | — | GPL-3.0 | `OVoCClient-GPL-3.0.txt` |
| [OpenVPNAdapter](https://github.com/amnezia-vpn/OpenVPNAdapter), форк Amnezia | `8bb3da5` (ветка `master-amnezia`) | AGPL-3.0 | `OpenVPNAdapter-AGPL-3.0.txt` |
| [OpenVPN 3](https://github.com/amnezia-vpn/openvpn3), форк Amnezia | `e901077` («3.8.5») + наш патч | AGPL-3.0 с разрешением линковки с OpenSSL | `OpenVPN3-LICENSE.txt`, `OpenVPNAdapter-NOTICE.txt` |
| mbed TLS | 2.7.12 (в составе OpenVPNAdapter) | Apache-2.0 | `OpenVPNAdapter-NOTICE.txt` |
| asio | 1.16.0 (в составе OpenVPNAdapter) | BSL-1.0 | `OpenVPNAdapter-NOTICE.txt` |
| LZ4 (`lib/`) | 1.8.3 (в составе OpenVPNAdapter) | BSD-2-Clause | `OpenVPNAdapter-NOTICE.txt` |
| [Cloak](https://github.com/cbeuw/Cloak), форк [amnezia-vpn/Cloak](https://github.com/amnezia-vpn/Cloak) | плагин `ck-ovpn-plugin.a` из OpenVPNAdapter `8bb3da5`, собран Amnezia (go1.22.2) | GPL-3.0 | `OVoCClient-GPL-3.0.txt` |
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

**Открытый вопрос.** Плагин Cloak вшит готовым бинарём Amnezia: известен репозиторий и ветка
исходников (`amnezia-vpn/Cloak`, `master-amnezia`) и версии модулей, но не точный коммит сборки.
Для полного соответствия GPL надёжнее собирать плагин из исходников самим (пункт «По желанию» в
[PLAN.md](PLAN.md)).

OpenVPN® is a registered trademark of OpenVPN Inc. OVoC Client не связан с Amnezia и OpenVPN Inc.
