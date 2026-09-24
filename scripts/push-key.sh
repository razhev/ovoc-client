#!/usr/bin/env bash
set -euo pipefail

# DEBUG-мост: доставить ключ vpn:// в установленное на iPhone приложение —
# `make push-key`. Обычный путь — экран «Добавить ключ» в приложении; мост нужен,
# чтобы проверять импорт с Mac, без рук на телефоне.
#
# Ключ копируется в Documents приложения через devicectl; DEBUG-сборка при
# запуске находит файл, прогоняет его через ТОТ ЖЕ код импорта, что и экран
# (TunnelManager.importKey), и СРАЗУ удаляет файл. Ключ не входит ни в один вход
# сборки, поэтому в Release/TestFlight попасть не может — гарантия структурная,
# а не «по флажку» (`make release-check`).
#
#   scripts/push-key.sh [путь-к-ключу]      # по умолчанию Secrets/my.vpnkey
#   FORCE=1 scripts/push-key.sh мусор.txt   # негативные случаи: не проверять префикс vpn://
#
# Сам ключ нигде не печатается.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_ID="com.razhev.personalvpn"
KEY_FILE="${1:-Secrets/my.vpnkey}"

if [[ ! -s "$KEY_FILE" ]]; then
    echo "FAIL: нет файла ключа $KEY_FILE."
    echo "      В Amnezia: Поделиться → формат «For the AmneziaVPN app» → Копировать, затем:"
    echo "      mkdir -p Secrets && pbpaste > Secrets/my.vpnkey"
    exit 2
fi
# Диагностика: готовый .ovpn без Cloak (например, к временному тестовому серверу)
# принимается как есть; всё остальное обязано быть ключом vpn://.
REMOTE_NAME="debug.vpnkey"
if [[ "$KEY_FILE" == *.ovpn ]]; then
    REMOTE_NAME="debug.ovpn"
elif [[ "${FORCE:-}" != "1" && "$(head -c 6 "$KEY_FILE")" != "vpn://" ]]; then
    echo "FAIL: $KEY_FILE не начинается с vpn:// — это не ключ формата «For the AmneziaVPN app»."
    echo "      Проверка негативных случаев (мусор вместо ключа): make push-key KEY=… FORCE=1"
    exit 2
fi

DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
IFS=$'\t' read -r UDID DEVICE_NAME OS_VERSION <<<"$DEVICE_LINE"

# Копируем под фиксированным именем: исходное имя файла приложению не важно.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$KEY_FILE" "$STAGE/$REMOTE_NAME"

echo "Копирую ключ в приложение на «${DEVICE_NAME}»…"
if ! xcrun devicectl device copy to --device "$UDID" \
        --domain-type appDataContainer --domain-identifier "$APP_BUNDLE_ID" \
        --source "$STAGE/$REMOTE_NAME" --destination "Documents/$REMOTE_NAME" >"$STAGE/copy.log" 2>&1; then
    echo "FAIL: не удалось скопировать ключ:"
    grep -v "^[0-9][0-9]:" "$STAGE/copy.log" | tail -6 | sed 's/^/    /'
    echo "      Приложение установлено? (make install). Телефон разблокирован?"
    exit 6
fi

# Перезапуск: DEBUG-сборка импортирует ключ при старте и удаляет файл.
if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing "$APP_BUNDLE_ID" >/dev/null 2>&1; then
    echo "Ключ скопирован, но приложение не перезапустилось — разблокируйте телефон"
    echo "и откройте OVoC Client пальцем: ключ импортируется при запуске."
    exit 7
fi

echo "Готово. В приложении должно появиться «Ключ импортирован: …» (или ошибка импорта под кнопкой)."
echo "Дальше: «Подключить» → подождать рукопожатие Cloak (несколько секунд) → make logs"
