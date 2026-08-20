import SwiftUI

/// Просмотр лога расширения (tunnel.log из App Group) + «Поделиться».
/// Это основной канал диагностики: подключать отладчик к расширению нельзя
/// (Go-код Cloak под отладчиком деградирует), а так родственник может
/// прислать лог одним нажатием.
struct LogView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Лог пуст" : text)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle("Логи")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = SharedPaths.logFileURL {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Обновить") { reload() }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        guard let url = SharedPaths.logFileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            text = ""
            return
        }
        // Свежие строки — важнее; показываем хвост.
        text = String(content.suffix(30_000))
    }
}
