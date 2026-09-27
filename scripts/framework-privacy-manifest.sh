#!/usr/bin/env bash
set -euo pipefail

# Кладёт privacy manifest в собранный OpenVPNAdapter.framework — `make framework-manifest`.
# У фреймворка Amnezia своего манифеста нет, а без объявления required reason API
# (stat/fstat, mach_absolute_time) App Store Connect отвергает загрузку (ITMS-91053).
# Источник — Config/OpenVPNAdapter-PrivacyInfo.xcprivacy; make framework вызывает
# этот скрипт сам, отдельно он нужен для уже собранного фреймворка.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Config/OpenVPNAdapter-PrivacyInfo.xcprivacy"
FW="$ROOT/Frameworks/OpenVPNAdapter.framework"

[[ -d "$FW" ]] || { echo "FAIL: нет ${FW#"$ROOT"/} — сначала make framework"; exit 1; }
plutil -lint -s "$SRC" || { echo "FAIL: ${SRC#"$ROOT"/} — не plist"; exit 1; }
cp "$SRC" "$FW/PrivacyInfo.xcprivacy"
echo "OK: privacy manifest → ${FW#"$ROOT"/}/PrivacyInfo.xcprivacy"
