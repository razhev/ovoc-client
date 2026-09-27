# OVoC Client — политика конфиденциальности / Privacy Policy

Действует с 27 сентября 2026 г. · Effective September 27, 2026

*English version below.*

## По-русски

OVoC Client — клиент OpenVPN over Cloak для **вашего собственного** сервера. У приложения нет своих серверов, VPN-сервиса, учётных записей, аналитики и рекламы.

**Какие данные собирает приложение.** Никакие. Разработчик не получает от приложения никаких сведений — ни о вас, ни об устройстве, ни о вашем трафике.

**Куда идёт трафик.** Когда VPN включён, трафик телефона идёт только на сервер, указанный в вашем ключе (ключ выдаёт владелец сервера). Что происходит с трафиком на сервере, определяет его владелец. Как любой клиент OpenVPN, приложение сообщает серверу свою версию и платформу. DNS-запросы идут через туннель к DNS-серверам из ключа; если в ключе их нет — к публичным DNS Cloudflare (1.1.1.1, 1.0.0.1), тоже через туннель. Если в ключе указано имя сервера, а не адрес, при импорте ключа приложение один раз узнаёт адрес сервера через обычный DNS телефона.

**Что хранится на телефоне.** Ключ (профиль подключения с сертификатами) — в настройках VPN iOS. Логи работы (`tunnel.log`, `app.log`, до 256 КБ каждый, старые строки затираются) — в контейнере приложения; в них есть адрес сервера и технические сообщения OpenVPN, но нет ключа. Те же технические сообщения пишутся в системный журнал iOS на телефоне. Логи покидают телефон только если вы сами нажмёте «Поделиться» на экране «Логи» — и уходят туда, куда вы их отправите.

**Третьи лица.** Приложение не продаёт, не использует и не передаёт данные третьим лицам ни для каких целей.

**Удаление.** Удалите приложение — iOS удалит вместе с ним его VPN-профиль и логи.

**Связь.** Вопросы — через «Отправить отзыв» в TestFlight или в разделе Issues репозитория с исходным кодом.

**Изменения.** Новая редакция политики публикуется по этому же адресу с новой датой.

## In English

OVoC Client is an OpenVPN over Cloak client for **your own** server. The app has no servers or VPN service of its own, and no accounts, analytics or ads.

**What data the app collects.** None. The developer receives no information from the app — about you, your device or your traffic.

**Where your traffic goes.** While the VPN is on, the phone's traffic goes only to the server named in your key (the key is issued by the server owner). What happens to the traffic on that server is up to its owner. Like any OpenVPN client, the app tells the server its version and platform. DNS queries go through the tunnel to the DNS servers from the key; if the key has none, to Cloudflare's public DNS (1.1.1.1, 1.0.0.1), also through the tunnel. If the key names the server by hostname rather than address, the app looks the address up once through the phone's regular DNS when the key is imported.

**What is stored on the phone.** The key (the connection profile with certificates) is kept in iOS VPN settings. Activity logs (`tunnel.log`, `app.log`, up to 256 KB each, oldest lines overwritten) are kept in the app's container; they contain the server address and OpenVPN technical messages, but not the key. The same technical messages are written to the iOS system log on the phone. Logs leave the phone only if you tap Share on the Logs screen yourself — and go wherever you send them.

**Third parties.** The app does not sell, use or disclose any data to third parties for any purpose.

**Deletion.** Delete the app, and iOS removes its VPN profile and logs with it.

**Contact.** Questions — via “Send Beta Feedback” in TestFlight or in the Issues section of the source code repository.

**Changes.** A revised policy is published at this same address with a new date.
