#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/Cloak-src"
COMMIT="884ac4fa0d4a8e014e18ca1dc4a40b18bc9e4291"
PATCH="$ROOT/patches/cloak-connection-registry.patch"
DEST="$SRC/build/ios"
export GOTOOLCHAIN=go1.22.2
export GOMODCACHE="$SRC/build/go-mod"
export GOCACHE="$SRC/build/go-cache"

if [[ ! -d "$SRC/.git" ]]; then
    git clone --no-checkout https://github.com/amnezia-vpn/Cloak.git "$SRC"
fi
# This directory is a generated source cache; always rebuild the pinned source.
git -C "$SRC" checkout -q "$COMMIT" -- .
git -C "$SRC" checkout --detach -q "$COMMIT"
git -C "$SRC" apply --check "$PATCH"
git -C "$SRC" apply "$PATCH"
git -C "$SRC" apply --reverse --check "$PATCH"
# Remove the generated test left by the retired build 8 cache, if present.
rm -f "$SRC/cmd/ck-ovpn-plugin/cloak_lifetime_test.go"
cp "$ROOT/Tests/Native/cloak_registry_test.go" "$SRC/cmd/ck-ovpn-plugin/"
cd "$SRC"

if [[ "$(go env GOVERSION)" != go1.22.2 ]]; then
    echo 'FAIL: Cloak requires the pinned Go 1.22.2 toolchain'
    exit 1
fi
go test -race -count=1 -timeout=60s -mod=readonly ./cmd/ck-ovpn-plugin

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$DEST"
CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$(xcrun --sdk iphoneos --find clang)" \
    CGO_CFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=16.0" \
    CGO_LDFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=16.0" \
    go build -trimpath -mod=readonly -buildmode=c-archive \
    -o "$DEST/ck-ovpn-plugin.a" ./cmd/ck-ovpn-plugin
echo 'PASS Cloak: pinned source + registry patch, race tests and iOS arm64 archive'
echo "Archive: $DEST/ck-ovpn-plugin.a"
echo "Header: $DEST/ck-ovpn-plugin.h"
