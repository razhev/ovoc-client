#!/usr/bin/env python3
"""Dev-утилита (только для Mac): распаковать ключ Amnezia vpn://… в читаемый JSON.

Использование:
    python3 scripts/decode-vpnkey.py 'vpn://...'
    python3 scripts/decode-vpnkey.py Secrets/my.vpnkey
    cat Secrets/my.vpnkey | python3 scripts/decode-vpnkey.py

Вывод — в stdout. Расшифровка содержит приватные ключи и сертификаты:
сохранять ТОЛЬКО в Secrets/ (каталог в .gitignore):
    python3 scripts/decode-vpnkey.py Secrets/my.vpnkey > Secrets/my-decoded.json

Безопасный режим — только структура, без секретов (можно показывать в чате,
вставлять в issue): имена полей, типы, длины; адреса — лишь вид (ipv4/hostname);
значения печатаются только у заведомо несекретных перечислимых полей:
    python3 scripts/decode-vpnkey.py --schema Secrets/my.vpnkey

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


# ── Режим --schema: структура без секретов ──

# Поля, значение которых — несекретное перечисление или число; печатаем как есть.
SAFE_VALUE_KEYS = {
    "container", "defaultContainer", "transport_proto", "port", "protocol_version",
    "Transport", "ProxyMethod", "EncryptionMethod", "BrowserSig", "NumConn",
    "StreamTimeout", "RemotePort", "isThirdPartyConfig", "crc", "api_version",
}

# Директивы .ovpn, аргументы которых несекретны.
SAFE_DIRECTIVES = {
    "client", "tls-client", "dev", "dev-type", "proto", "cipher", "auth", "data-ciphers",
    "data-ciphers-fallback", "ncp-ciphers", "key-direction", "remote-cert-tls",
    "resolv-retry", "verb", "tls-version-min", "redirect-gateway", "block-outside-dns",
    "nobind", "persist-key", "persist-tun", "compress", "comp-lzo", "mssfix", "tun-mtu",
    "sndbuf", "rcvbuf", "script-security", "pull", "float", "auth-nocache",
    "explicit-exit-notify", "keepalive", "ping", "ping-restart", "connect-retry",
    "connect-timeout", "server-poll-timeout", "reneg-sec", "tls-cipher", "tls-ciphersuites",
}


def kind_of(text: str) -> str:
    """Вид строки без раскрытия содержимого."""
    import re
    if not text:
        return "empty"
    if text.startswith("$"):
        return f"placeholder {text}"          # шаблонный токен Amnezia, не секрет
    if re.fullmatch(r"(\d{1,3}\.){3}\d{1,3}", text):
        if text.startswith("127."):
            return "ipv4 loopback"
        return "ipv4"
    if re.fullmatch(r"\d+", text):
        return "digits"
    if "-----BEGIN" in text:
        return "pem"
    if re.fullmatch(r"[A-Za-z0-9+/=_-]{16,}", text):
        return "base64-like"
    if re.fullmatch(r"[A-Za-z0-9.-]+\.[A-Za-z]{2,}", text):
        return "hostname"
    return "text"


def describe_scalar(key, value) -> str:
    if isinstance(value, bool):
        return f"bool = {value}" if key in SAFE_VALUE_KEYS else "bool"
    if isinstance(value, (int, float)):
        return f"number = {value}" if key in SAFE_VALUE_KEYS else "number"
    if value is None:
        return "null"
    text = str(value)
    if key in SAFE_VALUE_KEYS:
        return f"string = {text!r}"
    return f"string(len={len(text)}, {kind_of(text)})"


def describe_ovpn(text: str, indent: str):
    """Профиль .ovpn: имена директив, число аргументов, инлайн-блоки — без значений."""
    lines = text.replace("\r\n", "\n").split("\n")
    crlf = "\r\n" in text
    print(f"{indent}[.ovpn: {len(lines)} строк, переводы строк: {'CRLF' if crlf else 'LF'}]")
    block, block_lines, comments = None, 0, 0
    for raw in lines:
        line = raw.strip()
        if block:
            if line == f"</{block}>":
                print(f"{indent}  <{block}> … {block_lines} строк … </{block}>")
                block = None
            else:
                block_lines += 1
            continue
        if not line:
            continue
        if line.startswith(("#", ";")):
            comments += 1
            continue
        if line.startswith("<") and line.endswith(">") and not line.startswith("</"):
            block, block_lines = line[1:-1], 0
            continue
        parts = line.split()
        name, args = parts[0], parts[1:]
        if name in SAFE_DIRECTIVES:
            shown = " ".join(args)
        elif name == "remote":
            shown = " ".join([f"<{kind_of(args[0])}>"] + args[1:]) if args else ""
        elif name == "route":
            shown = " ".join([f"<{kind_of(args[0])}>"] + args[1:]) if args else ""
        elif name == "dhcp-option":
            shown = " ".join(args[:1] + [f"<{kind_of(a)}>" for a in args[1:]])
        else:
            shown = f"<{len(args)} арг.>" if args else ""
        flag = "   ← ТРЕБУЕТ ЛОГИН/ПАРОЛЬ" if name == "auth-user-pass" else ""
        print(f"{indent}  {name} {shown}".rstrip() + flag)
    if comments:
        print(f"{indent}  (# комментариев: {comments})")
    if block:
        print(f"{indent}  ВНИМАНИЕ: блок <{block}> не закрыт")


def describe(node, indent=""):
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(value, dict):
                print(f"{indent}{key}: object")
                describe(value, indent + "  ")
            elif isinstance(value, list):
                print(f"{indent}{key}: array[{len(value)}]")
                for index, item in enumerate(value):
                    print(f"{indent}  [{index}]")
                    describe(item, indent + "    ")
            elif key == "last_config" and isinstance(value, str):
                try:
                    inner = json.loads(value)
                except ValueError:
                    print(f"{indent}{key}: string(len={len(value)}) — НЕ JSON")
                    continue
                print(f"{indent}{key}: JSON-строка(len={len(value)}) → object")
                describe(inner, indent + "  ")
            elif key == "config" and isinstance(value, str) and "\n" in value:
                print(f"{indent}{key}: string(len={len(value)})")
                describe_ovpn(value, indent + "  ")
            else:
                print(f"{indent}{key}: {describe_scalar(key, value)}")
    else:
        print(f"{indent}{describe_scalar('', node)}")


def main():
    args = sys.argv[1:]
    schema_mode = "--schema" in args
    args = [a for a in args if a != "--schema"]

    if args:
        arg = args[0]
        if arg in ("-h", "--help"):
            sys.exit(__doc__)
        key = arg if arg.startswith("vpn://") else open(arg, encoding="utf-8").read()
    else:
        key = sys.stdin.read()

    key = key.strip()
    if not key.lower().startswith("vpn://"):
        sys.exit("ошибка: ключ должен начинаться с vpn://")

    raw = b64url_decode(key[len("vpn://"):])
    compressed = True
    try:
        payload = q_uncompress(raw)
    except Exception:
        payload = raw  # запасной путь: несжатый JSON
        compressed = False

    try:
        config = json.loads(payload)
    except ValueError as e:
        sys.exit(f"ошибка: внутри ключа не JSON ({e})")

    if schema_mode:
        print(f"[ключ: {len(key)} симв., упаковка: {'qCompress (zlib)' if compressed else 'plain base64'}, "
              f"JSON: {len(payload)} байт]")
        describe(config)
        return

    json.dump(expand_last_configs(config), sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
