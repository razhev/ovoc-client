# TestFlight: раздача OVoC Client родственникам (M6)

**TestFlight** — официальный способ Apple раздавать сборки до App Store: приложение TestFlight
на телефоне тестера скачивает вашу сборку по ссылке-приглашению. Сборка живёт **90 дней**, потом
её нужно перезалить. Публикации в App Store не требуется, ревью — короткое (Beta App Review,
обычно 1–2 дня, только первая сборка каждой версии).

Разделение труда: шаги **6.1** и **6.3** делаются руками в браузере (App Store Connect не
управляется из CLI без отдельной API-обвязки), шаг **6.2** — одна команда `make testflight`.

| Шаг | Кто | Что |
|---|---|---|
| 6.1 | человек | запись приложения в App Store Connect + API-ключ |
| 6.2 | `make testflight` | архив Release → загрузка |
| 6.3 | человек | группа внешних тестеров + публичная ссылка + заметки для ревью |
| 6.4 | — | шаблон сообщения родственникам, памятка «90 дней» — ниже в этом файле |

---

## Сборка 0.1.0 (4) — 2026-10-06

Загружена по запросу пользователя после реализации экспериментального экрана «Без VPN».
`xcodebuild` подтвердил `Upload succeeded` и `EXPORT SUCCEEDED`. Исключения для Ozon,
Wildberries и Яндекса (включая Go) по умолчанию выключены. Проверку на iPhone пользователь
отложил; совместимость сервисов ещё не подтверждена.

Перед загрузкой пройдены 81 тест, проверка 128 строк ru/en, Release-проверки и проверка
происхождения OpenVPNAdapter. В архиве сверены версия 0.1.0 (4) приложения/расширения
и совпадение встроенного каталога с исходником. Политика конфиденциальности обновлена
по существующей ссылке приложения. Известное предупреждение загрузки: у встроенного
OpenVPNAdapter отсутствует dSYM; Apple приняла сборку.

App Store Connect API подтвердил `processingState=VALID` и
`internalBuildState=IN_BETA_TESTING`; сборка `8c989c84-1494-4bc4-8f58-3bfd83a162bd`
доступна в `Internal Testing Group` с одним существующим тестером. Группа имеет
автоматический доступ к новым сборкам. Заметки What to Test сохранены и прочитаны
обратно для `ru` и `en-GB`.
Внешняя группа продолжает использовать сборку 2; новая сборка на Beta App Review не отправлялась.

