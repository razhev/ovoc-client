import SwiftUI

/// «О приложении»: что это, какие данные, лицензия и исходники, компоненты
/// и их лицензии (полные тексты — `App/Licenses`, шрифты — `App/Fonts`).
///
/// Зачем экран. OVoC Client распространяется по GPLv3 (внутри — AGPL-код
/// OpenVPNAdapter/OpenVPN3 и GPL-код Cloak). §5(d) GPLv3: интерфейс программы
/// показывает уведомление — чья программа, что гарантий нет, где текст лицензии.
/// Ссылки на исходники и политику конфиденциальности — из Info.plist
/// (`OVoCSourceCodeURL`, `OVoCPrivacyPolicyURL` в project.yml); пустые не показываются.
///
/// Вход — нажатие на название приложения на главном экране и ссылка внизу экрана
/// импорта ключа (его видит каждый новый пользователь).
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    PkHeading(text: Text(verbatim: Bundle.main.displayName), size: 34)
                    Text("Версия \(Bundle.main.shortVersion) (сборка \(Bundle.main.buildNumber))")
                        .font(.pkText(14, relativeTo: .subheadline))
                        .foregroundStyle(Pk.zola)
                }
                .padding(.horizontal, 4)

                PkCard {
                    Text("Клиент OpenVPN over Cloak для вашего собственного сервера. Своих серверов и VPN-сервиса у приложения нет: подключение идёт только к серверу из ключа, который выдал владелец сервера.")
                        .font(.pkText(15))
                        .foregroundStyle(Pk.sazha)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DataNoticeCard()

                sectionTitle(Text("Лицензия"))
                PkCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: "© 2026 razhev")
                            .font(.pkText(15, .semibold))
                            .foregroundStyle(Pk.sazha)
                        Text("OVoC Client — свободная программа: её можно распространять и изменять на условиях GNU General Public License версии 3. Программа поставляется без каких-либо гарантий. Тексты лицензий — ниже.")
                            .font(.pkText(14, relativeTo: .footnote))
                            .foregroundStyle(Pk.sazha)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = AppLinks.sourceCode {
                            Link(destination: url) {
                                Label { Text("Исходный код") } icon: { PkIconView(icon: .scroll, size: 18) }
                            }
                            .font(.pkText(15, .medium))
                            .tint(Pk.izrazets)
                        } else {
                            Text("Исходный код можно получить у разработчика — например, через «Отправить отзыв» в TestFlight.")
                                .font(.pkText(14, relativeTo: .footnote))
                                .foregroundStyle(Pk.zola)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                sectionTitle(Text("Компоненты и лицензии"))
                PkCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(LicenseItem.all.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Rectangle().fill(Pk.dash).frame(height: 1.5).padding(.horizontal, 10)
                            }
                            NavigationLink {
                                LicenseTextView(title: item.name, resource: item.resource)
                            } label: {
                                LicenseRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Уведомление о товарном знаке — дословно, по правилам OpenVPN Inc.
                    Text(verbatim: "OpenVPN® is a registered trademark of OpenVPN Inc.")
                    Text("Приложение не связано с Amnezia и OpenVPN Inc.")
                }
                .font(.pkText(12, relativeTo: .caption))
                .foregroundStyle(Pk.zola)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Pk.smetana.ignoresSafeArea())
        .navigationTitle(Text("О приложении"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("О приложении")
                    .font(.pkDisplay(22, relativeTo: .headline))
                    .foregroundStyle(Pk.sazha)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .tint(Pk.sazha)
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(.pkText(15, .semibold, relativeTo: .subheadline))
            .foregroundStyle(Pk.zola)
            .padding(.leading, 4)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Карточка «Что с данными» — раскрытие по правилу App Store 5.4: VPN-приложение
/// до первого использования говорит, какие данные собирает и зачем. Стоит в начале
/// экрана импорта ключа (до кнопки «Импортировать») и на экране «О приложении».
/// Флага «уже видел» нет — ни UserDefaults, ни лишнего окна при запуске.
struct DataNoticeCard: View {
    var body: some View {
        PkMessageCard(icon: .clipboard) {
            Text("Что с данными")
                .font(.pkText(16, .semibold, relativeTo: .headline))
                .foregroundStyle(Pk.sazha)
            Text("В приложении нет аналитики, рекламы и учётных записей. Трафик идёт через сервер из вашего ключа; включённые вами исключения на экране «Без VPN» подключаются напрямую и видят IP обычной сети. Ключ и выбор исключений хранятся в настройках VPN на телефоне. Логи остаются на телефоне и отправляются, только если вы нажмёте «Поделиться» на экране «Логи».")
                .font(.pkText(14, relativeTo: .footnote))
                .foregroundStyle(Pk.zola)
                .fixedSize(horizontal: false, vertical: true)
            if let url = AppLinks.privacyPolicy {
                Link(destination: url) { Text("Политика конфиденциальности") }
                    .font(.pkText(14, .medium))
                    .tint(Pk.izrazets)
                    .padding(.top, 2)
            }
        }
    }
}

/// Ссылки из Info.plist (project.yml). Пустая строка — ссылки нет.
enum AppLinks {
    static var sourceCode: URL? { url(forKey: "OVoCSourceCodeURL") }
    static var privacyPolicy: URL? { url(forKey: "OVoCPrivacyPolicyURL") }

    private static func url(forKey key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}

/// Компонент и файл с текстом его лицензии в бандле (`<resource>.txt`).
/// Имена и идентификаторы лицензий — как есть, без перевода.
private struct LicenseItem {
    let name: String
    let license: String
    let role: Text
    let resource: String

    static let all: [LicenseItem] = [
        LicenseItem(name: "OVoC Client", license: "GPL-3.0", role: Text("этот клиент"), resource: "OVoCClient-GPL-3.0"),
        LicenseItem(name: "Cloak", license: "GPL-3.0", role: Text("маскировка трафика, форк Amnezia"), resource: "OVoCClient-GPL-3.0"),
        LicenseItem(name: "OpenVPNAdapter", license: "AGPL-3.0", role: Text("OpenVPN для iOS, форк Amnezia"), resource: "OpenVPNAdapter-AGPL-3.0"),
        LicenseItem(name: "OpenVPN 3", license: "AGPL-3.0", role: Text("ядро протокола OpenVPN"), resource: "OpenVPN3-LICENSE"),
        LicenseItem(name: "OpenVPN 3 · mbed TLS · asio · LZ4", license: "AGPL-3.0 · Apache-2.0 · BSL-1.0 · BSD-2-Clause",
                    role: Text("библиотеки внутри фреймворка"), resource: "OpenVPNAdapter-NOTICE"),
        LicenseItem(name: "Go", license: "BSD-3-Clause", role: Text("рантайм плагина Cloak"), resource: "Go-LICENSE"),
        LicenseItem(name: "brotli · connutil · circl · websocket · ratelimit · compress · utls · logrus · x/crypto · x/net · x/sys",
                    license: "MIT · Apache-2.0 · BSD · LGPL-3.0", role: Text("модули Go в плагине Cloak"), resource: "Cloak-Go-modules"),
        LicenseItem(name: "Marmelad", license: "OFL-1.1", role: Text("шрифт"), resource: "OFL-marmelad"),
        LicenseItem(name: "Rubik", license: "OFL-1.1", role: Text("шрифт"), resource: "OFL-rubik"),
        LicenseItem(name: "PT Mono", license: "OFL-1.1", role: Text("шрифт"), resource: "OFL-ptmono"),
    ]
}

private struct LicenseRow: View {
    let item: LicenseItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.name)
                    .font(.pkText(15, .medium))
                    .foregroundStyle(Pk.sazha)
                    .fixedSize(horizontal: false, vertical: true)
                (item.role + Text(verbatim: " · \(item.license)"))
                    .font(.pkText(13, relativeTo: .footnote))
                    .foregroundStyle(Pk.zola)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            PkIconView(icon: .back, size: 16)
                .scaleEffect(x: -1)   // та же стрелка «назад», развёрнутая вперёд
                .foregroundStyle(Pk.zola)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Полный текст лицензии из бандла. Тексты длинные (до ~56 КБ) — абзацы в ленивом
/// стеке, чтобы экран открывался сразу.
private struct LicenseTextView: View {
    let title: String
    let resource: String

    var body: some View {
        ScrollView {
            if let paragraphs = Self.paragraphs(resource) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(verbatim: paragraph)
                            .font(.pkMono(11))
                            .foregroundStyle(Pk.sazha)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
                .padding(16)
            } else {
                Text("Не удалось открыть текст лицензии.")
                    .font(.pkText(15))
                    .foregroundStyle(Pk.klyukva)
                    .padding(16)
            }
        }
        .background(Pk.muka.ignoresSafeArea())
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .tint(Pk.sazha)
    }

    private static func paragraphs(_ resource: String) -> [String]? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
    }
}
