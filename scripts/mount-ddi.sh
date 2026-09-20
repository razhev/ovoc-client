#!/usr/bin/env bash
set -euo pipefail

# Монтирует Developer Disk Image (DDI) на подключённый iPhone — `make ddi`.
#
# DDI — служебный образ с инструментами разработчика; без него на телефон
# нельзя ни собрать «под устройство», ни запустить приложение. Образ
# персонализируется: Mac ходит на сервер подписи Apple (gs.apple.com).
# Смонтированный DDI живёт до перезагрузки телефона.
#
# Зачем отдельный шаг: при отказе xcodebuild минуту ждёт устройство и пишет
# только «The developer disk image could not be mounted». Здесь причина
# расшифровывается. Самая коварная — VPN на Mac: сервер подписи Apple
# отвечает 401 на запросы с IP дата-центров, хотя остальные сервисы Apple
# через тот же VPN работают.
#
#   scripts/mount-ddi.sh [UDID]     # без аргумента устройство ищется само

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
    DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
    UDID="$(cut -f1 <<<"$DEVICE_LINE")"
fi

LOG_DIR="$ROOT/build/logs"
DDI_LOG="$LOG_DIR/ddi.log"
mkdir -p "$LOG_DIR"

if xcrun devicectl device info ddiServices --device "$UDID" --timeout 120 >"$DDI_LOG" 2>&1 \
        && ! grep -q "^ERROR:" "$DDI_LOG"; then
    echo "PASS DDI: образ разработчика смонтирован"
    exit 0
fi

echo "FAIL DDI: образ разработчика не смонтирован."
if grep -q -E "HTTPUnauthorized|NetworkUnauthorized" "$DDI_LOG"; then
    echo "  Причина: сервер подписи Apple (gs.apple.com) ответил 401 Unauthorized."
    echo "  Так он отвечает на запросы с IP дата-центров — то есть мешает VPN на этом Mac."
    echo "  Что делать: отключить VPN на Mac (или добавить gs.apple.com в исключения"
    echo "  раздельного туннелирования) → make ddi → VPN можно включить обратно:"
    echo "  смонтированный образ держится до перезагрузки телефона."
elif grep -q -i -E "passcode|locked" "$DDI_LOG"; then
    echo "  Причина: телефон заблокирован. Разблокируйте его и повторите."
elif grep -q -i -E "network|timed out|offline|could not connect" "$DDI_LOG"; then
    echo "  Причина похожа на сетевую: Mac должен достучаться до gs.apple.com."
else
    echo "  Причина не распознана. Если телефон разблокирован и сеть в порядке — возможно,"
    echo "  iOS на телефоне новее, чем знает этот Xcode: обновите Xcode."
fi
echo "  Ошибка дословно (полностью: ${DDI_LOG#"$ROOT"/}):"
grep -E "Error mounting image|AMAuthInstall|CoreDeviceError" "$DDI_LOG" | sed 's/^[[:space:]]*/    /' | sort -u | head -5
exit 4
