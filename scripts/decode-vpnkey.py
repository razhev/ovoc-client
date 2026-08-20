#!/usr/bin/env python3
"""Dev-утилита (только для Mac): распаковать ключ Amnezia vpn://… в читаемый JSON.

Использование:
    python3 scripts/decode-vpnkey.py 'vpn://...'
    python3 scripts/decode-vpnkey.py Secrets/my.vpnkey
    cat Secrets/my.vpnkey | python3 scripts/decode-vpnkey.py

Вывод — в stdout. Расшифровка содержит приватные ключи и сертификаты:
сохранять ТОЛЬКО в Secrets/ (каталог в .gitignore):
    python3 scripts/decode-vpnkey.py Secrets/my.vpnkey > Secrets/my-decoded.json

Формат ключа: "vpn://" + base64url-без-паддинга от qCompress(JSON, 8),
где qCompress = 4 байта big-endian (длина несжатого) + zlib-поток RFC1950.
Запасной вариант — обычный base64 несжатого JSON.
"""

import base64
import json
import sys
import zlib


def b64url_decode(s: str) -> bytes:
    s = s.strip().replace("-", "+").replace("_", "/").replace("=", "")
    pad = -len(s) % 4
    if pad == 3:
        raise ValueError("длина base64 ≡ 1 (mod 4) — ключ скопирован не целиком?")
    return base64.b64decode(s + "=" * pad)


def q_uncompress(data: bytes) -> bytes:
    if len(data) <= 4:
        raise ValueError("слишком короткий вход")
    expected = int.from_bytes(data[:4], "big")
    out = zlib.decompress(data[4:])
    if len(out) != expected:
        raise ValueError(f"длина не сошлась: {len(out)} != {expected}")
    return out


def expand_last_configs(node):
    """last_config — JSON-СТРОКИ (двойная упаковка); разворачиваем для читаемости."""
    if isinstance(node, dict):
        result = {}
        for key, value in node.items():
            if key == "last_config" and isinstance(value, str):
                try:
                    result[key] = expand_last_configs(json.loads(value))
                except ValueError:
                    result[key] = value
            else:
                result[key] = expand_last_configs(value)
        return result
    if isinstance(node, list):
        return [expand_last_configs(item) for item in node]
    return node


def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg in ("-h", "--help"):
            sys.exit(__doc__)
        key = arg if arg.startswith("vpn://") else open(arg, encoding="utf-8").read()
    else:
        key = sys.stdin.read()

    key = key.strip()
    if not key.lower().startswith("vpn://"):
        sys.exit("ошибка: ключ должен начинаться с vpn://")

    raw = b64url_decode(key[len("vpn://"):])
    try:
        payload = q_uncompress(raw)
    except Exception:
        payload = raw  # запасной путь: несжатый JSON

    try:
        config = json.loads(payload)
    except ValueError as e:
        sys.exit(f"ошибка: внутри ключа не JSON ({e})")

    json.dump(expand_last_configs(config), sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
