# OVoC Client — политика конфиденциальности / Privacy Policy

Действует с 28 сентября 2026 г. · Effective September 28, 2026

*English version below.*

## По-русски

OVoC Client — клиент OpenVPN over Cloak для **вашего собственного** сервера. У приложения нет своих серверов, VPN-сервиса, учётных записей, аналитики и рекламы.

**Контакт.** Разработчик OVoC Client, razhev.n@gmail.com.

### Какие данные собираются и как используются

**Разработчик не собирает никаких данных через приложение** — ни о вас, ни об устройстве, ни о вашем трафике. В приложении нет сторонних SDK для аналитики, рекламы или отслеживания.

Что приложение обрабатывает, чтобы работать:

- **Ключ подключения** (профиль с сертификатами), который вы вставляете сами. Хранится только на телефоне, в настройках VPN iOS. Используется только для подключения к серверу из этого ключа.
- **Ваш трафик**, пока VPN включён. Идёт только на сервер, указанный в ключе (ключ выдаёт владелец сервера). Что происходит с трафиком на сервере, определяет его владелец. Как любой клиент OpenVPN, приложение сообщает этому серверу свою версию и платформу.
- **DNS-запросы.** Идут через туннель к DNS-серверам из ключа. Если в ключе их нет — к публичному DNS Cloudflare (1.1.1.1, 1.0.0.1), тоже через туннель. Если в ключе указано имя сервера, а не адрес, при импорте приложение один раз узнаёт адрес сервера через обычный DNS телефона.
- **Логи работы** (`tunnel.log`, `app.log`). Остаются на телефоне; в них есть адрес сервера и технические сообщения OpenVPN, но нет ключа. Те же сообщения пишутся в системный журнал iOS на телефоне. Логи уходят с телефона, только если вы сами нажмёте «Поделиться» на экране «Логи», — туда, куда вы их отправите.

### Третьи стороны

Приложение **не продаёт, не использует и не передаёт третьим лицам никакие данные ни для каких целей**.

Единственная третья сторона, до которой могут дойти ваши данные, — публичный DNS Cloudflare, если в ключе нет своих DNS-серверов. Запросы приходят к нему с адреса вашего VPN-сервера, а не телефона. Cloudflare обязуется не продавать и не передавать эти данные и удалять IP-адреса в течение 25 часов: <https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver/>.

**TestFlight.** Если вы получили приложение через TestFlight, Apple собирает данные о тестировании по своей политике (<https://www.apple.com/legal/privacy/>). Разработчику из них доступны: имя и email, с которыми вас пригласили (при публичной ссылке — анонимно), число запусков, отчёты о сбоях, модель устройства и версия iOS, а также отзывы и снимки экрана, которые вы отправите сами.

### Хранение и удаление

- Логи: не больше 256 КБ на файл, старые строки затираются. Лежат на телефоне, пока установлено приложение.
- Ключ: лежит в настройках VPN, пока вы не удалите профиль или приложение.
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
- **Your traffic** while the VPN is on. It goes only to the server named in your key (the key is issued by the server owner). What happens to the traffic on that server is up to its owner. Like any OpenVPN client, the app tells that server its version and platform.
- **DNS queries.** They go through the tunnel to the DNS servers from the key; if the key has none, to Cloudflare's public DNS (1.1.1.1, 1.0.0.1), also through the tunnel. If the key names the server by hostname rather than address, the app looks the address up once through the phone's regular DNS when the key is imported.
- **Activity logs** (`tunnel.log`, `app.log`). They stay on the phone; they contain the server address and OpenVPN technical messages, but not the key. The same messages are written to the iOS system log on the phone. Logs leave the phone only if you tap Share on the Logs screen yourself — and go wherever you send them.

### Third parties

The app **does not sell, use or disclose any data to third parties for any purpose**.

The only third party your data may reach is Cloudflare's public DNS, if the key has no DNS servers of its own. Queries reach it from your VPN server's address, not your phone's. Cloudflare commits not to sell or share this data and to delete IP addresses within 25 hours: <https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver/>.

**TestFlight.** If you got the app through TestFlight, Apple collects testing data under its own policy (<https://www.apple.com/legal/privacy/>). Of that data, the developer can see: the name and email you were invited with (anonymous for a public link), the number of sessions, crash reports, device model and iOS version, and any feedback and screenshots you choose to send.

### Retention and deletion

- Logs: at most 256 KB per file, oldest lines overwritten. They stay on the phone while the app is installed.
- Key: stays in VPN settings until you delete the profile or the app.
- **Delete everything:** delete the app, and iOS removes its VPN profile and logs. The key only: Settings → General → VPN & Device Management → VPN → OVoC Client profile → delete.
- The developer holds none of your data, so there is nothing to delete on the developer's side. TestFlight data is deleted under Apple's rules; to leave the beta — TestFlight → OVoC Client → Stop Testing.

### Withdrawing consent

You withdraw the VPN permission by deleting the VPN profile (see above). Logs never leave the phone unless you tap Share. Questions and requests — razhev.n@gmail.com.

### Changes

A revised policy is published at this same address with a new date.
