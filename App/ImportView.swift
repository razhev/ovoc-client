import SwiftUI
import UniformTypeIdentifiers

/// Экран импорта ключа vpn://: вставка из буфера или файл из «Файлов».
/// Всю работу делает `TunnelManager.importKey` — тот же путь, что у DEBUG-моста.
///
/// Ключ — это приватный ключ и сертификаты: экран его не логирует, не хранит
/// дольше импорта и очищает поле при успехе и при закрытии.
///
/// Локализация: каждый видимый текст — ОДИН строковый литерал (ключ каталога).
/// Склейка через `+` дала бы `String`, и SwiftUI показал бы его без перевода.
struct ImportView: View {
    @ObservedObject var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var error: String?
    @State private var importing = false
    @State private var pickingFile = false

    /// Ключ занимает килобайты; всё, что заметно больше, — не ключ, и читать
    /// такой файл в память незачем.
    private static let maxFileSize = 1_000_000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SackArt()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    // Правило App Store 5.4: до первого использования VPN — какие данные и зачем.
                    DataNoticeCard()

                    Text("Ключ")
                        .font(.pkText(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Pk.zola)
                        .padding(.leading, 4)

                    PkCard {
                        VStack(spacing: 12) {
                            // PasteButton, а не чтение UIPasteboard: системная кнопка не
                            // вызывает запрос «Разрешить вставку из …?». Её вид задаёт
                            // система — «Печка» меняет только цвет и форму.
                            PasteButton(payloadType: String.self) { strings in
                                text = strings.first ?? ""
                                error = nil
                            }
                            .tint(Pk.izrazets)
                            .buttonBorderShape(.capsule)
                            .labelStyle(.titleAndIcon)
                            .controlSize(.large)
                            .disabled(importing)

                            Button {
                                pickingFile = true
                            } label: {
                                Label { Text("Выбрать файл с ключом…") } icon: { PkIconView(icon: .chest, size: 20) }
                            }
                            .buttonStyle(PkSmallButtonStyle())
                            .disabled(importing)

                            TextEditor(text: $text)
                                .font(.pkMono(12))
                                .foregroundStyle(Pk.sazha)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(height: 110)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Pk.smetana))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Pk.sazha, lineWidth: 2))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .disabled(importing)
                                .overlay(alignment: .topLeading) {
                                    if text.isEmpty {
                                        Text(verbatim: "vpn://…")
                                            .font(.pkMono(12))
                                            .foregroundStyle(Pk.zola.opacity(0.7))
                                            .padding(.top, 14)
                                            .padding(.leading, 12)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                    }

                    footnote(Text("Ключ выдаёт владелец сервера. В AmneziaVPN: «Поделиться» → протокол OpenVPN over Cloak → формат «Для приложения AmneziaVPN» → «Копировать». Можно вставить сообщение целиком — ключ найдётся сам."))

                    Button(action: importFromField) {
                        HStack(spacing: 10) {
                            if importing {
                                ProgressView().tint(Pk.muka)
                                Text("Импортирую…")
                            } else {
                                Text("Импортировать")
                            }
                        }
                    }
                    .buttonStyle(PkButtonStyle(kind: .primary, height: 60))
                    .disabled(importing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 6)

                    if let error {
                        PkMessageCard(icon: .smoke, badge: Pk.klyukvaTint, badgeInk: Pk.klyukva) {
                            Text(verbatim: error)
                                .font(.pkText(15))
                                .foregroundStyle(Pk.sazha)
                                .textSelection(.enabled)
                        }
                    }

                    if tunnel.status == .connected || tunnel.status == .connecting || tunnel.status == .reasserting {
                        footnote(Text("VPN сейчас включён — на время смены ключа он будет отключён."))
                    }
                    if !tunnel.hasRealConfig {
                        footnote(Text("Дальше iOS спросит: «\(Bundle.main.displayName) хочет добавить конфигурации VPN». Нажмите «Разрешить» и введите код-пароль — без этого разрешения приложение не может включать VPN. Спрашивают один раз."))
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label { Text("О приложении и лицензиях") } icon: { PkIconView(icon: .pechka, size: 18) }
                            .font(.pkText(14, .medium, relativeTo: .footnote))
                            .foregroundStyle(Pk.izrazets)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .disabled(importing)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Pk.smetana.ignoresSafeArea())
            .navigationTitle(tunnel.hasRealConfig ? Text("Сменить ключ") : Text("Добавить ключ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    (tunnel.hasRealConfig ? Text("Сменить ключ") : Text("Добавить ключ"))
                        .font(.pkDisplay(22, relativeTo: .headline))
                        .foregroundStyle(Pk.sazha)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .font(.pkText(17, .medium))
                        .tint(Pk.izrazets)
                        .disabled(importing)
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.item]) { result in
                importFromFile(result)
            }
            .interactiveDismissDisabled(importing)
            .onDisappear { text = "" }
        }
    }

    private func footnote(_ text: Text) -> some View {
        text
            .font(.pkText(13, relativeTo: .footnote))
            .foregroundStyle(Pk.zola)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func importFromField() {
        run(text, source: .paste)
    }

    /// `.item` — любой файл: у `.vpnkey` нет зарегистрированного типа, а ключ
    /// могут прислать и как `.txt`.
    private func importFromFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }   // отмена выбора — не ошибка

        // Файл вне песочницы приложения: доступ к нему выдан только на время чтения.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maxFileSize else {
            error = String(localized: "Файл слишком большой для ключа. Выберите файл, в котором лежит строка vpn://…")
            return
        }
        guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) else {
            error = String(localized: "Не удалось прочитать файл как текст. В файле должен лежать ключ vpn://…")
            return
        }
        run(content, source: .file)
    }

    private func run(_ key: String, source: TunnelManager.KeySource) {
        error = nil
        importing = true
        Task {
            defer { importing = false }
            do {
                try await tunnel.importKey(key, source: source)
                text = ""
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Мешок муки «vpn://» над формой: ключ — это мука, из которой замесят тесто.
private struct SackArt: View {
    private static let box = CGSize(width: 230, height: 118)
    private static let burlap = Color(hex: 0xE4D2B0)

    private func shape(_ d: String) -> SVGPath { SVGPath(d: d, box: Self.box) }
    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> String {
        "M \(x - r) \(y) A \(r) \(r) 0 1 1 \(x + r) \(y) A \(r) \(r) 0 1 1 \(x - r) \(y) Z"
    }

    var body: some View {
        let flour = [(52, 104, 11), (68, 100, 13), (84, 106, 9)].map { circle(CGFloat($0.0), CGFloat($0.1), CGFloat($0.2)) }
        let sack = "M 96 34 C 74 48 68 76 74 96 C 78 108 96 113 118 113 C 140 113 158 108 162 96 C 168 76 162 48 140 34 Z"
        let top = "M 100 34 C 96 24 98 16 104 12 C 110 18 114 20 118 20 C 122 20 126 18 132 12 C 138 16 140 24 136 34 Z"
        ZStack {
            ForEach(flour, id: \.self) { shape($0).stroke(Pk.sazha, lineWidth: 5) }
            ForEach(flour, id: \.self) { shape($0).fill(Pk.muka) }
            shape(sack).fill(Self.burlap)
            shape(sack).stroke(Pk.sazha, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            shape("M 86 60 L 150 58 M 82 80 L 156 78 M 84 98 L 154 97")
                .stroke(Color(hex: 0xC9B48E), style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
            shape(top).fill(Self.burlap)
            shape(top).stroke(Pk.sazha, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            shape("M 96 34 Q 118 41 140 34").stroke(Pk.sazha, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            shape(circle(110, 40, 4) + " " + circle(126, 40, 4)).stroke(Pk.sazha, lineWidth: 2)
            // Ложка: черенок и черпак
            shape("M 172 106 L 196 58").stroke(Pk.sazha, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            shape("M 172 106 L 196 58").stroke(Color(hex: 0xA8652F), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            Ellipse().fill(Color(hex: 0xA8652F))
                .overlay(Ellipse().strokeBorder(Pk.sazha, lineWidth: 2.5))
                .frame(width: 18, height: 26)
                .rotationEffect(.degrees(26))
                .position(x: 200, y: 48)
            Text(verbatim: "vpn://")
                .font(.pkMono(13))
                .foregroundStyle(Pk.sazha)
                .frame(width: 52, height: 28)
                .background(RoundedRectangle(cornerRadius: 4).fill(Pk.muka))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Pk.sazha, lineWidth: 2))
                .rotationEffect(.degrees(-4))
                .position(x: 118, y: 76)
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .accessibilityHidden(true)
    }
}
