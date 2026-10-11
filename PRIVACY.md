# OVoC Client — политика конфиденциальности / Privacy Policy

Редакция от 6 октября 2026 г., начиная со сборки 0.1.0 (4).
Effective October 6, 2026, starting with build 0.1.0 (4).

*English version below.*

## По-русски

OVoC Client — клиент OpenVPN over Cloak для **вашего собственного** сервера. У приложения нет своих серверов, VPN-сервиса, учётных записей, аналитики и рекламы.

**Контакт.** Разработчик OVoC Client, razhev.n@gmail.com.

### Какие данные собираются и как используются

**Разработчик не собирает никаких данных через приложение** — ни о вас, ни об устройстве, ни о вашем трафике. В приложении нет сторонних SDK для аналитики, рекламы или отслеживания.

Что приложение обрабатывает, чтобы работать:

- **Ключ подключения** (профиль с сертификатами), который вы вставляете сами. Хранится только на телефоне, в настройках VPN iOS. Используется только для подключения к серверу из этого ключа.
- **Ваш трафик**, пока VPN включён, следует маршрутам профиля VPN. На экране «Без VPN» вы можете дополнительно включить прямое подключение для сетей Ozon, Wildberries и Яндекса. Эти соединения используют обычную сеть телефона, а сервисы видят её IP-адрес. Правила действуют по IP: сторонний сервис на том же адресе тоже может подключаться напрямую. Остальной трафик сохраняет маршрутизацию профиля. Что происходит с трафиком на VPN-сервере, определяет его владелец. Как любой клиент OpenVPN, приложение сообщает этому серверу свою версию и платформу.
- **Выбор исключений** сохраняется только в профиле VPN на телефоне. По умолчанию новые исключения выключены. Встроенный каталог поставляется вместе с приложением; приложение не загружает удалённые списки и не собирает историю посещений для его обновления.
- **DNS-запросы.** Идут через туннель к DNS-серверам из ключа. Если в ключе их нет — к публичному DNS Cloudflare (1.1.1.1, 1.0.0.1), тоже через туннель. Если в ключе указано имя сервера, а не адрес, при импорте приложение один раз узнаёт адрес сервера через обычный DNS телефона.
- **Логи работы** (`tunnel.log`, `app.log`). Остаются на телефоне; в них есть адрес сервера и технические сообщения OpenVPN, но нет ключа. Те же сообщения пишутся в системный журнал iOS на телефоне. Логи уходят с телефона, только если вы сами нажмёте «Поделиться» на экране «Логи», — туда, куда вы их отправите.

### Третьи стороны

Приложение не собирает данные для разработчика, аналитики или рекламы и не продаёт их. Сетевые соединения доставляют ваши запросы адресатам через VPN или напрямую согласно выбранным исключениям.

Если в ключе нет своих DNS-серверов, системные DNS-запросы идут к публичному DNS Cloudflare через VPN. Сведения Cloudflare об обработке этих запросов: <https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver/>. Исключения не переключают системный DNS на обычную сеть. Приложения со своим DNS-протоколом создают обычные сетевые соединения, к которым применяются IP-маршруты.

