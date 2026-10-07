#!/usr/bin/env bash
set -euo pipefail

# ОСНОВНОЙ способ получить OpenVPNAdapter.framework: сборка из исходников форка
# Amnezia с нашим исправлением — `make framework`.
#
# Почему не готовый бинарь (scripts/fetch-framework.sh, релиз v1.0.42): в нём дефект,
# из-за которого VPN не работает вообще. Клиент шифрует пакеты данных правильно, но
# вместо 16-байтной метки подлинности GCM отправляет мусор из памяти, и любой сервер
# OpenVPN рвёт соединение («AEAD Decrypt error: cipher final failed»; на клиенте —
# «PT_SIZE_ERROR» и переподключение каждые 5 секунд; тот же симптом —
# amnezia-client#2072). Разбор — docs/DEVICE-TESTING.md, «Итог первой попытки M3».
# Исправление — patches/openvpn3-aead-auth-tag.patch (заодно включает проверку метки
# у ВХОДЯЩИХ пакетов, которой в форке не было совсем).
#
# Что фиксируем:
#   - коммит адаптера 8bb3da5 — тот, из которого собран релиз v1.0.42; его подмодуль
#     OpenVPN3 (e901077, «3.8.5») — последняя линия форка, где есть транспорт Cloak.
#     HEAD ветки master-amnezia НЕ годится: там OpenVPN3 без Cloak;
#   - Cloak пересобирается из того же коммита и Go 1.22.2 с патчем lifetime.
# SPM у форка сломан (OpenVPN3 — сабмодуль), podspec указывает на чужой upstream —
# поэтому только клон + их .xcodeproj.

ADAPTER_REPO="https://github.com/amnezia-vpn/OpenVPNAdapter"
ADAPTER_COMMIT="8bb3da50ae2ad07c76a815bc670e9e70e0e3e3ad"
OPENVPN3_COMMIT="e901077a05a5e3d018260d0955acb1a21e05578d"
DEPLOYMENT_TARGET="16.0"   # как у приложения; в проекте форка стоит 10.0 — Xcode 26 его не поддерживает

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/OpenVPNAdapter-src"
DERIVED="$ROOT/build/DerivedData-OpenVPNAdapter"
PATCH="$ROOT/patches/openvpn3-aead-auth-tag.patch"
DEST="$ROOT/Frameworks"
BUILD_LOG="$ROOT/build/framework-build.log"
mkdir -p "$ROOT/build"

# ── 1. Исходники на зафиксированных коммитах ──
if [[ ! -d "$SRC/.git" ]]; then
    git clone --filter=blob:none -b master-amnezia "$ADAPTER_REPO" "$SRC"
fi
cd "$SRC"
git checkout -q "$ADAPTER_COMMIT"
git submodule update --init --depth 1

ACTUAL_OPENVPN3="$(git -C Sources/OpenVPN3 rev-parse HEAD)"
if [[ "$ACTUAL_OPENVPN3" != "$OPENVPN3_COMMIT" ]]; then
    echo "FAIL: подмодуль OpenVPN3 на коммите $ACTUAL_OPENVPN3, ожидали $OPENVPN3_COMMIT"
    exit 1
fi
# Build Cloak from the exact source used by the old prebuilt archive, with
# synchronized ownership and cancellable I/O. Never substitute the old binary.
"$ROOT/scripts/build-cloak-source.sh"

# ── 2. Наше исправление ──
git -C Sources/OpenVPN3 checkout -q -- .                  # чистое дерево перед патчем
git -C Sources/OpenVPN3 apply --check "$PATCH"
git -C Sources/OpenVPN3 apply "$PATCH"
git -C Sources/OpenVPN3 apply "$ROOT/patches/openvpn3-cloak-async-io.patch"
echo "PASS патч применён: ${PATCH#"$ROOT"/}"

cp Lib/ios/arm64/ck-ovpn-plugin.h Sources/OpenVPN3/openvpn/transport/client/pluggable/ck-ovpn-plugin.h

"$ROOT/scripts/test-cloak-native.sh"

# ── 3. Сборка ──
echo "Сборка фреймворка… (полный лог: ${BUILD_LOG#"$ROOT"/})"
if ! xcodebuild -project OpenVPNAdapter.xcodeproj -scheme OpenVPNAdapter \
        -configuration Release -destination 'generic/platform=iOS' \
        -derivedDataPath "$DERIVED" build \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
        IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" >"$BUILD_LOG" 2>&1; then
    echo "FAIL: сборка не прошла. Ошибки дословно:"
    grep -E "error:" "$BUILD_LOG" | sort -u | head -20 | sed 's/^/    /'
    exit 1
fi

FW_PATH="$DERIVED/Build/Products/Release-iphoneos/OpenVPNAdapter.framework"
if [[ ! -d "$FW_PATH" ]]; then
    echo "FAIL: собранный OpenVPNAdapter.framework не найден: $FW_PATH"
    exit 1
fi

rm -rf "$DEST/OpenVPNAdapter.framework"
mkdir -p "$DEST"
cp -R "$FW_PATH" "$DEST/"
"$ROOT/scripts/framework-privacy-manifest.sh"   # своего манифеста у фреймворка нет
python3 "$ROOT/scripts/framework-provenance.py" record --framework "$DEST/OpenVPNAdapter.framework" --source "$SRC"
echo "OK: ${DEST#"$ROOT"/}/OpenVPNAdapter.framework (из исходников, с исправлениями GCM и Cloak)"
echo "Дальше обязательно: make verify"