Проверка: отключить VPN → «Без VPN» → выбрать сервисы → сохранить → подключить VPN.
Сценарии: [DEVICE-TESTING.md](DEVICE-TESTING.md#проверка-исключений-российских-сервисов).
Если выбранный сервис или подключение перестали работать, отключить VPN, выключить
исключения, сохранить и подключиться снова. Ранее доступные сборки не удалялись.

---

## Первая загрузка — что сделать руками, по порядку

В репозитории к первой загрузке всё готово (2026-09-27):
- privacy manifest у приложения, расширения и фреймворка;
- тексты лицензий и экран «О приложении» — он открывается нажатием на название на главном экране;
- карточка «Что с данными» на экране импорта ключа (этого требует правило App Store 5.4);
- политика конфиденциальности [PRIVACY.md](../PRIVACY.md);
- новые проверки в `make release-check`.

Флаг `ITSAppUsesNonExemptEncryption=false` оставлен сознательно: по таблице Apple для
стандартных алгоритмов документы нужны только при раздаче в App Store во Франции (подробно —
комментарий в `project.yml`).

Дальше — только руками. **Часть 1** — сборка у вас на телефоне через TestFlight (внутреннее
тестирование, без ревью Apple). **Часть 2** — раздача другим людям.

**Проверено через App Store Connect API 2026-10-02:** сборка **0.1.0 (2)** обработана
(`processingState=VALID`), состояния внутреннего и внешнего тестирования — `IN_BETA_TESTING`.
Точная дата одобрения не установлена. Проверки IPv6-only сети и P1 при смене сети на
физическом iPhone по-прежнему не выполнены. Ниже сохранён ход первой загрузки.

**Состояние на 2026-09-28:**
- Шаги 1–6 пройдены: сборка **0.1.0 (1)** стоит у вас через TestFlight и работает.
- Для внешней группы:
  - политика ([PRIVACY.md](../PRIVACY.md), сверена с правилами Apple 5.1.1(i) и 5.4) и
    тестовый ключ ревьюера выложены секретными Gist;
  - Test Information заполнена на английском и сохранена;
  - сборка **2** — со ссылкой на политику внутри приложения (5.1.1(i) требует её и в приложении).
- Исходники — вариант В (по запросу).
- **Сборка 2 отправлена на Beta App Review 2026-09-28** (шаг 11, через App Store Connect API):
  - «What to Test» задан на английском;
  - сборка добавлена в «External Testing Group» (тестеров и публичной ссылки пока нет);
  - статус — Waiting for Beta Review.
- Проверка в IPv6-only сети (шаг 10) не делалась.
- После ответа Apple:
  - одобрят → удалить пользователя `appreview` в Amnezia и Gist с тестовым ключом; публичная
    ссылка или приглашения — по решению;
  - откажут → шаг 12.

### Часть 1. Первая сборка у себя (≈ 1 час, из них 5–30 минут — ожидание Apple)

1. **Обновить фреймворк на Mac:** `make framework && make verify`. С 2026-10-02 нужны
   четыре проверки, включая квитанцию `Frameworks/OpenVPNAdapter.build.json`; одного
   добавления privacy manifest к старому бинарнику недостаточно. Затем `make release-check`:
   все строки `PASS`, в том числе «privacy manifest» и «лицензии».
2. **Соглашения Apple.** Открыть <https://appstoreconnect.apple.com> под Apple ID аккаунта
   разработчика.
   - Если наверху баннер о новом соглашении (Apple Developer Program License Agreement) — открыть
     и принять. Пока оно не принято, загрузка отказывает.
   - Договор Paid Apps, налоговые формы и банковский счёт для бесплатного приложения **не нужны**.
3. **Запись приложения** — шаг 6.1а ниже: Apps → «+» → New App, SKU `ovocclient`. В списке
   **Bundle ID** нужная строка называется `XC com razhev ovocclient - com.razhev.ovocclient`.
   Регистрировать Bundle ID руками не нужно: его уже завёл `make install`.
4. **API-ключ** — шаг 6.1б ниже. Это **не** внутри страницы приложения, а в общем разделе
   «Users and Access» — прямая ссылка: <https://appstoreconnect.apple.com/access/integrations/api>.
   - вкладка Integrations → Team Keys → «Generate API Key» (или «+»), роль App Manager;
   - роли App Manager хватает, если в Xcode добавлен ваш Apple ID: подпись для распространения
     скрипт тогда делает через него. Подписывать самим ключом Apple разрешает только роли Admin;
   - скачать `.p8` — его можно скачать **только один раз**;
   - положить файл в `~/.private_keys/`;
   - Key ID и Issuer ID вписать в `Secrets/asc.env` (или сказать агенту).
5. **Загрузить сборку**: `make testflight` в Terminal.app — или попросить агента.
   - Связка ключей может спросить пароль Mac → «Всегда разрешать».
   - В конце должно быть `Готово: 0.1.0 (1) загружена`.
   - Два предупреждения `⚠ OVoCSourceCodeURL пустой` и `⚠ OVoCPrivacyPolicyURL пустой` для
     этой части нормальны.
6. **Поставить себе.**
   - Через 5–30 минут: App Store Connect → OVoC Client → вкладка **TestFlight**. Сборка выйдет
     из «Processing».
   - **Internal Testing** → «+» → группа, например `Я` → добавить себя → в группе **Builds** →
     «+» → сборка.
   - Тестер получает письмо от TestFlight. Само приложение в TestFlight на телефоне не
     появляется — только после «View in TestFlight» → **Accept** в этом письме (или **Redeem**
     с кодом из письма, если на iPhone другой Apple ID).
   - **Если письма нет, а у тестера статус «No Builds Available»**, ждать бесполезно. Письмо
     уходит, только если в группе уже была готовая сборка, когда туда добавили тестера. Так было
     при первой загрузке 2026-09-28. Исправить: TestFlight → слева Testers → **All** → галочка у
     тестера → **Reinvite**.
   - На iPhone: поставить **TestFlight** из App Store → письмо → **Accept** → OVoC Client →
     **Install**. Сборка из TestFlight заменит установленную по кабелю (bundle ID тот же). Если
     профиль VPN пропал — импортировать ключ заново.
   - **Проверка:**
     - нажать на название «OVoC Client» вверху главного экрана → «О приложении»: версия, «Что с
       данными», лицензия, список компонентов (каждый открывает полный текст);
     - кнопка-ключ → вверху карточка «Что с данными», внизу «О приложении и лицензиях»;
     - «Подключить» → сайт-определитель показывает IP сервера.

### Часть 2. Раздача другим людям — внешняя группа (≈ 1–2 дня из-за ревью)

7. **Решить, где будут исходники.** Лицензия GPL: каждый, кто получил сборку, должен иметь доступ
   к её исходному коду. Варианты и команды — раздел «Исходники и ссылки» ниже:
   - **А.** Новый публичный репозиторий со свежей историей — рекомендуется: в ней нет ваших email
     и отладочной переписки.
   - **Б.** Сделать публичным текущий `personal-ios-client` — в истории видны email из коммитов.
   - **В.** Только для своих — приватный доступ по запросу. Ссылки не публикуются, в приложении
     остаётся «Исходный код можно получить у разработчика».
8. **Опубликовать политику конфиденциальности** — текст готов в [PRIVACY.md](../PRIVACY.md).
   - При вариантах А/Б — ссылка на файл в публичном репозитории.
   - При варианте В — «секретный» Gist (раздел «Исходники и ссылки»).
   - Ссылки вписать в `project.yml` (`OVoCSourceCodeURL`, `OVoCPrivacyPolicyURL`) или передать
     агенту. Поднять номер сборки и снова `make testflight` — предупреждений о пустых ссылках
     больше не будет.
9. **Тестовый ключ для ревьюера.**
   - В AmneziaVPN: сервер → «Поделиться» → протокол OpenVPN over Cloak → **новый пользователь**
     (например, `appreview`) → формат «Для приложения AmneziaVPN».
   - Сохранить как `test-key.txt` **вне репозитория**.
   - Личный ключ ревьюерам не давать. После ревью этого пользователя удалить в Amnezia.
10. **Проверка в сети только с IPv6** — раздел «Проверка в IPv6-only сети» ниже, с ключом из
    шага 9. Apple проверяет приложения именно в такой сети. Если не подключается — на ревью не
    отправлять, прислать агенту `make logs`.
11. **Внешняя группа и ревью** — шаг 6.3:
    - Test Information: описание, email для отзывов, **Privacy Policy URL** из шага 8, контакт
      для ревью;
    - группа → публичная ссылка → сборка;
    - заметки для ревью (готовый текст ниже) + вложение `test-key.txt` → **Submit for Review**.
12. **Ответ Apple** — обычно 1–2 дня.
    - **«Ready to Test»** — ссылку можно раздавать, шаблон сообщения — шаг 6.4.
    - **Отказ по «Guideline 5.4 – VPN Apps»** — ответить в Resolution Center (текст ниже) или
      перейти на внутренних тестеров (до 100 человек, без ревью).

---

## Предпосылки

- Платный аккаунт Apple Developer одобрен, Team ID вписан в `project.yml` (`DEVELOPMENT_TEAM`).
- `make install` хотя бы раз проходил: он зарегистрировал на портале App ID
  `com.razhev.ovocclient` и `com.razhev.ovocclient.tunnel` с нужными capability. Без этого
  запись приложения в App Store Connect создать нельзя (bundle ID выбирается из списка портала).
- `Frameworks/OpenVPNAdapter.framework` собран (`make framework`), `make verify` — 4×PASS. В
  фреймворке лежит privacy manifest (`make framework` кладёт его сам; для собранного раньше —
  `make framework-manifest`).
- `make release-check` — зелёный. Его `make testflight` прогоняет сам, но лучше знать заранее.

---

## Шаг 6.1 — App Store Connect: запись приложения и API-ключ (человек, один раз)

### а) Запись приложения

1. Открыть <https://appstoreconnect.apple.com> → **Apps** (Приложения) → **«+»** → **New App**.
2. Заполнить:
   - **Platforms**: iOS.
   - **Name**: `OVoC Client` (имя в App Store Connect; должно быть уникальным среди всех
     приложений Apple — если занято, добавить что-нибудь: `OVoC Client (razhev)`; на телефоне
     всё равно показывается `CFBundleDisplayName` из `project.yml`).
   - **Primary Language**: Russian.
   - **Bundle ID**: выбрать из списка строку `XC com razhev ovocclient - com.razhev.ovocclient`.
     - Приставку `XC` и имя с пробелами дал Xcode, когда `make install` сам регистрировал этот
       идентификатор. Важна правая часть — `com.razhev.ovocclient`.
     - Регистрировать Bundle ID руками на портале не нужно. Портал ответит, что такой
       идентификатор недоступен, — именно потому, что он уже зарегистрирован у вас.
     - Не выбирать `XC Wildcard - *` и строку расширения `…ovocclient.tunnel`. Не вписывать
       другой идентификатор (например, `com.razhev`): загрузка не найдёт запись приложения.
     - Если нужной строки в списке нет — см. предпосылки: `make install` не запускался или упал
       до регистрации App ID.
   - **SKU**: любая строка без пробелов, например `ovocclient`.
   - **User Access**: Full Access.
3. **Create**. Bundle ID после первой загрузки сборки уже не меняется.

**Если запись создана не с тем Bundle ID.** Пока не загружена ни одна сборка, его можно
поменять: приложение → вкладка **Distribution** → слева **General → App Information** → блок
**General Information** → список **Bundle ID** → `XC com razhev ovocclient -
com.razhev.ovocclient` → **Save**. Лишний идентификатор, заведённый руками, можно удалить на
<https://developer.apple.com/account/resources/identifiers/list> — или оставить, он ничему не
мешает.

Больше на этом экране ничего заполнять не нужно: скриншоты, описание для App Store, цена —
это для публикации, а не для TestFlight. Страница «iOS App Version 1.0» с кнопкой **Add for
Review** — тоже про App Store: её не трогать. Всё, что нужно для TestFlight, — на вкладке
**TestFlight**.

### б) API-ключ App Store Connect

Ключ нужен, чтобы `xcodebuild` заливал сборку без пароля Apple ID и двухфакторного кода.

1. Открыть <https://appstoreconnect.apple.com/access/integrations/api>. Это общий раздел
   App Store Connect, а не страница приложения: со страницы приложения туда ведёт логотип
   «App Store Connect» в самом верху (на главную) → **Users and Access** → вкладка
   **Integrations** → слева **App Store Connect API** → **Team Keys**.
2. Если видна кнопка **Request Access** — нажать и подтвердить (это делает Account Holder,
   один раз; для личного аккаунта Account Holder — вы).
3. **Generate API Key** (или «+»):
   - **Name**: `ovocclient testflight`;
   - **Access**: **App Manager**.

   Про роль. Подпись сборки для распространения (distribution) через API-ключ Apple разрешает
   только ключу с ролью **Admin**. С ролью App Manager экспорт отвечает «Cloud signing
   permission error» — и `make testflight` сам повторяет его через Apple ID, добавленный в
   Xcode → Settings → Accounts (у владельца аккаунта права есть). Так прошла первая загрузка
   2026-09-28. Ключ с ролью Admin нужен, только если Apple ID в Xcode нет (например, на сервере
   сборки): такой ключ может управлять всем аккаунтом, хранить его надо строже.
4. **Generate**. На странице появятся **Issuer ID** (вверху, общий для команды) и строка ключа
   с **Key ID**. Нажать **Download API Key** — скачается `AuthKey_<Key ID>.p8`.
   **Скачать можно только один раз**: если файл потерян — ключ отозвать (Revoke) и сделать новый.
5. Положить ключ туда, где его ищет скрипт (Xcode тоже смотрит именно в этот каталог):

   ```bash
   mkdir -p ~/.private_keys
   mv ~/Downloads/AuthKey_*.p8 ~/.private_keys/
   chmod 600 ~/.private_keys/AuthKey_*.p8
   ```

6. Записать реквизиты в файл, который не попадает в git:

   ```bash
   cp Secrets/asc.env.example Secrets/asc.env
   # открыть Secrets/asc.env и вписать ASC_KEY_ID и ASC_ISSUER_ID со страницы ключей
   ```

   Проверка, что секреты не утекут в репозиторий: `git status --short Secrets/` должен показать
   только `Secrets/asc.env.example` (и то лишь пока он не закоммичен). `*.p8` дополнительно
   запрещены в `.gitignore` по расширению.

---

## Шаг 6.2 — `make testflight`

```bash
make testflight
```

Что делает `scripts/upload-testflight.sh`, по порядку (каждая проверка при неудаче печатает
`FAIL: …` и останавливается, ничего не заливая):

1. Проверяет инструменты: `xcodebuild`, `xcodegen`, наличие фреймворка, `Config/ExportOptions.plist`.
   Запускает `make verify`: архитектура, Cloak, API и квитанция сборки с текущим AEAD-патчем.
2. Читает `Secrets/asc.env` (или переменные окружения `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   необязательно `ASC_KEY_PATH`), проверяет, что файл ключа `~/.private_keys/AuthKey_<Key ID>.p8`
   существует. С `ASC_AUTH=account` (в `Secrets/asc.env` или в окружении) ключ не нужен вовсе:
   подпись и загрузка идут через Apple ID из Xcode.
3. Сверяет Team ID в `project.yml` и `Config/ExportOptions.plist`; печатает версию и номер
   сборки; отказывается заливать номер, который уже заливался (`build/testflight/uploads.log`).
4. **Ворота**: `make release-check` (в бандле нет DEBUG-моста и ни одного файла ключа; privacy
   manifest у приложения, расширения и фреймворка; тексты лицензий на месте) и
   `scripts/check-localization.py` (каталог строк сходится с кодом). Пропустить, если только что
   гоняли: `RELEASE_CHECK=0 make testflight`. Проверка фреймворка из пункта 1 не отключается.
5. `xcodebuild archive` — Release, `generic/platform=iOS`, автоподпись через API-ключ
   (`-allowProvisioningUpdates`): distribution-профили для приложения и расширения Xcode
   заводит сам. Архив: `build/testflight/OVoCClient.xcarchive`, лог:
   `build/logs/xcodebuild-archive.log`. При первой distribution-подписи Связка ключей может
   спросить пароль Mac — ответить «Всегда разрешать», иначе сборка висит.
6. Ворота на архиве: `CFBundleShortVersionString`/`CFBundleVersion` печатаются,
   `ITSAppUsesNonExemptEncryption=false` обязателен (иначе TestFlight задержит сборку вопросом
   про шифрование), файлов ключа в архиве нет. Ссылки `OVoCSourceCodeURL` и
   `OVoCPrivacyPolicyURL` печатаются; пустые — только предупреждение `⚠` (для внутреннего
   тестирования можно, перед внешней группой — «Первая загрузка», шаги 7–8).
7. `xcodebuild -exportArchive` с `Config/ExportOptions.plist` (`method: app-store-connect`,
   `destination: upload`) — переподписывает и **загружает** сборку. Лог:
   `build/logs/xcodebuild-export.log`. Если ключу не хватило роли («Cloud signing permission
   error»), экспорт повторяется через Apple ID из Xcode; лог первой попытки —
   `build/logs/xcodebuild-export-key.log`.
8. Дописывает строку в `build/testflight/uploads.log` (дата, версия, сборка, коммит) и печатает
   дату, до которой нужно перезалить следующую сборку.

Занимает 5–10 минут (из них ворота — две сборки без подписи — большую часть). Сборка появляется в
App Store Connect → TestFlight через 5–30 минут после «Upload succeeded» (стадия Processing).

### Номер сборки — поднимать руками перед каждой загрузкой

Apple различает загрузки по паре `CFBundleShortVersionString` (версия, `MARKETING_VERSION`) и
`CFBundleVersion` (номер сборки, `CURRENT_PROJECT_VERSION`). Обе живут в `project.yml`, в
`settings.base`; `App/Info.plist` и `PacketTunnel/Info.plist` берут их оттуда через `$(…)`
(версии расширения обязаны совпадать с версиями приложения — так и происходит).

Правило: **каждая загрузка — новый номер сборки**, строго больше предыдущего для той же версии.
Автоматики нет намеренно (`manageAppVersionAndBuildNumber: false` в ExportOptions): номер в
`app.log`, в `git log` и в TestFlight — один и тот же.

```bash
# перед make testflight:
sed -i '' 's/CURRENT_PROJECT_VERSION: "1"/CURRENT_PROJECT_VERSION: "2"/' project.yml   # 1 → 2
git commit -am "release: сборка 2"
make testflight
```

Версию (`MARKETING_VERSION`, `0.1.0` → `0.2.0`) поднимать, когда изменилось поведение —
каждая новая версия снова проходит Beta App Review; новые сборки внутри той же версии — нет.

---

## Исходники и ссылки (перед внешней группой)

**Зачем.** OVoC Client распространяется по GPL-3.0 (почему именно так —
[THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md)). Внешний тестер получает сборку, значит,
должен иметь доступ к её исходникам. Кроме того, TestFlight просит URL политики
конфиденциальности. Публикуете вы сами (или агент по вашему прямому слову): это публичное действие
под вашим именем.

### Вариант А — новый публичный репозиторий со свежей историей (рекомендуется)

В нём один коммит с текущим кодом: без личных email из истории и без отладочной переписки. Имя
репозитория — любое, ниже `ovoc-client`.

```bash
# 0. посмотреть, что уйдёт в публикацию (секреты и ключи в git не попадают — .gitignore)
git ls-files | less

# 1. снимок текущего коммита во временную папку
SNAP="$(mktemp -d)"
git archive --format=tar HEAD | tar -x -C "$SNAP"

# 2. новая история от имени, за которым GitHub прячет почту (noreply-адрес)
cd "$SNAP"
git init -q -b main
EMAIL="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
git add -A
git -c user.name="razhev" -c user.email="$EMAIL" commit -q -m "OVoC Client 0.1.0 (1)"

# 3. публичный репозиторий
gh repo create razhev/ovoc-client --public --source . --push \
  --description "iOS client for self-hosted OpenVPN over Cloak servers (GPL-3.0)"
```

Ссылки: исходники — `https://github.com/razhev/ovoc-client`, политика —
`https://github.com/razhev/ovoc-client/blob/main/PRIVACY.md`. Для каждой следующей раздаваемой
версии в этот репозиторий добавляется новый коммит с тем же содержимым — попросите агента, он
сделает снимок тем же способом.

### Вариант Б — открыть текущий репозиторий

```bash
gh repo edit razhev/personal-ios-client --visibility public --accept-visibility-change-consequences
```

Ссылки: `https://github.com/razhev/personal-ios-client` и
`https://github.com/razhev/personal-ios-client/blob/main/PRIVACY.md`. В истории будут видны email
из коммитов (gmail и yandex) и вся отладка. Реальных ключей и IP сервера в истории нет
(проверено 2026-09-26).

### Вариант В — только для своих

Ссылка на исходники не публикуется. Кто попросит — даёте доступ к приватному репозиторию (GitHub →
репозиторий → Settings → Collaborators) или архив исходников. Политика конфиденциальности всё
равно нужна по URL:

1. <https://gist.github.com> → имя файла `PRIVACY.md` → вставить текст из
   [PRIVACY.md](../PRIVACY.md) → **Create secret gist**.
2. Скопировать адрес страницы. «Секретный» gist не находится поиском, но открывается по ссылке
   без входа.

`OVoCSourceCodeURL` остаётся пустым, в `OVoCPrivacyPolicyURL` — адрес gist.

### Вписать ссылки в сборку

`project.yml`, таргет `OVoCClient` → `info` → `properties`:

```yaml
        OVoCSourceCodeURL: "https://github.com/razhev/ovoc-client"
        OVoCPrivacyPolicyURL: "https://github.com/razhev/ovoc-client/blob/main/PRIVACY.md"
```

Дальше поднять `CURRENT_PROJECT_VERSION` (см. «Номер сборки» выше), закоммитить,
`make testflight`. В приложении ссылки появятся на экране «О приложении» и в карточке «Что с
данными».

---

## Проверка в IPv6-only сети (NAT64)

**Зачем.** Apple проверяет приложения в сети, где есть только IPv6 (правило 2.5.5). А наш путь до
сервера рассчитан на IPv4:
- адрес сервера в ключе — IPv4;
- исключение маршрута — `/32`;
- если VPN-сервер не выдал IPv6-настройки, расширение ставит «раковину» с маршрутом по умолчанию в туннель.

Как Cloak поведёт себя в такой сети, заранее неизвестно — лучше увидеть самим, чем получить отказ
ревью.

**Нужно:** Mac с проводным интернетом (Ethernet или USB-C-адаптер) — Mac раздаёт его по Wi-Fi.
Если провода нет, проверку пропустить и помнить о возможном отказе по 2.5.5.

1. Выключить VPN на Mac: с kill switch раздача не заработает.
2. Системные настройки → Основные → Общий доступ → «Общий интернет» → (i):
   - «Общее подключение» — Ethernet (или адаптер);
   - «Для устройств, использующих» — Wi-Fi.
3. **Зажать Option** — в том же окне должен появиться флажок «Создать сеть NAT64». Включить его,
   затем включить «Общий интернет».
4. iPhone: Настройки → Wi-Fi → сеть Mac. В Safari открыть любой сайт — должен открыться (через
   NAT64).
5. В OVoC Client из TestFlight: кнопка-ключ → тестовый ключ из шага 9 «Первой загрузки» →
   «Подключить». Ожидаем «VPN включён» и IP сервера на сайте-определителе.
6. Не подключилось — снять `make logs` (телефон по кабелю) и прислать агенту. Вероятные причины
   чинятся в коде: Cloak подключается к IPv4-адресу там, где IPv4 нет, или соединение уходит в
   петлю через синтетический IPv6-адрес сервера.
7. Вернуть телефон в обычную сеть, импортировать свой ключ обратно, выключить «Общий интернет».

---

## Шаг 6.3 — Внешняя группа тестеров и публичная ссылка (человек)

Делается после того, как первая сборка прошла Processing (App Store Connect → приложение →
вкладка **TestFlight** → в разделе **iOS Builds** сборка со статусом не «Processing»).

### а) Информация для тестирования (один раз)

TestFlight → слева **Test Information**:

- **Beta App Description** (что тестируем): «Личный VPN-клиент к собственному серверу OpenVPN
  over Cloak. Ключ выдаёт владелец сервера.»
- **Feedback Email**: ваш адрес.
- **Privacy Policy URL**: ссылка из шага 8 «Первой загрузки» (текст — [PRIVACY.md](../PRIVACY.md);
  публичный репозиторий или «секретный» Gist).
- **Beta App Review Information**: контакт (имя, телефон, e-mail); **Sign-in required** — нет
  (аккаунтов в приложении нет).

### б) Группа и публичная ссылка

1. TestFlight → **External Testing** (Внешнее тестирование) → **«+»** → имя группы, например
   `Семья` → **Create**.
2. В группе → **Public Link** → **Enable Public Link** → задать лимит тестеров (например, 10;
   максимум 10 000) → скопировать ссылку вида `https://testflight.apple.com/join/XXXXXXXX`.
3. В группе → **Builds** → **«+»** → выбрать загруженную сборку → **Next**.
4. Появится форма для Beta App Review: **What to Test** (что проверять) и заметки. Вставить
   текст из раздела ниже, приложить файл с тестовым ключом (поле **Attachment**) → **Submit for
   Review**.
5. Статус сборки: **Waiting for Review** → **In Review** → **Ready to Test** (обычно 1–2 дня; у
   VPN-утилит вопросов, как правило, не возникает). После этого ссылка работает.

Что важно про ревью: **отдельный тестовый ключ.** На сервере (AmneziaVPN → «Поделиться» →
выбрать/создать отдельного клиента) сделать ключ только для ревьюера и после «Ready to Test»
его отозвать. Личный ключ ревьюерам не давать.

### Заметки для Beta App Review (готовый текст, на английском — ревью читает по-английски)

**What to Test:**

```
Connect to the owner's private OpenVPN-over-Cloak server using the attached key,
verify the VPN status indicator appears in the iOS status bar, browse a few websites,
then disconnect.
```

**Notes (Beta App Review Information → Notes):**

```
OVoC Client is a VPN client for self-hosted OpenVPN over Cloak servers (AmneziaVPN
server-side). It offers no VPN service of its own: no servers, accounts, sign-in,
purchases, ads or analytics, and it collects no user data (see the "Your Data" card
on the key import screen and the privacy policy). It is distributed via TestFlight
to a small group of testers.

The app ships empty: the user pastes a "vpn://..." key issued by the server owner on
the "Add Key" screen, then taps "Connect". The first import triggers the standard iOS
"Would Like to Add VPN Configurations" prompt — please tap Allow.

A working test key is attached (test-key.txt). Steps: open the app → "Add Key" →
"Paste" → "Import" → Allow → "Connect". The status should change to "VPN is on" and
the VPN icon should appear in the status bar. Logs are on the "Logs" screen; licenses
and the data notice are under "About" (tap the app name at the top of the main
screen). The key belongs to a dedicated test client and will be revoked after review.
```

Слова «not intended for the App Store» из текста убраны сознательно. Правило 2.2: сборки для
TestFlight должны быть рассчитаны на публичное распространение, и такая фраза даёт повод отказать.

**Ответ в Resolution Center при отказе по «Guideline 5.4 – VPN Apps»** (аккаунт у нас Individual,
а правило 5.4 допускает VPN-приложения только от организаций — повод к отказу возможен):

```
Thank you for the review. OVoC Client does not offer a VPN service: it has no servers,
accounts or purchases, and it collects no user data. It is a client for a server that
the user runs themselves — the same model as the WireGuard or OpenVPN Connect clients —
distributed via TestFlight to a small group of testers. Could you please reconsider
this build for TestFlight testing?
```

Если отказ повторили — не спорить, перейти на внутренних тестеров (ниже).

Файл `test-key.txt` — строка `vpn://…` тестового клиента (в репозиторий не класть; `*.vpnkey`
и `Secrets/` в `.gitignore`).

### Запасной вариант: внутренние тестеры (если ревью буксует)

Внутренним тестерам ревью не нужно вообще: сборка доступна сразу после Processing. Цена — каждого
тестера надо сделать пользователем вашего App Store Connect (у аккаунта Individual — до 50
пользователей, у них доступ только к App Store Connect, не к сертификатам):

1. App Store Connect → **Users and Access** (<https://appstoreconnect.apple.com/access/users>) →
   **«+»**:
   - имя, фамилия, e-mail человека;
   - роль **Marketing**. Внутренними тестерами Apple разрешает быть только ролям Account Holder,
     Admin, App Manager, Developer и Marketing; Marketing — самая узкая из них. Customer Support
     **не подходит**;
   - **Apps**: только OVoC Client;
   - **Invite**.
2. Человек получает письмо от App Store Connect, принимает приглашение и входит своим Apple ID
   (если на этот адрес Apple ID нет — заводит его).
3. **После** принятия: TestFlight → **Internal Testing Group** (или своя группа, например
   `Семья (внутр.)` с **Enable automatic distribution**) → **Testers** → **«+»** → отметить
   человека → **Add**. Сборка в группе уже есть, так что письмо от TestFlight уходит сразу; если
   статус «No Builds Available» — Testers → All → **Reinvite**.
4. Человек открывает письмо на iPhone (iOS 16+) → **View in TestFlight** → **Accept** →
   **Install**. Ключ — его личный, отдельным сообщением (шаг 6.4).

Лимит — 100 внутренних тестеров. Оба варианта можно держать одновременно.

---

## Шаг 6.4 — Сообщение родственникам (шаблон)

Ключ отправлять **отдельным сообщением** и не в общий чат: это приватный ключ и сертификат,
по нему подключаются к вашему серверу. Лучше — мессенджером с исчезающими сообщениями или
голосовым звонком с последующей отправкой.

```
Привет! Ставлю тебе VPN на iPhone — три шага, минут пять.

1. Установи из App Store приложение «TestFlight» (это официальное приложение Apple
   для тестовых программ): https://apps.apple.com/app/testflight/id899247664

2. Открой на телефоне эту ссылку и нажми «Установить»:
   https://testflight.apple.com/join/XXXXXXXX
   Появится приложение «OVoC Client».

3. Открой OVoC Client → «Добавить ключ». Ключ пришлю следующим сообщением — скопируй его
   целиком (можно вообще всё сообщение, лишнее отбросится), в приложении нажми
   «Вставить» → «Импортировать». iOS спросит «OVoC Client хочет добавить конфигурации
   VPN» — нажми «Разрешить» и введи код-пароль телефона (спрашивает один раз).

Дальше — просто кнопка «Подключить»; когда сверху появится значок VPN, всё работает.
Выключить — «Отключить».

Если что-то не так: в приложении справа вверху есть «Логи» → «Поделиться» — пришли мне
файлы, разберусь. Раз в 2–3 месяца TestFlight будет предлагать обновление — просто
соглашайся.
```

---

## Памятка: перезаливать сборку каждые ≤ 90 дней

- Сборка в TestFlight действует **90 дней** с момента загрузки; по истечении приложение у
  тестеров перестаёт запускаться («Beta has expired»), пока не выйдет новая сборка.
- `make testflight` в конце печатает дату «не позже …» (загрузка + 85 дней). Поставить
  напоминание в календаре на эту дату: `поднять CURRENT_PROJECT_VERSION → make testflight`.
- Все загрузки — в `build/testflight/uploads.log` (локально, в git не попадает).
- Новая сборка той же версии ревью не проходит и уходит тестерам сразу; у кого включено
  автообновление в TestFlight, обновится сама.
- Новая **версия** (`MARKETING_VERSION`) — снова Beta App Review, снова ключ ревьюеру.

---

## Если что-то пошло не так

| Симптом | Причина | Что делать |
|---|---|---|
| `FAIL: не задан ASC_KEY_ID` / `ASC_ISSUER_ID` | нет `Secrets/asc.env` или в нём остались значения из примера | шаг 6.1б, п. 6 |
| `FAIL: нет файла ключа ~/.private_keys/AuthKey_….p8` | `.p8` не скачан / лежит не там / Key ID с опечаткой | шаг 6.1б, п. 4–5; проверить `ls ~/.private_keys` |
| `FAIL: Team ID расходится` | правили `DEVELOPMENT_TEAM` в `project.yml`, а `Config/ExportOptions.plist` — нет | вписать тот же Team ID в plist |
| `FAIL: сборка … уже загружалась` | номер сборки не поднят | «Номер сборки» выше |
| `FAIL происхождение фреймворка` | нет квитанции сборки или её коммиты/хэши не совпадают с текущими исходниками, патчем и бинарником | `make framework && make verify`; готовый v1.0.42 использовать нельзя |
| `FAIL: make release-check не прошёл` | в Release попал DEBUG-мост или файл ключа; нет privacy manifest или текстов лицензий | `make release-check` — смотреть строки `FAIL` |
| `FAIL privacy manifest` в release-check | фреймворк собран до 2026-09-27; или расширение собрано инкрементально сразу после добавления манифеста | `make framework-manifest`; начисто: `rm -rf build/DerivedData-check && make release-check` |
| письмо или ошибка `ITMS-91053: Missing API declaration` | в коде появился новый required reason API, не объявленный в манифесте | добавить категорию и причину в `App/PrivacyInfo.xcprivacy` (`PacketTunnel/…`, `Config/OpenVPNAdapter-PrivacyInfo.xcprivacy`) — как в комментариях этих файлов |
| `⚠ OVoCSourceCodeURL пустой` / `⚠ OVoCPrivacyPolicyURL пустой` | ссылки ещё не заданы | для внутреннего тестирования — ничего; перед внешней группой — «Первая загрузка», шаги 7–8 |
| archive: «No profiles for 'com.razhev.ovocclient' were found» / «doesn't include the … entitlement» | автоподпись не смогла завести distribution-профиль | проверить, что у API-ключа роль App Manager; на портале у обоих App ID включены Network Extensions и App Groups; повторить |
| export: `⚠ API-ключу не хватает роли Admin…`, затем загрузка проходит | у ключа роль App Manager; скрипт повторил экспорт через Apple ID из Xcode | ничего; чтобы не тратить попытку — `ASC_AUTH=account` в `Secrets/asc.env` |
| export: «Cloud signing permission error» и повтор тоже не прошёл («No Accounts», ошибка входа) | в Xcode нет Apple ID или сессия устарела | Xcode → Settings → Accounts → добавить Apple ID (или войти заново); либо новый ключ с ролью **Admin** в `Secrets/asc.env` |
| export: `warning: Upload Symbols Failed … dSYM for the OpenVPNAdapter.framework` | фреймворк собирается без отладочных символов | ничего: на загрузку и работу не влияет; отчёты о падениях внутри фреймворка придут без имён функций |
| archive висит на CodeSign | ждёт диалог Связки ключей | пароль Mac → «Всегда разрешать»; запускать из Terminal.app, не из песочницы |
| export: `ITMS-90189` / «Redundant Binary Upload» | такая пара версия+сборка уже есть в App Store Connect | поднять `CURRENT_PROJECT_VERSION` |
| export: `ITMS-90062` / «CFBundleShortVersionString … must be greater» | версия ниже, чем уже загруженная | поднять `MARKETING_VERSION` |
| export: «Missing Compliance» / вопрос про шифрование в App Store Connect | в Info.plist нет `ITSAppUsesNonExemptEncryption` | скрипт это проверяет; в `project.yml` флаг есть — пересобрать `make gen` |
| export: «The bundle … cannot be uploaded: no app record» / «No suitable application records were found» | шаг 6.1а не сделан или bundle ID в записи другой | поменять Bundle ID записи на `com.razhev.ovocclient` — шаг 6.1а, «Если запись создана не с тем Bundle ID» |
| export: `ITMS-90424` / «Invalid Swift Support» и прочие ITMS-9xxx | несовпадение версий приложения и расширения, битый фреймворк | `make verify`; версии в `project.yml` общие для обоих таргетов — проверить, что `PacketTunnel/Info.plist` не правили руками |
| сборка в TestFlight «Processing» дольше часа | обычная задержка Apple | подождать; письмо придёт |
| ревью отклонено «Guideline 5.4 – VPN Apps» | аккаунт Individual, а правило 5.4 допускает VPN-приложения только от организаций | ответить в Resolution Center — готовый текст в шаге 6.3; при повторном отказе — внутренние тестеры |
| ревью отклонено по 2.1 / 2.5.5 («не удалось подключиться», IPv6) | ревьюер в сети только с IPv6, а путь до сервера рассчитан на IPv4 | раздел «Проверка в IPv6-only сети»; `make logs` агенту — чинится в коде |
| родственник: «Beta has expired» | прошло 90 дней | поднять номер сборки → `make testflight` |
| родственник: ссылка «This beta isn't accepting any new testers» | исчерпан лимит публичной ссылки | увеличить лимит в группе |
