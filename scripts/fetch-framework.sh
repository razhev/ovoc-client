#!/usr/bin/env bash
set -euo pipefail

# Скачивает готовый OpenVPNAdapter.framework от Amnezia
# (внутри: OpenVPN3 + mbedTLS + Cloak, iOS arm64 only) и фиксирует SHA-256.
#
# Запасной источник, если релиз пропадёт (см. docs/IMPLEMENTATION.md, шаг 0.2):
#   репозиторий amnezia-vpn/3rd-prebuilt, ветка feature/special-handshake,
#   путь openvpn/apple/OpenVPNAdapter-ios/OpenVPNAdapter.framework
# Крайний случай — сборка из исходников: scripts/build-framework-source.sh

URL="https://github.com/amnezia-vpn/3rd-build-ga/releases/download/v1.0.42/openvpnadapter.zip"

# Зафиксированный хэш архива. Пустое значение = первый запуск:
# скрипт напечатает вычисленный хэш — вписать его сюда и перезапустить.
EXPECTED_SHA256="c6d6b3f745265771bdcb4bcdebb3ff5e39fe4bfee54958a86b5d3229f1151c10"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/build/cache"
ZIP="$CACHE/openvpnadapter.zip"
DEST="$ROOT/Frameworks"

mkdir -p "$CACHE"

if [[ ! -f "$ZIP" ]]; then
    echo "Downloading $URL"
    curl -fL --retry 3 -o "$ZIP.part" "$URL"
    mv "$ZIP.part" "$ZIP"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "SHA-256: $ACTUAL_SHA256"

if [[ -z "$EXPECTED_SHA256" ]]; then
    echo ""
    echo "ПЕРВЫЙ ЗАПУСК: впишите хэш выше в EXPECTED_SHA256 внутри $0 и перезапустите."
    exit 2
fi

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "FAIL: SHA-256 не совпадает с зафиксированным ($EXPECTED_SHA256)."
    echo "Либо релиз подменили, либо докачка побилась. Удалите $ZIP и повторите."
    exit 1
fi

TMP="$DEST/.unzip_tmp"
rm -rf "$DEST/OpenVPNAdapter.framework" "$TMP"
mkdir -p "$TMP"
unzip -q "$ZIP" -d "$TMP"

# В архиве лежат варианты для нескольких платформ (ios/, macos/) — берём строго iOS.
FW_PATH="$(find "$TMP" -type d -name 'OpenVPNAdapter.framework' -path '*/ios/*' | head -1)"
if [[ -z "$FW_PATH" ]]; then
    echo "FAIL: в архиве нет iOS-варианта OpenVPNAdapter.framework. Содержимое:"
    find "$TMP" -maxdepth 3
    exit 1
fi

mv "$FW_PATH" "$DEST/"
rm -rf "$TMP"
echo "OK: $DEST/OpenVPNAdapter.framework"
