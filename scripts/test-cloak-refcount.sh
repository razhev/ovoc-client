#!/usr/bin/env bash
set -euo pipefail

# Test the actual OpenVPN Connection header on macOS with ThreadSanitizer.
# Optional argument: an alternate OpenVPNAdapter source checkout (negative control).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ROOT="${1:-$ROOT/build/OpenVPNAdapter-src}"
OUT="$ROOT/build/native-tests"
if [[ ! -f "$SOURCE_ROOT/Sources/OpenVPN3/openvpn/transport/client/pluggable/pt.hpp" ]]; then
    echo "FAIL: исходники OpenVPNAdapter не найдены. Сначала выполните make framework."
    exit 1
fi
mkdir -p "$OUT"
xcrun clang++ -std=c++17 -g -O0 -fsanitize=thread -fno-omit-frame-pointer \
    -DUSE_ASIO -DASIO_STANDALONE \
    -I "$SOURCE_ROOT/Sources/OpenVPN3" -I "$SOURCE_ROOT/Sources/ASIO/asio/include" \
    "$ROOT/Tests/Native/cloak_connection_refcount.cpp" -o "$OUT/cloak-connection-refcount"
TSAN_OPTIONS=halt_on_error=1:exitcode=66 "$OUT/cloak-connection-refcount"
