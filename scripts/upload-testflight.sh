#!/usr/bin/env bash
set -euo pipefail

# Сборка Release и загрузка в TestFlight — `make testflight` (M6, шаг 6.2).
#
# Два вызова xcodebuild, без fastlane и altool:
#   1. `xcodebuild archive` — Release, generic/platform=iOS, автоподпись
#      (-allowProvisioningUpdates: Xcode сам заводит distribution-профили для
#      приложения и расширения через API-ключ App Store Connect);
#   2. `xcodebuild -exportArchive` с Config/ExportOptions.plist (method
#      app-store-connect, destination upload) — переподписывает архив и
#      загружает его в App Store Connect. Дальше сборка появляется в TestFlight.
#
# Реквизиты API-ключа: переменные окружения ASC_KEY_ID / ASC_ISSUER_ID
# (необязательно ASC_KEY_PATH) либо файл Secrets/asc.env (шаблон —
# Secrets/asc.env.example). Сам ключ — ~/.private_keys/AuthKey_<Key ID>.p8.
#
# Чем подписывать и загружать — ASC_AUTH:
#   key     (по умолчанию) — API-ключом. Distribution-подпись Apple разрешает только
#           ключу с ролью Admin; у ключа с ролью App Manager экспорт падает с
#           «Cloud signing permission error» — тогда скрипт сам повторяет экспорт
#           через Apple ID из Xcode;
#   account — Apple ID, добавленным в Xcode → Settings → Accounts. API-ключ не нужен.
#
# Перед загрузкой скрипт проверяет окружение и прогоняет ворота:
# make release-check (нет DEBUG-моста и файлов ключа в бандле) и проверку
# каталога строк. Пропустить ворота (уже прошли только что): RELEASE_CHECK=0.
#
# Коды выхода: 2 окружение/реквизиты · 3 ворота · 5 archive · 6 export/upload

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="OVoCClient.xcodeproj"
SCHEME="OVoCClient"
EXPORT_OPTIONS="Config/ExportOptions.plist"
ARCHIVE="$ROOT/build/testflight/OVoCClient.xcarchive"
EXPORT_DIR="$ROOT/build/testflight/export"
LOG_DIR="$ROOT/build/logs"
ARCHIVE_LOG="$LOG_DIR/xcodebuild-archive.log"
EXPORT_LOG="$LOG_DIR/xcodebuild-export.log"
UPLOADS_LOG="$ROOT/build/testflight/uploads.log"

fail() { echo "FAIL: $1"; exit "$2"; }

# ── 0. Инструменты ──
command -v xcodebuild >/dev/null || fail "нет xcodebuild — установите Xcode и выполните: sudo xcode-select -s /Applications/Xcode.app" 2
command -v xcodegen >/dev/null  || fail "нет xcodegen — brew install xcodegen" 2
[[ -d "$PROJECT" ]] || fail "нет $PROJECT — сначала make gen (или запускайте через make testflight)" 2
[[ -d "Frameworks/OpenVPNAdapter.framework" ]] || fail "нет Frameworks/OpenVPNAdapter.framework — сначала make framework && make verify" 2
[[ -f "$EXPORT_OPTIONS" ]] || fail "нет $EXPORT_OPTIONS" 2
# Не отключается RELEASE_CHECK=0: старый бинарник нельзя отправить в TestFlight.
./scripts/verify-framework.sh || fail "фреймворк не прошёл проверку — make framework" 3

# ── 1. Чем подписывать и загружать: API-ключ или Apple ID из Xcode ──
if [[ -f "Secrets/asc.env" ]]; then
    # shellcheck disable=SC1091
    set -a; source "Secrets/asc.env"; set +a
