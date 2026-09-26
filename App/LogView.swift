import SwiftUI

/// Просмотр логов из App Group + «Поделиться»: tunnel.log пишет расширение,
/// app.log — приложение. Это основной канал диагностики: подключать отладчик
/// к расширению нельзя (Go-код Cloak под отладчиком деградирует), а так
/// родственник может прислать лог одним нажатием.
///
/// «Поделиться» отдаёт СРАЗУ ВСЕ имеющиеся файлы (tunnel.log, app.log и
/// last_error.txt, если он есть), а не только открытую вкладку: причина
/// сбоя обычно видна лишь по двум логам вместе, а просить прислать второй
/// файл отдельно — лишний круг переписки.
struct LogView: View {
    private enum Source: CaseIterable, Identifiable {
        case tunnel
        case app

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .tunnel: return "Туннель"
            case .app: return "Приложение"
            }
        }

        var url: URL? {
            switch self {
            case .tunnel: return SharedPaths.logFileURL
            case .app: return SharedPaths.appLogFileURL
            }
        }
    }

    @State private var source: Source = .tunnel
    @State private var text = ""
    @State private var summary: LocalizedStringKey = ""
    @State private var healthy = true
    /// Файлы для «Поделиться» — только существующие; пересчитываются при каждом обновлении.
    @State private var shareItems: [URL] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Источник", selection: $source) {
                    ForEach(Source.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                // Состояние App Group видно сразу: пустой лог и «лог писать
                // некуда» — разные ситуации, M1 проверяет именно это.
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(healthy ? Color.secondary : Color.red)

                Group {
                    if text.isEmpty {
                        Text("Лог пуст")
                    } else {
                        // verbatim: содержимое лога — не ключ каталога.
                        Text(verbatim: text)
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("Логи")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !shareItems.isEmpty {
                    ShareLink(items: shareItems) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Поделиться логами"))
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Обновить") { reload() }
            }
        }
        // Срабатывает при открытии экрана и при смене источника.
        .task(id: source) { reload() }
    }

    private func reload() {
        text = ""
        shareItems = Self.existingLogFiles()
        guard SharedPaths.containerURL != nil else {
            healthy = false
            summary = "App Group НЕДОСТУПНА: в подписи сборки нет application-groups — логи писать некуда."
            return
        }
        guard let url = source.url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            healthy = true
            summary = source == .tunnel
                ? "App Group: OK · файла лога нет — расширение ещё не запускалось"
                : "App Group: OK · файла лога нет"
            return
        }

        let size = (attributes[.size] as? Int) ?? 0
        let modified = (attributes[.modificationDate] as? Date)
            .map { $0.formatted(date: .omitted, time: .standard) } ?? "?"
        healthy = true
        summary = "App Group: OK · \(max(size / 1024, 1)) КБ · изменён в \(modified)"

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        // Свежие строки — важнее; показываем хвост.
        text = String(content.suffix(30_000))
    }

    /// tunnel.log, app.log, last_error.txt — те, что реально лежат в App Group.
    private static func existingLogFiles() -> [URL] {
        [SharedPaths.logFileURL, SharedPaths.appLogFileURL, SharedPaths.lastErrorURL]
            .compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
