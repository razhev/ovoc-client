#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/Cloak-src"
COMMIT=884ac4fa0d4a8e014e18ca1dc4a40b18bc9e4291
DEST="$ROOT/build/OpenVPNAdapter-src/Lib/ios/arm64"
export GOTOOLCHAIN=go1.22.2
export GOMODCACHE="$ROOT/build/go-mod"
export GOCACHE="$ROOT/build/go-cache"
if [[ ! -d "$SRC/.git" ]]; then
    git clone --no-checkout https://github.com/amnezia-vpn/Cloak.git "$SRC"
fi
git -C "$SRC" checkout -q "$COMMIT" -- .
git -C "$SRC" checkout -q "$COMMIT"
git -C "$SRC" apply "$ROOT/patches/cloak-connection-lifetime.patch"
cp "$ROOT/Tests/Native/cloak_lifetime_test.go" "$SRC/cmd/ck-ovpn-plugin/"
cd "$SRC"
go test -race ./cmd/ck-ovpn-plugin
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$(xcrun --sdk iphoneos --find clang)" \
    CGO_CFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=16.0" \
    CGO_LDFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=16.0" \
    go build -trimpath -mod=readonly -buildmode=c-archive -o "$DEST/ck-ovpn-plugin.a" ./cmd/ck-ovpn-plugin
# This header must match the newly built C archive.
cp "$DEST/ck-ovpn-plugin.h" "$ROOT/build/OpenVPNAdapter-src/Sources/OpenVPN3/openvpn/transport/client/pluggable/ck-ovpn-plugin.h"
echo 'PASS Cloak: pinned source + lifetime patch, race tests and iOS arm64 archive'
