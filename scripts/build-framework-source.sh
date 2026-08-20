#!/usr/bin/env bash
set -euo pipefail

# ЗАПАСНОЙ ПУТЬ: сборка OpenVPNAdapter.framework из исходников форка Amnezia.
# Нужен только если:
#   - готовый бинарь не прошёл ворота verify-framework.sh, ИЛИ
#   - на iOS 26 воспроизвёлся баг «подключено, но трафика нет»
#     (amnezia-client#2072 — чинится фиксами марта 2026 в HEAD master-amnezia).
#
# ВАЖНО: SPM у форка сломан (OpenVPN3 — сабмодуль, не резолвится),
# podspec указывает на чужой upstream — поэтому ТОЛЬКО клон + их .xcodeproj.
# Требуется Go (Cloak-плагин собирается на этапе их сборки).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/OpenVPNAdapter-src"
DEST="$ROOT/Frameworks"
DERIVED="$ROOT/build/DerivedData-OpenVPNAdapter"

if [[ ! -d "$SRC" ]]; then
    git clone --recursive -b master-amnezia \
        https://github.com/amnezia-vpn/OpenVPNAdapter "$SRC"
else
    echo "Источники уже склонированы: $SRC (git pull — вручную, чтобы не съехать с проверенного коммита)"
fi

cd "$SRC"
echo "Доступные схемы:"
xcodebuild -list -project OpenVPNAdapter.xcodeproj

# Имя схемы сверяем с выводом -list; ожидаемое — фреймворк-таргет для iOS.
SCHEME="${SCHEME:-OpenVPNAdapter (iOS)}"

xcodebuild -project OpenVPNAdapter.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    build \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

FW_PATH="$(find "$DERIVED/Build/Products" -name 'OpenVPNAdapter.framework' -type d | head -1)"
if [[ -z "$FW_PATH" ]]; then
    echo "FAIL: собранный OpenVPNAdapter.framework не найден в $DERIVED"
    exit 1
fi

rm -rf "$DEST/OpenVPNAdapter.framework"
mkdir -p "$DEST"
cp -R "$FW_PATH" "$DEST/"
echo "OK: $DEST/OpenVPNAdapter.framework (из исходников)"
echo "Дальше обязательно: ./scripts/verify-framework.sh"
