#!/usr/bin/env bash
set -euo pipefail

# Перезапускает OVoC Client на подключённом iPhone с аргументами запуска.
# DEBUG-сборка понимает -autoconnect и -autodisconnect: это позволяет гонять
# попытки подключения с Mac (make connect / make disconnect) и одновременно
# снимать диагностику, не нажимая ничего на телефоне.
#
#   scripts/launch-app.sh [аргументы приложения…]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_ID="com.razhev.ovocclient"

DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
UDID="$(cut -f1 <<<"$DEVICE_LINE")"

# «--» обязателен: без него devicectl разбирает -autoconnect как свои опции (-a -u -t …).
LAUNCH_LOG="$(mktemp)"
trap 'rm -f "$LAUNCH_LOG"' EXIT
if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing \
        "$APP_BUNDLE_ID" -- "$@" >"$LAUNCH_LOG" 2>&1; then
    echo "FAIL: приложение не запустилось (телефон заблокирован? приложение установлено?):"
    grep -v -E "^[0-9]{2}:[0-9]{2}:[0-9]{2}" "$LAUNCH_LOG" | head -6 | sed 's/^/    /'
    exit 7
fi
echo "OK: OVoC Client перезапущен${*:+ с аргументами: $*}"
