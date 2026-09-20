#!/usr/bin/env python3
"""Находит подключённый iPhone для установки сборки.

  python3 scripts/find-device.py            # stdout: UDID<TAB>имя<TAB>версия iOS
  python3 scripts/find-device.py --list     # таблица всех физических iOS-устройств
  DEVICE=<udid|имя> python3 scripts/find-device.py   # выбрать конкретное

Источник — `xcrun devicectl list devices --json-output` (единственный интерфейс
devicectl, официально пригодный для скриптов). Схема JSON у Apple не стабильна
между версиями Xcode, поэтому поля ищутся обходом в глубину, а не по жёстким
путям. Проверено на jsonVersion 3 (Xcode 26.2).

Коды выхода: 0 — найден; 3 — устройств нет / их несколько; 4 — есть, но не готов
(не спарен, выключен Developer Mode, iOS < 17); 2 — не сработал сам devicectl.
"""

import json
import os
import subprocess
import sys
import tempfile


# Ветки, в которых встречаются одноимённые ключи (name у capability и у типа CPU) —
# в них не заходим, иначе вместо имени телефона найдётся "arm64e".
SKIP_BRANCHES = {"capabilities", "cpuType", "supportedCPUTypes"}


def find(node, key):
    """Первое значение ключа key при обходе в глубину (None, если нет)."""
    if isinstance(node, dict):
        if key in node:
            value = node[key]
            # В новых схемах скаляры бывают завёрнуты: {"stringValue": "26.6.2"}.
            if isinstance(value, dict) and "stringValue" in value:
                return value["stringValue"]
            return value
        for name, child in node.items():
            if name in SKIP_BRANCHES:
                continue
            found = find(child, key)
            if found is not None:
                return found
    elif isinstance(node, list):
        for child in node:
            found = find(child, key)
            if found is not None:
                return found
    return None


def load_devices(from_json):
    if from_json:
        with open(from_json, encoding="utf-8") as handle:
            data = json.load(handle)
    else:
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "devices.json")
            result = subprocess.run(
                ["xcrun", "devicectl", "list", "devices", "--json-output", path],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
            )
            if result.returncode != 0 or not os.path.exists(path):
                sys.stderr.write("FAIL: devicectl не отработал:\n" + result.stderr)
                sys.exit(2)
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
    devices = find(data, "devices")
    return devices if isinstance(devices, list) else []


def describe(device):
    return {
        "udid": str(find(device, "udid") or ""),
        "identifier": str(find(device, "identifier") or ""),
        "serial": str(find(device, "serialNumber") or ""),
        "name": str(find(device, "name") or "?"),
        "model": str(find(device, "marketingName") or find(device, "productType") or "?"),
        "os": str(find(device, "osVersionNumber") or "?"),
        "platform": str(find(device, "platform") or ""),
        "reality": str(find(device, "reality") or "physical"),
        "pairing": str(find(device, "pairingState") or "?"),
        "tunnel": str(find(device, "tunnelState") or "?"),
        "devmode": str(find(device, "developerModeStatus") or "?"),
        "transport": str(find(device, "transportType") or "?"),
    }


def problems(info):
    """Почему на устройство нельзя ставить сборку (пустой список — готово)."""
    issues = []
    if info["pairing"] != "paired":
        issues.append("не спарен с этим Mac: подключите кабелем, разблокируйте "
                      "и нажмите «Доверять этому компьютеру»")
    if info["devmode"] != "enabled":
        issues.append("выключен Режим разработчика: Настройки → Конфиденциальность "
                      "и безопасность → Режим разработчика → Вкл (перезагрузка)")
    try:
        major = int(info["os"].split(".")[0])
        if major < 17:
            issues.append(f"iOS {info['os']}: devicectl требует iOS 17+. Для iOS 16 — "
                          "ios-deploy, см. docs/DEVICE-TESTING.md")
    except ValueError:
        pass
    return issues


def main():
    args = sys.argv[1:]
    list_mode = "--list" in args
    from_json = args[args.index("--from-json") + 1] if "--from-json" in args else None

    candidates = [
        info for info in map(describe, load_devices(from_json))
        # Только физические iPhone/iPad: к Mac бывают привязаны ещё часы и симуляторы.
        if info["platform"].lower() == "ios" and info["reality"] != "simulated"
    ]

    if list_mode:
        if not candidates:
            print("iOS-устройств не найдено. Подключите iPhone кабелем и разблокируйте его.")
            return 3
        for info in candidates:
            reachable = info["tunnel"] != "unavailable"
            issues = problems(info) if reachable else ["сейчас недоступен (не подключён)"]
            status = "ГОТОВ" if not issues else "НЕ ГОТОВ"
            print(f"{status}: {info['name']} — {info['model']}, iOS {info['os']}, "
                  f"{info['transport']}, UDID {info['udid']}")
            for issue in issues:
                print(f"    • {issue}")
        return 0

    wanted = os.environ.get("DEVICE", "").strip()
    if wanted:
        candidates = [
            info for info in candidates
            if wanted in (info["udid"], info["identifier"], info["serial"])
            or wanted.lower() == info["name"].lower()
        ]
        if not candidates:
            sys.stderr.write(f"FAIL: устройство DEVICE='{wanted}' не найдено. См. make devices\n")
            return 3
    else:
        candidates = [info for info in candidates if info["tunnel"] != "unavailable"]

    if not candidates:
        sys.stderr.write("FAIL: подключённый iPhone не найден. Подключите кабелем, "
                         "разблокируйте, проверьте: make devices\n")
        return 3
    if len(candidates) > 1:
        sys.stderr.write("FAIL: найдено несколько устройств — укажите одно: "
                         "make install DEVICE=<udid|имя>\n")
        for info in candidates:
            sys.stderr.write(f"    {info['name']} — iOS {info['os']}, UDID {info['udid']}\n")
        return 3

    info = candidates[0]
    issues = problems(info)
    if issues:
        sys.stderr.write(f"FAIL: «{info['name']}» не готов к установке:\n")
        for issue in issues:
            sys.stderr.write(f"    • {issue}\n")
        return 4
    if not info["udid"]:
        sys.stderr.write("FAIL: в выводе devicectl нет UDID — схема JSON изменилась, "
                         "поправьте scripts/find-device.py\n")
        return 2

    print(f"{info['udid']}\t{info['name']}\t{info['os']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
