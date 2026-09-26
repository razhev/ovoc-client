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

## Предпосылки

- Платный аккаунт Apple Developer одобрен, Team ID вписан в `project.yml` (`DEVELOPMENT_TEAM`).
- `make install` хотя бы раз проходил: он зарегистрировал на портале App ID
  `com.razhev.ovocclient` и `com.razhev.ovocclient.tunnel` с нужными capability. Без этого
  запись приложения в App Store Connect создать нельзя (bundle ID выбирается из списка портала).
- `Frameworks/OpenVPNAdapter.framework` собран (`make framework`), `make verify` — 3×PASS.
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
   - **Bundle ID**: выбрать из списка `com.razhev.ovocclient` (если в списке нет — см.
     предпосылки: `make install` не запускался или упал до регистрации App ID).
   - **SKU**: любая строка без пробелов, например `ovocclient`.
   - **User Access**: Full Access.
3. **Create**. Bundle ID после первой загрузки сборки уже не меняется.

Больше на этом экране ничего заполнять не нужно: скриншоты, описание для App Store, цена —
это для публикации, а не для TestFlight.

### б) API-ключ App Store Connect

Ключ нужен, чтобы `xcodebuild` заливал сборку без пароля Apple ID и двухфакторного кода.

1. App Store Connect → **Users and Access** → вкладка **Integrations** → **App Store Connect API**
   → **Team Keys**.
2. Если видна кнопка **Request Access** — нажать и подтвердить (это делает Account Holder,
   один раз; для личного аккаунта Account Holder — вы).
