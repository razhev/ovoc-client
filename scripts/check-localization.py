#!/usr/bin/env python3
"""Проверка каталога строк — `make strings-check`.

Правило проекта: русский — базовый язык, ключ каталога App/Localizable.xcstrings —
это сама русская строка из кода. Значит, каждый строковый литерал с кириллицей
в App/*.swift обязан быть ключом каталога (иначе на английском телефоне он
покажется по-русски), а каждый ключ каталога — встречаться в коде (иначе он
мёртвый). Строки для логов пишутся по-английски и под проверку не попадают.

Интерполяция `\\(x)` в коде соответствует `%@` (строка) или `%lld` (целое) в ключе.

Выход: 0 — всё сходится, 1 — есть расхождения (печатаются построчно).
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "Localizable.xcstrings"
SOURCES = sorted((ROOT / "App").glob("*.swift"))

CYRILLIC = re.compile(r"[Ѐ-ӿ]")
INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")


def string_literals(line: str):
    """Все "…" литералы строки кода; текст после // вне литерала — комментарий."""
    literals, i, n = [], 0, len(line)
    while i < n:
        ch = line[i]
        if ch == "/" and i + 1 < n and line[i + 1] == "/":
            break
        if ch == '"':
            j, buf = i + 1, []
            while j < n:
                c = line[j]
                if c == "\\" and j + 1 < n:
                    if line[j + 1] == "(":          # интерполяция — до парной скобки
                        depth, k = 0, j + 1
                        while k < n:
                            depth += line[k] == "("
                            depth -= line[k] == ")"
                            if depth == 0:
                                break
                            k += 1
                        buf.append(line[j:k + 1])
                        j = k + 1
                        continue
                    buf.append(line[j:j + 2])
                    j += 2
                    continue
                if c == '"':
                    break
                buf.append(c)
                j += 1
            literals.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return literals


def key_pattern(literal: str) -> re.Pattern:
    parts = [re.escape(p) for p in INTERPOLATION.split(literal)]
    return re.compile("^" + "(?:%@|%lld)".join(parts) + "$")


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    keys = set(catalog["strings"])
    if catalog.get("sourceLanguage") != "ru":
        print(f"FAIL {CATALOG.name}: sourceLanguage должен быть ru")
        return 1

    problems, used = [], set()
    for path in SOURCES:
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for literal in string_literals(line):
                if not CYRILLIC.search(literal):
                    continue
                pattern = key_pattern(literal)
                matches = [k for k in keys if pattern.match(k)]
                if matches:
                    used.update(matches)
                else:
                    problems.append(f"{path.relative_to(ROOT)}:{lineno}: нет в каталоге: \"{literal}\"")

    for key in sorted(keys - used):
        problems.append(f"{CATALOG.relative_to(ROOT)}: ключ не используется в коде: \"{key}\"")

    for key, entry in catalog["strings"].items():
        en = entry.get("localizations", {}).get("en", {}).get("stringUnit", {})
        if not en.get("value"):
            problems.append(f"{CATALOG.relative_to(ROOT)}: нет английского перевода: \"{key}\"")
        elif en.get("state") != "translated":
            problems.append(f"{CATALOG.relative_to(ROOT)}: перевод не в состоянии translated: \"{key}\"")

    if problems:
        print("\n".join(problems))
        print(f"FAIL локализация: {len(problems)} расхождений")
        return 1
    print(f"PASS локализация: {len(keys)} строк, все русские литералы App/*.swift есть в каталоге, у всех есть английский перевод")
    return 0


if __name__ == "__main__":
    sys.exit(main())
