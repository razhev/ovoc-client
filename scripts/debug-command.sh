#!/usr/bin/env bash
set -euo pipefail

# DEBUG-мост: доставить команду запущенному приложению файлом, БЕЗ перезапуска.
#
#   scripts/debug-command.sh disconnect
#
# Почему не `launch-app.sh -autodisconnect`: принудительный перезапуск приложения
# через devicectl (--terminate-existing) убивает вместе с ним и процесс
# расширения — туннель падает с NEVPNConnectionErrorDomain 12, stopTunnel не
# вызывается вовсе, и «отключение по кнопке» так не проверить. Файл
# Documents/debug.<команда> DEBUG-сборка замечает раз в секунду и выполняет
# команду тем же кодом, что и кнопка. В Release этого кода нет.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_ID="com.razhev.ovocclient"
COMMAND="${1:-}"
case "$COMMAND" in
    disconnect) ;;
    *) echo "usage: scripts/debug-command.sh disconnect"; exit 2 ;;
esac

DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
IFS=$'\t' read -r UDID DEVICE_NAME OS_VERSION <<<"$DEVICE_LINE"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
date -u +%Y-%m-%dT%H:%M:%SZ >"$STAGE/debug.$COMMAND"

if ! xcrun devicectl device copy to --device "$UDID" \
        --domain-type appDataContainer --domain-identifier "$APP_BUNDLE_ID" \
        --source "$STAGE/debug.$COMMAND" --destination "Documents/debug.$COMMAND" >"$STAGE/copy.log" 2>&1; then
    echo "FAIL: не удалось доставить команду «${COMMAND}»:"
    grep -v "^[0-9][0-9]:" "$STAGE/copy.log" | tail -6 | sed 's/^/    /'
    exit 6
fi
echo "OK: команда «${COMMAND}» доставлена; приложение должно быть запущено (DEBUG-сборка)"
