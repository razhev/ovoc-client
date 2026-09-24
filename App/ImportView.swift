import SwiftUI
import UniformTypeIdentifiers

/// Экран импорта ключа vpn://: вставка из буфера или файл из «Файлов».
/// Всю работу делает `TunnelManager.importKey` — тот же путь, что у DEBUG-моста.
///
/// Ключ — это приватный ключ и сертификаты: экран его не логирует, не хранит
/// дольше импорта и очищает поле при успехе и при закрытии.
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
            Form {
                Section {
                    // PasteButton, а не чтение UIPasteboard: системная кнопка не
                    // вызывает запрос «Разрешить вставку из …?».
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.first ?? ""
                        error = nil
                    }
                    .disabled(importing)

                    Button {
                        pickingFile = true
                    } label: {
                        Label("Выбрать файл с ключом…", systemImage: "folder")
                    }
                    .disabled(importing)

                    TextEditor(text: $text)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(height: 110)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .disabled(importing)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("vpn://…")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Ключ")
                } footer: {
                    Text("Ключ выдаёт владелец сервера. В AmneziaVPN: «Поделиться» → протокол "
                       + "OpenVPN over Cloak → формат «Для приложения AmneziaVPN» → «Копировать». "
                       + "Можно вставить сообщение целиком — ключ найдётся сам.")
                }

                Section {
                    Button(action: importFromField) {
                        HStack {
                            Text(importing ? "Импортирую…" : "Импортировать")
                            if importing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(importing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if tunnel.status == .connected || tunnel.status == .connecting || tunnel.status == .reasserting {
                            Text("VPN сейчас включён — на время смены ключа он будет отключён.")
                        }
                        if !tunnel.hasRealConfig {
                            Text("Дальше iOS спросит: «\(Bundle.main.displayName) хочет добавить конфигурации VPN». "
                               + "Нажмите «Разрешить» и введите код-пароль — без этого разрешения "
                               + "приложение не может включать VPN. Спрашивают один раз.")
                        }
                    }
                }
            }
            .navigationTitle(tunnel.hasRealConfig ? "Сменить ключ" : "Добавить ключ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
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
            error = "Файл слишком большой для ключа. Выберите файл, в котором лежит строка vpn://…"
            return
        }
        guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) else {
            error = "Не удалось прочитать файл как текст. В файле должен лежать ключ vpn://…"
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
