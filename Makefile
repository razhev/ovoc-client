# Короткие команды проекта. Все сборки — CLI, без кликов в Xcode.

PROJECT := PersonalVPN.xcodeproj
SCHEME  := PersonalVPN

.PHONY: gen build test fetch verify devices install logs crashlogs clean

## Сгенерировать PersonalVPN.xcodeproj из project.yml
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

## Скачать OpenVPNAdapter.framework (с фиксацией SHA-256)
fetch:
	./scripts/fetch-framework.sh

## Ворота качества: arm64? символы Cloak? setPTCloak в заголовках?
verify:
	./scripts/verify-framework.sh

## Какие iPhone видит Mac и готовы ли они к установке
devices:
	@python3 scripts/find-device.py --list

## Подписанная сборка → установка на подключённый iPhone → запуск.
## Несколько устройств: make install DEVICE=<udid|имя>
install: gen
	./scripts/install-device.sh

## Забрать логи с телефона в build/logs/latest/ (tunnel.log, app.log, last_error.txt)
logs:
	@./scripts/device-logs.sh

## То же + отчёты о падениях расширения/приложения (.ips)
crashlogs:
	@./scripts/device-logs.sh --crashes

## Только продукты сборки и логи: build/cache с фреймворком (82 МБ) не трогаем
clean:
	rm -rf build/DerivedData build/logs DerivedData