fi
: "${ASC_AUTH:=key}"
: "${ASC_KEY_ID:=}"
: "${ASC_ISSUER_ID:=}"
ACCOUNT_AUTH=(-allowProvisioningUpdates)
case "$ASC_AUTH" in
    account)
        AUTH=("${ACCOUNT_AUTH[@]}")
        AUTH_NAME="Apple ID из Xcode"
        ;;
    key)
        [[ -n "$ASC_KEY_ID" && "$ASC_KEY_ID" != "ABC123DEFG" ]] \
            || fail "не задан ASC_KEY_ID — заполните Secrets/asc.env (шаблон: Secrets/asc.env.example) или экспортируйте переменную; без API-ключа: ASC_AUTH=account" 2
        [[ -n "$ASC_ISSUER_ID" && "$ASC_ISSUER_ID" != 12345678-* ]] \
            || fail "не задан ASC_ISSUER_ID — заполните Secrets/asc.env или экспортируйте переменную" 2
        KEY_PATH="${ASC_KEY_PATH:-$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8}"
        [[ -f "$KEY_PATH" ]] \
            || fail "нет файла ключа $KEY_PATH — скачайте AuthKey_${ASC_KEY_ID}.p8 из App Store Connect и положите в ~/.private_keys/ (docs/TESTFLIGHT.md, шаг 6.1)" 2
        AUTH=(-allowProvisioningUpdates
              -authenticationKeyPath "$KEY_PATH"
              -authenticationKeyID "$ASC_KEY_ID"
              -authenticationKeyIssuerID "$ASC_ISSUER_ID")
        AUTH_NAME="API-ключ ${ASC_KEY_ID}"
        ;;
    *)
        fail "ASC_AUTH=${ASC_AUTH} — ожидается key или account" 2
        ;;
esac

# ── 2. Согласованность: Team ID в project.yml и в ExportOptions.plist ──
TEAM_YML="$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*"?([A-Z0-9]+)"?.*/\1/p' project.yml | head -1)"
TEAM_PLIST="$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$EXPORT_OPTIONS" 2>/dev/null || true)"
[[ -n "$TEAM_YML" ]] || fail "в project.yml пустой DEVELOPMENT_TEAM" 2
[[ "$TEAM_YML" == "$TEAM_PLIST" ]] || fail "Team ID расходится: project.yml=$TEAM_YML, $EXPORT_OPTIONS=$TEAM_PLIST" 2

VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"]+)"?.*/\1/p' project.yml | head -1)"
BUILD="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([^"]+)"?.*/\1/p' project.yml | head -1)"
echo "Версия: ${VERSION} (сборка ${BUILD}), команда ${TEAM_YML}, авторизация: ${AUTH_NAME}"
if [[ -f "$UPLOADS_LOG" ]] && grep -q "	${VERSION}	${BUILD}	" "$UPLOADS_LOG"; then
    fail "сборка ${VERSION} (${BUILD}) уже загружалась (см. ${UPLOADS_LOG#"$ROOT"/}) — поднимите CURRENT_PROJECT_VERSION в project.yml и повторите make gen" 2
fi
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "  ⚠ В рабочем дереве незакоммиченные изменения — в TestFlight уйдёт то, что лежит на диске."
fi

# ── 3. Ворота ──
if [[ "${RELEASE_CHECK:-1}" != "0" ]]; then
    mkdir -p "$LOG_DIR"
    echo "Ворота Release (make release-check)…"
    ./scripts/check-release.sh >"$LOG_DIR/release-check.log" 2>&1 \
        || { grep -E "^FAIL" "$LOG_DIR/release-check.log" | sed 's/^/    /'; fail "make release-check не прошёл — лог: ${LOG_DIR#"$ROOT"/}/release-check.log" 3; }
    grep -E "^PASS" "$LOG_DIR/release-check.log" | sed 's/^/  /'
    python3 scripts/check-localization.py | sed 's/^/  /' || fail "каталог строк расходится с кодом (scripts/check-localization.py)" 3
else
    echo "  ⚠ RELEASE_CHECK=0 — ворота пропущены."
fi

# ── 4. Архив ──
mkdir -p "$LOG_DIR" "$(dirname "$ARCHIVE")"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

echo "Архив Release… (полный лог: ${ARCHIVE_LOG#"$ROOT"/})"
echo "  ⚠ При первой distribution-подписи Связка ключей может спросить пароль Mac → «Всегда разрешать»."
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
        "${AUTH[@]}" archive >"$ARCHIVE_LOG" 2>&1; then
    echo ""
    grep -E "error:|Ineligible|No profiles|No Accounts|requires a development team|ARCHIVE FAILED" "$ARCHIVE_LOG" \
        | sed 's/^[[:space:]]*//' | sort -u | head -30 | sed 's/^/    /'
    fail "xcodebuild archive не прошёл (типовые причины — docs/TESTFLIGHT.md, «Если что-то пошло не так»)" 5
fi
echo "PASS архив: ${ARCHIVE#"$ROOT"/}"