**TestFlight.** Если вы получили приложение через TestFlight, Apple собирает данные о тестировании по своей политике (<https://www.apple.com/legal/privacy/>). Разработчику из них доступны: имя и email, с которыми вас пригласили (при публичной ссылке — анонимно), число запусков, отчёты о сбоях, модель устройства и версия iOS, а также отзывы и снимки экрана, которые вы отправите сами.

### Хранение и удаление

- Логи: не больше 256 КБ на файл, старые строки затираются. Лежат на телефоне, пока установлено приложение.
- Ключ: лежит в настройках VPN, пока вы не удалите профиль или приложение.
- Выбор исключений: хранится вместе с профилем; его можно сбросить на экране «Без VPN» при отключённом соединении.
- **Удалить всё:** удалите приложение — iOS удалит его профиль VPN и логи. Только ключ: Настройки → Основные → VPN и управление устройством → VPN → профиль OVoC Client → удалить.
- У разработчика ваших данных нет, удалять на его стороне нечего. Данные TestFlight удаляются по правилам Apple; чтобы выйти из тестирования — TestFlight → OVoC Client → «Прекратить тестирование».

### Отзыв согласия

Разрешение на VPN отзывается удалением профиля VPN (см. выше). Логи никуда не уходят без вашего нажатия «Поделиться». Вопросы и запросы — razhev.n@gmail.com.

### Изменения

Новая редакция политики публикуется по этому же адресу с новой датой.

## In English

OVoC Client is an OpenVPN over Cloak client for **your own** server. The app has no servers or VPN service of its own, and no accounts, analytics or ads.

**Contact.** The developer of OVoC Client, razhev.n@gmail.com.

### What data is collected and how it is used

**The developer collects no data through the app** — about you, your device or your traffic. The app contains no third-party analytics, advertising or tracking SDKs.

What the app processes in order to work:

- **The connection key** (a profile with certificates) that you paste in yourself. Stored only on the phone, in iOS VPN settings. Used only to connect to the server named in that key.
- **Your traffic** while the VPN is on follows your VPN profile's routes. In Outside VPN, you can additionally enable direct connections to Ozon, Wildberries and Yandex networks. Those connections use the phone's regular network, and the services see that network's IP address. Rules apply to IP addresses: an unrelated service sharing the same address may also connect directly. Other traffic keeps the profile's routing policy. What happens to traffic on the VPN server is up to its owner. Like any OpenVPN client, the app tells that server its version and platform.
- **Your exception selection** is stored only in the VPN profile on your phone. New exceptions are off by default. The catalog ships with the app; the app does not download remote lists or collect browsing history to update it.
- **DNS queries.** They go through the tunnel to the DNS servers from the key; if the key has none, to Cloudflare's public DNS (1.1.1.1, 1.0.0.1), also through the tunnel. If the key names the server by hostname rather than address, the app looks the address up once through the phone's regular DNS when the key is imported.
- **Activity logs** (`tunnel.log`, `app.log`). They stay on the phone; they contain the server address and OpenVPN technical messages, but not the key. The same messages are written to the iOS system log on the phone. Logs leave the phone only if you tap Share on the Logs screen yourself — and go wherever you send them.

### Third parties

The app does not collect data for the developer, analytics or advertising, and does not sell it. Network connections deliver your requests to their destinations through the VPN or directly according to your selected exceptions.

If your key has no DNS servers of its own, system DNS queries go to Cloudflare's public DNS through the VPN. Cloudflare describes its processing here: <https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver/>. Exceptions do not move system DNS to the regular network. Apps using their own DNS protocols create network connections that follow the IP routing rules.

**TestFlight.** If you got the app through TestFlight, Apple collects testing data under its own policy (<https://www.apple.com/legal/privacy/>). Of that data, the developer can see: the name and email you were invited with (anonymous for a public link), the number of sessions, crash reports, device model and iOS version, and any feedback and screenshots you choose to send.

### Retention and deletion

- Logs: at most 256 KB per file, oldest lines overwritten. They stay on the phone while the app is installed.
- Key: stays in VPN settings until you delete the profile or the app.
- Exception selection: stays with the profile; you can reset it in Outside VPN while disconnected.
- **Delete everything:** delete the app, and iOS removes its VPN profile and logs. The key only: Settings → General → VPN & Device Management → VPN → OVoC Client profile → delete.
- The developer holds none of your data, so there is nothing to delete on the developer's side. TestFlight data is deleted under Apple's rules; to leave the beta — TestFlight → OVoC Client → Stop Testing.

### Withdrawing consent

You withdraw the VPN permission by deleting the VPN profile (see above). Logs never leave the phone unless you tap Share. Questions and requests — razhev.n@gmail.com.

### Changes

A revised policy is published at this same address with a new date.
