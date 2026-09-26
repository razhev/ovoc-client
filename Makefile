# Короткие команды проекта. Все сборки — CLI, без кликов в Xcode.

PROJECT := OVoCClient.xcodeproj
SCHEME  := OVoCClient

.PHONY: scene gen build test framework fetch verify devices ddi install push-key connect disconnect dummy release-check strings-check icon testflight logs crashlogs clean

## Сгенерировать OVoCClient.xcodeproj из project.yml
gen:
	xcodegen generate

## Собрать оба таргета БЕЗ подписи — ворота компиляции (не нужны аккаунт, телефон, сеть)
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' build \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

## Юнит-тесты ConfigKit — на Mac, без телефона и подписи
test:
	cd ConfigKit && swift test

## Собрать OpenVPNAdapter.framework из исходников Amnezia с нашим исправлением
## (patches/openvpn3-aead-auth-tag.patch). ОСНОВНОЙ способ получить фреймворк.
framework:
	./scripts/build-framework-source.sh

## Скачать ГОТОВЫЙ фреймворк v1.0.42. НЕ для работы: в нём дефект метки GCM, VPN с ним
## не передаёт ни одного пакета (см. docs/DEVICE-TESTING.md). Оставлено для сравнения.
fetch:
	./scripts/fetch-framework.sh

## Ворота качества: arm64? символы Cloak? setPTCloak в заголовках?
verify:
	./scripts/verify-framework.sh

## Какие iPhone видит Mac и готовы ли они к установке
devices:
	@python3 scripts/find-device.py --list

## Смонтировать на телефон образ разработчика (DDI). Нужен доступ к gs.apple.com
## БЕЗ VPN; держится до перезагрузки телефона. make install делает это сам.
ddi:
	@./scripts/mount-ddi.sh

## Подписанная сборка → установка на подключённый iPhone → запуск.
## Несколько устройств: make install DEVICE=<udid|имя>
install: gen
	./scripts/install-device.sh

## DEBUG-мост: доставить Secrets/my.vpnkey в установленное приложение — тот же код
## импорта, что у экрана «Добавить ключ», но без рук (ключ не попадает в сборку).
## Другой файл: make push-key KEY=путь
push-key:
	@./scripts/push-key.sh $(KEY)

## Отладка с Mac: перезапустить приложение на телефоне и сразу подключить / отключить
## VPN (только DEBUG-сборка; телефон должен быть разблокирован)
connect:
	@./scripts/launch-app.sh -autoconnect

disconnect:
	@./scripts/debug-command.sh disconnect

## Диагностика без сервера: профиль-пустышка M1 (подпись, entitlements, App Group,
## загрузка фреймворка). ЗАТИРАЕТ боевой профиль — после неё ключ импортировать заново.
dummy:
	@./scripts/launch-app.sh -dummyprofile

## Ворота Release: в сборке нет DEBUG-моста и нет ни одного файла ключа
release-check: gen
	./scripts/check-release.sh

## Каталог строк ru/en: каждый русский литерал App/*.swift есть в
## App/Localizable.xcstrings и переведён; мёртвых ключей нет
strings-check:
	@python3 scripts/check-localization.py

## Пересобрать сцену главного экрана App/Scene/scene.html (изба, печь, Вовка, анимации)
## из scripts/pechka/scene.mjs — того же кода, что рисует холст Design. Нужен Node.js.
scene:
	node scripts/pechka/build-scene.mjs

## Перерисовать иконку 1024×1024 (App/Assets.xcassets/AppIcon.appiconset/AppIcon.png)
## скриптом на CoreGraphics — без внешних зависимостей
icon:
	swift scripts/make-app-icon.swift

## Release-архив → загрузка в TestFlight через API-ключ App Store Connect
## (Secrets/asc.env, ключ в ~/.private_keys/). Перед этим сам гоняет release-check.
## Номер сборки (CURRENT_PROJECT_VERSION в project.yml) поднимать руками — docs/TESTFLIGHT.md
testflight: gen
	./scripts/upload-testflight.sh

## Забрать логи с телефона в build/logs/latest/ (tunnel.log, app.log, last_error.txt)
logs:
	@./scripts/device-logs.sh

## То же + отчёты о падениях расширения/приложения (.ips)
crashlogs:
	@./scripts/device-logs.sh --crashes

## Только продукты сборки и логи: build/cache с фреймворком (82 МБ) не трогаем
clean:
	rm -rf build/DerivedData build/logs DerivedData
