#!/usr/bin/env bash
set -euo pipefail

# DEBUG-мост M3: доставить ключ vpn:// в установленное на iPhone приложение —
# `make push-key`. Экрана импорта ещё нет (он появится в M4).
#
# Ключ копируется в Documents приложения через devicectl; DEBUG-сборка при
# запуске находит файл, прогоняет через ConfigKit, записывает профиль туннеля
# и СРАЗУ удаляет файл. Ключ не входит ни в один вход сборки, поэтому в
# Release/TestFlight попасть не может — гарантия структурная, а не «по флажку».
#
#   scripts/push-key.sh [путь-к-ключу]      # по умолчанию Secrets/my.vpnkey
#
# Сам ключ нигде не печатается.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_ID="com.razhev.personalvpn"
KEY_FILE="${1:-Secrets/my.vpnkey}"

if [[ ! -s "$KEY_FILE" ]]; then
    echo "FAIL: нет файла ключа $KEY_FILE."
    echo "      В Amnezia: Поделиться → формат «For the AmneziaVPN app» → Копировать, затем:"
    echo "      mkdir -p Secrets && pbpaste > Secrets/my.vpnkey"
    exit 2
fi
if [[ "$(head -c 6 "$KEY_FILE")" != "vpn://" ]]; then
    echo "FAIL: $KEY_FILE не начинается с vpn:// — это не ключ формата «For the AmneziaVPN app»."
    exit 2
fi

DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
IFS=$'\t' read -r UDID DEVICE_NAME OS_VERSION <<<"$DEVICE_LINE"

# Копируем под фиксированным именем: исходное имя файла приложению не важно.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$KEY_FILE" "$STAGE/debug.vpnkey"

echo "Копирую ключ в приложение на «${DEVICE_NAME}»…"
if ! xcrun devicectl device copy to --device "$UDID" \
        --domain-type appDataContainer --domain-identifier "$APP_BUNDLE_ID" \
        --source "$STAGE/debug.vpnkey" --destination "Documents/debug.vpnkey" >"$STAGE/copy.log" 2>&1; then
    echo "FAIL: не удалось скопировать ключ:"
    grep -v "^[0-9][0-9]:" "$STAGE/copy.log" | tail -6 | sed 's/^/    /'
    echo "      Приложение установлено? (make install). Телефон разблокирован?"
    exit 6
fi

# Перезапуск: DEBUG-сборка импортирует ключ при старте и удаляет файл.
if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing "$APP_BUNDLE_ID" >/dev/null 2>&1; then
    echo "Ключ скопирован, но приложение не перезапустилось — разблокируйте телефон"
    echo "и откройте PersonalVPN пальцем: ключ импортируется при запуске."
    exit 7
fi

echo "Готово. В приложении должно появиться «Ключ импортирован» и «Профиль: сервер»."
echo "Дальше: «Подключить» → подождать рукопожатие Cloak (несколько секунд) → make logs"
