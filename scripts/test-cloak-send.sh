#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/build/OpenVPNAdapter-src}"
OUT="$ROOT/build/native-tests"
mkdir -p "$OUT"
xcrun clang++ -std=c++17 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
    -Wno-deprecated-declarations \
    -I "$SRC/Sources/OpenVPN3" -I "$SRC/Sources/ASIO/asio/include" \
    "$ROOT/Tests/Native/cloak_send_queue.cpp" -o "$OUT/cloak-send-queue"
# A deadlocked event loop must fail the test instead of hanging the test runner.
python3 - "$OUT/cloak-send-queue" <<'PY'
import subprocess, sys
subprocess.run([sys.argv[1]], timeout=60, check=True)
PY
