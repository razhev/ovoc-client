#!/usr/bin/env bash
set -euo pipefail

# Ворота Release — `make release-check`. Собирает Release-конфигурацию БЕЗ подписи
# и проверяет содержимое OVoCClient.app:
#   1. в коде нет DEBUG-моста (`make push-key`, `make connect/disconnect/dummy`);
#   2. в бандле нет ни одного файла ключа и ни одной строки vpn://… — клиент
#      раздаётся пустым, ключ каждый добавляет сам на экране импорта.
#   3. privacy manifest (PrivacyInfo.xcprivacy) есть у приложения, расширения и
#      фреймворка и читается как plist — без них App Store Connect отвергает загрузку
#      (ITMS-91053);
#   4. в бандле лежат тексты лицензий для экрана «О приложении» (GPL/AGPL-компоненты).
# Контроль самой проверки: те же метки ОБЯЗАНЫ находиться в Debug-сборке, иначе
# «в Release не найдено» ничего бы не доказывало. Поэтому собираются обе
# конфигурации — из одних и тех же исходников, в отдельный каталог.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="build/DerivedData-check"
mkdir -p build

build_config() {
    local config="$1" log="build/release-check-$1.log"
    echo "Собираю ${config} без подписи (лог: ${log})…"
    if ! xcodebuild -project OVoCClient.xcodeproj -scheme OVoCClient -configuration "$config" \
            -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" build \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO >"$log" 2>&1; then
        echo "FAIL сборка ${config}:"
        grep -E "error:|BUILD FAILED" "$log" | head -10 | sed 's/^/    /'
        exit 1
    fi
}
build_config Release
build_config Debug
APP="${DERIVED}/Build/Products/Release-iphoneos/OVoCClient.app"
DEBUG_APP="${DERIVED}/Build/Products/Debug-iphoneos/OVoCClient.app"
echo "PASS сборка: ${APP}"

# Имена функций и длинные строковые литералы, существующие только под #if DEBUG.
# Короткие литералы («-autoconnect») не годятся: Swift хранит строки до 15 байт
# прямо в коде команд, в секции строк их нет даже в Debug.
MARKERS="importDebugKeyIfPresent findDebugKey rawProfileConfig applyDummyProfile connectDummy debugBridge"

# Наш код: всё, кроме встроенного фреймворка Amnezia.
our_binaries() {
    find "$1" -type f -not -path "*/OpenVPNAdapter.framework/*" -print0 \
        | xargs -0 file | grep "Mach-O" | cut -d: -f1
}

# Печатает метки, найденные в бинарях бандла (таблица символов + строки).
found_markers() {
    local app="$1" marker binary
    for marker in $MARKERS; do
        while IFS= read -r binary; do
            # Без grep -q: он закрывает конвейер на первом совпадении, nm получает
            # SIGPIPE, и под pipefail условие становится ложным при НАЙДЕННОЙ метке.
            if { nm -a "$binary" 2>/dev/null; strings -a "$binary"; } | grep "$marker" >/dev/null; then
                echo "$marker"
                break
            fi
        done < <(our_binaries "$app")
    done
}

FAILED=0

FOUND="$(found_markers "$APP" | tr '\n' ' ')"
if [[ -z "$FOUND" ]]; then
    echo "PASS DEBUG-мост: в Release нет ни одной из меток: ${MARKERS}"
else
    echo "FAIL DEBUG-мост попал в Release: ${FOUND}"
    FAILED=1
fi

FOUND_DEBUG="$(found_markers "$DEBUG_APP" | wc -l | tr -d ' ')"
TOTAL="$(echo $MARKERS | wc -w | tr -d ' ')"
if [[ "$FOUND_DEBUG" == "$TOTAL" ]]; then
    echo "PASS контроль: в Debug-сборке найдены все ${TOTAL} меток — проверка их видит"
else
    echo "FAIL контроль: в Debug-сборке найдено ${FOUND_DEBUG} из ${TOTAL} меток — проверка слепа"
    FAILED=1
fi

KEY_FILES="$(find "$APP" \( -name "*.vpnkey" -o -name "*.ovpn" \) -print)"
if [[ -z "$KEY_FILES" ]]; then
    echo "PASS файлы ключей: в бандле нет *.vpnkey и *.ovpn"
else
    echo "FAIL в бандле лежит файл ключа (что-то положили в App/?):"
    echo "$KEY_FILES" | sed 's/^/    /'
    FAILED=1
fi

# Ключ под любым именем: vpn:// + длинный хвост base64. Печатаем только имена файлов.
KEY_STRINGS="$(grep -rlaE "vpn://[A-Za-z0-9_+/=-]{64,}" "$APP" || true)"
if [[ -z "$KEY_STRINGS" ]]; then
    echo "PASS содержимое: ни в одном файле бандла нет строки vpn://<ключ>"
else
    echo "FAIL строка vpn://<ключ> найдена в файлах:"
    echo "$KEY_STRINGS" | sed 's/^/    /'
    FAILED=1
fi

# Privacy manifest у каждого исполняемого бандла.
MANIFEST_PROBLEMS=""
for bundle in "" "PlugIns/PacketTunnel.appex/" "Frameworks/OpenVPNAdapter.framework/"; do
    manifest="${APP}/${bundle}PrivacyInfo.xcprivacy"
    if [[ ! -f "$manifest" ]]; then
        MANIFEST_PROBLEMS="${MANIFEST_PROBLEMS}    нет ${bundle}PrivacyInfo.xcprivacy"$'\n'
    elif ! plutil -lint -s "$manifest"; then
        MANIFEST_PROBLEMS="${MANIFEST_PROBLEMS}    не plist: ${bundle}PrivacyInfo.xcprivacy"$'\n'
    fi
done
if [[ -z "$MANIFEST_PROBLEMS" ]]; then
    echo "PASS privacy manifest: приложение, расширение и фреймворк"
else
    echo "FAIL privacy manifest:"
    printf '%s' "$MANIFEST_PROBLEMS"
    echo "    фреймворк — make framework-manifest; расширение сразу после добавления файла —"
    echo "    пересобрать начисто: rm -rf ${DERIVED} && make release-check"
    FAILED=1
fi

# Тексты лицензий для экрана «О приложении» (App/Licenses + OFL шрифтов).
LICENSES="OVoCClient-GPL-3.0 OpenVPNAdapter-AGPL-3.0 OpenVPNAdapter-NOTICE OpenVPN3-LICENSE Go-LICENSE Cloak-Go-modules OFL-marmelad OFL-rubik OFL-ptmono"
MISSING_LICENSES=""
for name in $LICENSES; do
    [[ -s "${APP}/${name}.txt" ]] || MISSING_LICENSES="${MISSING_LICENSES} ${name}.txt"
done
if [[ -z "$MISSING_LICENSES" ]]; then
    echo "PASS лицензии: $(echo $LICENSES | wc -w | tr -d ' ') текстов в бандле"
else
    echo "FAIL в бандле нет текстов лицензий:${MISSING_LICENSES}"
    FAILED=1
fi

echo
echo "Состав OVoCClient.app (без фреймворка):"
( cd "$APP" && find . -type f -not -path "./Frameworks/*" | sort | sed 's/^/    /' )

exit $FAILED
