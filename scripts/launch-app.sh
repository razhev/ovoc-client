#!/usr/bin/env bash
set -euo pipefail

# Перезапускает PersonalVPN на подключённом iPhone с аргументами запуска.
# DEBUG-сборка понимает -autoconnect и -autodisconnect: это позволяет гонять
# попытки подключения с Mac (make connect / make disconnect) и одновременно
# снимать диагностику, не нажимая ничего на телефоне.
#
#   scripts/launch-app.sh [аргументы приложения…]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_ID="com.razhev.personalvpn"

DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
UDID="$(cut -f1 <<<"$DEVICE_LINE")"

if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing \
        "$APP_BUNDLE_ID" "$@" >/dev/null 2>&1; then
    echo "FAIL: приложение не запустилось — телефон заблокирован или приложение не установлено."
    exit 7
fi
echo "OK: PersonalVPN перезапущен${*:+ с аргументами: $*}"
