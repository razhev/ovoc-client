#!/usr/bin/env bash
set -euo pipefail

# Подписанная сборка → проверка entitlements в подписи → установка на
# подключённый iPhone → запуск. Это `make install` (этап M1 и дальше).
#
# Почему сборка идёт по UDID телефона, а не generic/platform=iOS: у новой
# команды разработчика нет ни одного зарегистрированного устройства, а без
# них Apple не выпускает development-профиль. Сборка «под конкретный телефон»
# с -allowProvisioningDeviceRegistration регистрирует его сама.
#
# Отладчик НЕ подключаем (никакого --console / lldb): Go-код Cloak под
# отладчиком деградирует до ~5 fps (golang/go#57651). Отладка — логами:
# make logs / экран «Логи» в приложении / Console.app.
#
# Коды выхода: 2 окружение · 3 нет устройства · 4 устройство не готово ·
#              5 сборка/подпись · 6 установка · 7 запуск

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="PersonalVPN.xcodeproj"
SCHEME="PersonalVPN"
APP_BUNDLE_ID="com.razhev.personalvpn"
APP_GROUP_ID="group.com.razhev.personalvpn"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphoneos/PersonalVPN.app"
LOG_DIR="$ROOT/build/logs"
BUILD_LOG="$LOG_DIR/xcodebuild-install.log"

# ── 0. Окружение ──
if grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*""' project.yml; then
    echo "FAIL: в project.yml пустой DEVELOPMENT_TEAM — впишите Team ID (developer.apple.com → Membership)."
    exit 2
fi
if [[ ! -d "$PROJECT" ]]; then
    echo "FAIL: нет $PROJECT. Сначала: make gen (или запускайте через make install)."
    exit 2
fi
if [[ ! -d "Frameworks/OpenVPNAdapter.framework" ]]; then
    echo "FAIL: нет Frameworks/OpenVPNAdapter.framework. Сначала: make fetch && make verify"
    exit 2
fi

# ── 1. Устройство ──
DEVICE_LINE="$(python3 scripts/find-device.py)" || exit $?
IFS=$'\t' read -r UDID DEVICE_NAME OS_VERSION <<<"$DEVICE_LINE"
echo "Устройство: $DEVICE_NAME (iOS $OS_VERSION)"

# ── 2. Подписанная сборка ──
mkdir -p "$LOG_DIR"
echo "Сборка с подписью… (полный лог: ${BUILD_LOG#"$ROOT"/})"
echo "  ⚠ Следите за экраном Mac: при первой подписи появится диалог Связки ключей"
echo "    «codesign хочет получить доступ к ключу…» → пароль Mac → «Всегда разрешать»."
echo "    Пока на него не ответить, сборка будет висеть."

XCODEBUILD=(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug
    -destination "id=$UDID" -destination-timeout 60
    -derivedDataPath "$DERIVED"
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration)

if ! "${XCODEBUILD[@]}" build >"$BUILD_LOG" 2>&1; then
    echo ""
    echo "FAIL: сборка/подпись не прошла. Ошибки дословно:"
    grep -E "error:|Ineligible|requires a development team|No Accounts|No profiles" "$BUILD_LOG" \
        | sed 's/^[[:space:]]*//' | sort -u | head -30 | sed 's/^/    /'
    echo ""
    echo "Доступные назначения сборки:"
    "${XCODEBUILD[@]}" -showdestinations 2>/dev/null | grep -E "platform:iOS|Ineligible" | head -12 | sed 's/^/    /' || true
    echo ""
    echo "Расшифровка типовых ошибок — docs/DEVICE-TESTING.md, раздел «Если что-то пошло не так»."
    exit 5
fi
echo "PASS сборка: BUILD SUCCEEDED"

# ── 3. Ворота: entitlements реально попали в подпись ──
# Самая частая беда Network Extension: сборка «успешна», а в подписи нет
# права на VPN или на App Group — и на телефоне всё молча не работает.
FAILED=0
for BUNDLE in "$APP" "$APP/PlugIns/PacketTunnel.appex"; do
    NAME="$(basename "$BUNDLE")"
    ENTITLEMENTS="$(codesign -d --entitlements - --xml "$BUNDLE" 2>/dev/null || true)"
    if grep -q "packet-tunnel-provider" <<<"$ENTITLEMENTS" && grep -q "$APP_GROUP_ID" <<<"$ENTITLEMENTS"; then
        echo "PASS подпись $NAME: packet-tunnel-provider + $APP_GROUP_ID"
    else
        echo "FAIL подпись $NAME: в entitlements нет packet-tunnel-provider и/или $APP_GROUP_ID"
        FAILED=1
    fi
done
TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
echo "Подписано командой: ${TEAM:-?}"
if [[ -f "$APP/embedded.mobileprovision" ]]; then
    security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -p - 2>/dev/null \
        | grep -E '"(Name|TeamName|ExpirationDate)"' | sed 's/^[[:space:]]*/    профиль: /' || true
fi
if [[ "$FAILED" -ne 0 ]]; then
    echo ""
    echo "ВОРОТА НЕ ПРОЙДЕНЫ — ставить такую сборку бессмысленно: VPN-профиль не создастся."
    echo "Проверьте на developer.apple.com → Identifiers, что у ОБОИХ App ID включены"
    echo "Network Extensions и App Groups (группа $APP_GROUP_ID), затем повторите make install."
    exit 5
fi

# ── 4. Установка ──
echo "Установка на «$DEVICE_NAME»…"
if ! xcrun devicectl device install app --device "$UDID" "$APP"; then
    echo "FAIL: установка не прошла (телефон разблокирован? Developer Mode включён?)."
    exit 6
fi

# ── 5. Запуск (без отладчика) ──
if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing "$APP_BUNDLE_ID"; then
    echo "FAIL: приложение установлено, но не запустилось — скорее всего телефон заблокирован."
    echo "      Разблокируйте и откройте PersonalVPN пальцем."
    exit 7
fi

echo ""
echo "Готово: PersonalVPN установлен и запущен на «$DEVICE_NAME»."
echo "Дальше: «Подключить» → системный диалог про конфигурации VPN → «Разрешить». Логи: make logs"
