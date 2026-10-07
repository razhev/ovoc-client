#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/OpenVPNAdapter-src"
mkdir -p "$ROOT/build/native-tests"
xcrun clang++ -std=c++14 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
    -I "$SRC/Sources/OpenVPN3" -I "$SRC/Sources/ASIO/asio/include" \
    "$ROOT/Tests/Native/cloak_async_io.cpp" -o "$ROOT/build/native-tests/cloak-async-io"
"$ROOT/build/native-tests/cloak-async-io"
