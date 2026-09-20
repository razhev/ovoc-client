import SwiftUI

/// Просмотр логов из App Group + «Поделиться»: tunnel.log пишет расширение,
/// app.log — приложение. Это основной канал диагностики: подключать отладчик
/// к расширению нельзя (Go-код Cloak под отладчиком деградирует), а так
/// родственник может прислать лог одним нажатием.
struct LogView: View {
    private enum Source: String, CaseIterable, Identifiable {
        case tunnel = "Туннель"
        case app = "Приложение"

        var id: Self { self }
        var url: URL? {
            switch self {
            case .tunnel: return SharedPaths.logFileURL
            case .app: return SharedPaths.appLogFileURL
            }
        }
    }

    @State private var source: Source = .tunnel
    @State private var text = ""
    @State private var summary = ""
    @State private var healthy = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Источник", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                // Состояние App Group видно сразу: пустой лог и «лог писать
                // некуда» — разные ситуации, M1 проверяет именно это.
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(healthy ? Color.secondary : Color.red)

                Text(text.isEmpty ? "Лог пуст" : text)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("Логи")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = source.url {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
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
        guard SharedPaths.containerURL != nil else {
            healthy = false
            summary = "App Group НЕДОСТУПНА: в подписи сборки нет application-groups — логи писать некуда."
            return
        }
        guard let url = source.url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            healthy = true
            summary = "App Group: OK · файла лога нет"
                + (source == .tunnel ? " — расширение ещё не запускалось" : "")
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
}
