# Короткие команды проекта. Все сборки — CLI, без кликов в Xcode.

PROJECT := PersonalVPN.xcodeproj
SCHEME  := PersonalVPN

.PHONY: gen build test fetch verify clean

## Сгенерировать PersonalVPN.xcodeproj из project.yml
gen:
	xcodegen generate

## Собрать оба таргета БЕЗ подписи (работает до одобрения Apple Developer)
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

clean:
	rm -rf build DerivedData