3. **Generate API Key** (или «+»):
   - **Name**: `ovocclient testflight`;
   - **Access**: **App Manager**.
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
2. Читает `Secrets/asc.env` (или переменные окружения `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   необязательно `ASC_KEY_PATH`), проверяет, что файл ключа `~/.private_keys/AuthKey_<Key ID>.p8`
   существует.
3. Сверяет Team ID в `project.yml` и `Config/ExportOptions.plist`; печатает версию и номер
   сборки; отказывается заливать номер, который уже заливался (`build/testflight/uploads.log`).
4. **Ворота**: `make release-check` (в бандле нет DEBUG-моста и ни одного файла ключа) и
   `scripts/check-localization.py` (каталог строк сходится с кодом). Пропустить, если только что
   гоняли: `RELEASE_CHECK=0 make testflight`.
5. `xcodebuild archive` — Release, `generic/platform=iOS`, автоподпись через API-ключ
   (`-allowProvisioningUpdates`): distribution-профили для приложения и расширения Xcode
   заводит сам. Архив: `build/testflight/OVoCClient.xcarchive`, лог:
   `build/logs/xcodebuild-archive.log`. При первой distribution-подписи Связка ключей может
   спросить пароль Mac — ответить «Всегда разрешать», иначе сборка висит.
6. Ворота на архиве: `CFBundleShortVersionString`/`CFBundleVersion` печатаются,
   `ITSAppUsesNonExemptEncryption=false` обязателен (иначе TestFlight задержит сборку вопросом
   про шифрование), файлов ключа в архиве нет.
7. `xcodebuild -exportArchive` с `Config/ExportOptions.plist` (`method: app-store-connect`,
   `destination: upload`) — переподписывает и **загружает** сборку. Лог:
   `build/logs/xcodebuild-export.log`.
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

## Шаг 6.3 — Внешняя группа тестеров и публичная ссылка (человек)

Делается после того, как первая сборка прошла Processing (App Store Connect → приложение →
вкладка **TestFlight** → в разделе **iOS Builds** сборка со статусом не «Processing»).

### а) Информация для тестирования (один раз)

TestFlight → слева **Test Information**:

- **Beta App Description** (что тестируем): «Личный VPN-клиент к собственному серверу OpenVPN
  over Cloak. Ключ выдаёт владелец сервера.»
- **Feedback Email**: ваш адрес.
- **Privacy Policy URL**: если поле обязательно — ссылка на любую страницу с текстом «Приложение
  не собирает и не передаёт никаких данных, кроме трафика к вашему собственному VPN-серверу»
  (подойдёт GitHub Gist или страница репозитория, если он публичный).
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
OVoC Client is a personal VPN client for a self-hosted OpenVPN over Cloak server
(AmneziaVPN server-side). It is distributed via TestFlight to the developer's family
only, is not intended for the App Store, and has no accounts, sign-in, purchases or
analytics. The app ships empty: the user pastes a "vpn://..." key issued by the server
owner on the "Add key" screen, then taps "Connect". The first connection triggers the
standard iOS "Would Like to Add VPN Configurations" prompt — please tap Allow.

A working test key is attached (test-key.txt). Steps: open the app → "Add key" →
paste the key → "Import" → Allow → "Connect". The status should change to "Connected"
and the VPN icon should appear in the status bar. Logs are available on the "Logs"
screen. The key belongs to a dedicated test client and will be revoked after review.

The app uses only standard TLS/AES cryptography (ITSAppUsesNonExemptEncryption = NO).
```

Файл `test-key.txt` — строка `vpn://…` тестового клиента (в репозиторий не класть; `*.vpnkey`
и `Secrets/` в `.gitignore`).

### Запасной вариант: внутренние тестеры (если ревью буксует)

Внутренним тестерам ревью не нужно вообще, сборка доступна сразу после Processing. Цена —
каждого тестера надо добавить в команду по Apple ID:

1. App Store Connect → **Users and Access** → **«+»** → имя, фамилия, e-mail Apple ID
   родственника, роль **Customer Support** (минимальная) → **Invite**. Родственник принимает
   приглашение по письму.
2. TestFlight → **Internal Testing** → **«+»** → группа, например `Семья (внутр.)` → добавить
   пользователей → включить **Enable automatic distribution** (новые сборки уходят сами).
3. Родственник получает письмо со ссылкой; дальше — как по публичной ссылке.

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
| `FAIL: make release-check не прошёл` | в Release попал DEBUG-мост или файл ключа | `make release-check` — смотреть строки `FAIL` |
| archive: «No profiles for 'com.razhev.ovocclient' were found» / «doesn't include the … entitlement» | автоподпись не смогла завести distribution-профиль | проверить, что у API-ключа роль App Manager; на портале у обоих App ID включены Network Extensions и App Groups; повторить |
| archive: «Cloud signing permission error» / «You don't have permission to create a certificate» | роли ключа не хватает для выпуска distribution-сертификата | создать новый ключ с ролью **Admin**, вписать в `Secrets/asc.env` |
| archive висит на CodeSign | ждёт диалог Связки ключей | пароль Mac → «Всегда разрешать»; запускать из Terminal.app, не из песочницы |
| export: `ITMS-90189` / «Redundant Binary Upload» | такая пара версия+сборка уже есть в App Store Connect | поднять `CURRENT_PROJECT_VERSION` |
| export: `ITMS-90062` / «CFBundleShortVersionString … must be greater» | версия ниже, чем уже загруженная | поднять `MARKETING_VERSION` |
| export: «Missing Compliance» / вопрос про шифрование в App Store Connect | в Info.plist нет `ITSAppUsesNonExemptEncryption` | скрипт это проверяет; в `project.yml` флаг есть — пересобрать `make gen` |
| export: «The bundle … cannot be uploaded: no app record» | шаг 6.1а не сделан или bundle ID в записи другой | App Store Connect → Apps: запись с `com.razhev.ovocclient` |
| export: `ITMS-90424` / «Invalid Swift Support» и прочие ITMS-9xxx | несовпадение версий приложения и расширения, битый фреймворк | `make verify`; версии в `project.yml` общие для обоих таргетов — проверить, что `PacketTunnel/Info.plist` не правили руками |
| сборка в TestFlight «Processing» дольше часа | обычная задержка Apple | подождать; письмо придёт |
| ревью отклонено «Guideline 5.4 – VPN Apps» | ревьюер решил, что это App Store-публикация | ответить в Resolution Center: TestFlight only, personal server, см. заметки; либо внутренние тестеры |
| родственник: «Beta has expired» | прошло 90 дней | поднять номер сборки → `make testflight` |
| родственник: ссылка «This beta isn't accepting any new testers» | исчерпан лимит публичной ссылки | увеличить лимит в группе |