# Ворота на архиве: версии и флаг шифрования — то, из-за чего загрузку отвергают.
APP_PLIST="$ARCHIVE/Products/Applications/OVoCClient.app/Info.plist"
ARCHIVED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
ENCRYPTION="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP_PLIST" 2>/dev/null || echo "нет")"
echo "  в архиве: ${ARCHIVED_VERSION} (${ARCHIVED_BUILD}), ITSAppUsesNonExemptEncryption=${ENCRYPTION}"
[[ "$ENCRYPTION" == "false" ]] || fail "в Info.plist нет ITSAppUsesNonExemptEncryption=false — TestFlight задержит сборку вопросом про шифрование" 5
if find "$ARCHIVE/Products" \( -name "*.vpnkey" -o -name "*.ovpn" \) | grep -q .; then
    fail "в архиве лежит файл ключа" 5
fi
# Ссылки «О приложении»: для внутреннего тестирования можно без них, для внешних
# тестеров — нужны (исходники по GPL, политика конфиденциальности).
for key in OVoCSourceCodeURL OVoCPrivacyPolicyURL; do
    value="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$APP_PLIST" 2>/dev/null || true)"
    if [[ -z "$value" && "$key" == "OVoCSourceCodeURL" ]]; then
        echo "  ℹ ${key} пустой — в приложении «исходный код по запросу у разработчика» (вариант В, docs/TESTFLIGHT.md, «Исходники и ссылки»)."
    elif [[ -z "$value" ]]; then
        echo "  ⚠ ${key} пустой — для внутреннего тестирования можно; перед внешней группой задайте его в project.yml (docs/TESTFLIGHT.md, «Первая загрузка»)."
    else
        echo "  ${key}: ${value}"
    fi
done

# ── 5. Экспорт + загрузка ──
export_and_upload() {   # аргументы — флаги авторизации xcodebuild
    rm -rf "$EXPORT_DIR"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$EXPORT_DIR" \
        "$@" >"$EXPORT_LOG" 2>&1
}
export_failed() {
    echo ""
    grep -E "error:|Error Domain|EXPORT FAILED|ITMS-" "$EXPORT_LOG" \
        | sed 's/^[[:space:]]*//' | sort -u | head -30 | sed 's/^/    /'
    fail "экспорт/загрузка не прошли (коды ITMS-* — docs/TESTFLIGHT.md)" 6
}

echo "Загрузка в App Store Connect… (полный лог: ${EXPORT_LOG#"$ROOT"/})"
if ! export_and_upload "${AUTH[@]}"; then
    # Distribution-подпись через API-ключ Apple разрешает только роли Admin.
    # У Apple ID владельца аккаунта права есть — повторяем экспорт через него.
    if [[ "$ASC_AUTH" == "key" ]] && grep -q "Cloud signing permission error" "$EXPORT_LOG"; then
        cp "$EXPORT_LOG" "${EXPORT_LOG%.log}-key.log"
        echo "  ⚠ API-ключу не хватает роли Admin для distribution-подписи (Cloud signing permission error)."
        echo "    Повторяю через Apple ID из Xcode (Settings → Accounts). Чтобы не тратить попытку:"
        echo "    ASC_AUTH=account в Secrets/asc.env — либо ключ с ролью Admin."
        export_and_upload "${ACCOUNT_AUTH[@]}" || export_failed
    else
        export_failed
    fi
fi
grep -E "Upload succeeded|EXPORT SUCCEEDED" "$EXPORT_LOG" | head -2 | sed 's/^/  /' || true
# Символы встроенного фреймворка: он собирается без dSYM, отчёты о падениях внутри
# него придут без имён функций. На загрузку и работу сборки не влияет.
if grep -q "Upload Symbols Failed" "$EXPORT_LOG"; then
    echo "  ⚠ dSYM для OpenVPNAdapter.framework нет в архиве — на загрузку не влияет (docs/TESTFLIGHT.md)."
fi

printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$ARCHIVED_VERSION" "$ARCHIVED_BUILD" "$(git rev-parse --short HEAD 2>/dev/null || echo '?')" >>"$UPLOADS_LOG"
echo ""
echo "Готово: ${ARCHIVED_VERSION} (${ARCHIVED_BUILD}) загружена. Через 5–30 минут сборка появится в"
echo "App Store Connect → TestFlight; первую сборку версии проверяет Beta App Review (docs/TESTFLIGHT.md, шаг 6.3)."
echo "Срок годности сборки в TestFlight — 90 дней: следующая загрузка не позже $(date -v+85d '+%Y-%m-%d')."
