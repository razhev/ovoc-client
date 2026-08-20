#!/usr/bin/env bash
set -euo pipefail

# ГЛАВНЫЕ ворота качества фреймворка — гоняем ДО любой интеграции.
# Три проверки:
#   1. lipo: бинарь содержит только arm64 (device-only, симулятора нет);
#   2. nm:   внутри есть символы Go-части Cloak (значит Cloak реально вшит);
#   3. в Headers/ есть setPTCloak — печатаем точную строку объявления,
#      по ней пишется код провайдера (форк менял API в марте 2026).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FW="$ROOT/Frameworks/OpenVPNAdapter.framework"

if [[ ! -d "$FW" ]]; then
    echo "FAIL: $FW не найден. Сначала: make fetch"
    exit 1
fi

BIN="$FW/OpenVPNAdapter"
if [[ ! -f "$BIN" ]]; then
    # имя бинаря может отличаться — берём из Info.plist или ищем Mach-O
    BIN="$(find "$FW" -maxdepth 1 -type f ! -name '*.plist' | head -1)"
fi
echo "Binary: $BIN"

FAILED=0

# ── 1. Архитектуры ──
ARCHS="$(lipo -archs "$BIN" 2>/dev/null || true)"
if [[ "$ARCHS" == "arm64" ]]; then
    echo "PASS [1/3] lipo: only arm64"
else
    echo "FAIL [1/3] lipo: '$ARCHS' (ожидали ровно 'arm64')"
    FAILED=1
fi

# ── 2. Символы Cloak ──
SYMS="$(nm -gU "$BIN" 2>/dev/null || true)"
if grep -q "Cloak_dial" <<<"$SYMS" && grep -q "Initialize_cloak_c_client" <<<"$SYMS"; then
    echo "PASS [2/3] nm: Cloak_dial + Initialize_cloak_c_client найдены"
else
    echo "FAIL [2/3] nm: символы Cloak не найдены — Cloak НЕ вшит в этот бинарь."
    echo "        Взять фреймворк из 3rd-prebuilt (см. fetch-framework.sh) или собрать из исходников."
    FAILED=1
fi

# ── 3. setPTCloak в заголовках ──
if grep -rq "setPTCloak" "$FW/Headers/"; then
    echo "PASS [3/3] Headers: setPTCloak найден. Объявление:"
    grep -rn "setPTCloak" "$FW/Headers/" | sed 's/^/        /'
else
    echo "FAIL [3/3] Headers: setPTCloak отсутствует — этот API обязателен для включения Cloak."
    FAILED=1
fi

if [[ "$FAILED" -ne 0 ]]; then
    echo ""
    echo "ВОРОТА НЕ ПРОЙДЕНЫ — интегрировать этот фреймворк нельзя."
    exit 1
fi
echo ""
echo "Все проверки пройдены. Точные сигнатуры API — фиксируются в docs/FRAMEWORK-API.md."
