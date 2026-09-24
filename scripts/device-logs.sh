#!/usr/bin/env bash
set -euo pipefail

# Забирает логи с подключённого iPhone на Mac — без Xcode и без sudo.
#
#   scripts/device-logs.sh            # tunnel.log, app.log, last_error.txt из App Group
#   scripts/device-logs.sh --crashes  # + отчёты о падениях расширения/приложения (.ips)
#
# Файлы кладутся в build/logs/<время>/, на последний набор указывает
# симлинк build/logs/latest. Это основной канал отладки: отладчик к
# расширению подключать нельзя (golang/go#57651), а `log collect` с
# устройства требует sudo.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_GROUP_ID="group.com.razhev.ovocclient"
WITH_CRASHES=0
[[ "${1:-}" == "--crashes" ]] && WITH_CRASHES=1

DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
IFS=$'\t' read -r UDID DEVICE_NAME OS_VERSION <<<"$DEVICE_LINE"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/build/logs/$STAMP"
mkdir -p "$OUT"

# ── 1. Файлы из App Group ──
# Листинг контейнера — заодно проверка, что App Group вообще выдана сборке.
if ! xcrun devicectl device info files --device "$UDID" \
        --domain-type appGroupDataContainer --domain-identifier "$APP_GROUP_ID" \
        --no-recurse >"$OUT/group-listing.txt" 2>&1; then
    echo "FAIL: контейнер App Group $APP_GROUP_ID недоступен:"
    sed 's/^/    /' "$OUT/group-listing.txt" | tail -8
    echo "Причины: приложение не установлено (make install) либо App Group не попала в подпись."
    exit 1
fi

for FILE in tunnel.log app.log last_error.txt; do
    if xcrun devicectl device copy from --device "$UDID" \
            --domain-type appGroupDataContainer --domain-identifier "$APP_GROUP_ID" \
            --source "$FILE" --destination "$OUT/$FILE" >/dev/null 2>&1 && [[ -f "$OUT/$FILE" ]]; then
        echo "OK   $FILE ($(wc -c <"$OUT/$FILE" | tr -d ' ') байт)"
    else
        echo "—    $FILE: на устройстве нет"
    fi
done

# ── 2. Отчёты о падениях ──
if [[ "$WITH_CRASHES" -eq 1 ]]; then
    mkdir -p "$OUT/crashes"
    LISTING="$OUT/crashes/listing.json"
    xcrun devicectl device info files --device "$UDID" --domain-type systemCrashLogs \
        --json-output "$LISTING" >/dev/null 2>&1 || true
    # Имена отчётов: <процесс>-<дата>.ips; JetsamEvent — убийство по памяти (лимит appex ~50 МБ).
    NAMES="$(python3 - "$LISTING" <<'PY' || true
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
found = set()
def walk(node):
    if isinstance(node, dict):
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
    elif isinstance(node, str) and node.endswith(".ips"):
        base = node.rsplit("/", 1)[-1]
        if base.startswith(("PacketTunnel", "OVoCClient", "JetsamEvent")):
            found.add(node)
walk(data)
print("\n".join(sorted(found)[-15:]))
PY
)"
    if [[ -z "$NAMES" ]]; then
        echo "Отчётов о падениях PacketTunnel / OVoCClient / Jetsam на устройстве нет."
    else
        while IFS= read -r NAME; do
            [[ -z "$NAME" ]] && continue
            if xcrun devicectl device copy from --device "$UDID" --domain-type systemCrashLogs \
                    --source "$NAME" --destination "$OUT/crashes/$(basename "$NAME")" >/dev/null 2>&1; then
                echo "OK   crashes/$(basename "$NAME")"
            fi
        done <<<"$NAMES"
    fi
fi

ln -sfn "$STAMP" "$ROOT/build/logs/latest"
echo ""
echo "Логи «${DEVICE_NAME}» (iOS $OS_VERSION): build/logs/latest/"

for FILE in last_error.txt app.log tunnel.log; do
    if [[ -s "$OUT/$FILE" ]]; then
        echo ""
        echo "── $FILE (хвост) ──"
        tail -n 40 "$OUT/$FILE"
    fi
done
