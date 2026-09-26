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
                sourcePicker

                // Состояние App Group видно сразу: пустой лог и «лог писать
                // некуда» — разные ситуации, M1 проверяет именно это.
                Text(summary)
                    .font(.pkText(13, relativeTo: .footnote))
                    .foregroundStyle(healthy ? Pk.zola : Pk.klyukva)
                    .padding(.horizontal, 6)

                // Свиток: лог между двумя деревянными валиками.
                VStack(spacing: -2) {
                    ScrollRoll()
                    Group {
                        if text.isEmpty {
                            Text("Лог пуст")
                        } else {
                            // verbatim: содержимое лога — не ключ каталога.
                            Text(verbatim: text)
                        }
                    }
                    .font(.pkMono(11))
                    .foregroundStyle(Pk.sazha)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
                    .background(Pk.muka)
                    .overlay(alignment: .leading) { Rectangle().fill(Pk.sazha).frame(width: 2.5) }
                    .overlay(alignment: .trailing) { Rectangle().fill(Pk.sazha).frame(width: 2.5) }
                    .padding(.horizontal, 10)
                    ScrollRoll()
                }
            }
            .padding(16)
        }
        .background(Pk.smetana.ignoresSafeArea())
        .navigationTitle("Логи")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Логи")
                    .font(.pkDisplay(22, relativeTo: .headline))
                    .foregroundStyle(Pk.sazha)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { reload() } label: { PkIconView(icon: .kalach) }
                    .accessibilityLabel(Text("Обновить"))
                if !shareItems.isEmpty {
                    ShareLink(items: shareItems) {
                        PkIconView(icon: .basket)
                    }
                    .accessibilityLabel(Text("Поделиться логами"))
                }
            }
        }
        .tint(Pk.sazha)
        // Срабатывает при открытии экрана и при смене источника.
        .task(id: source) { reload() }
    }

    /// Переключатель «Туннель / Приложение»: выбранный — мёд с контуром.
    private var sourcePicker: some View {
        HStack(spacing: 4) {
            ForEach(Source.allCases) { item in
                let selected = item == source
                Button {
                    source = item
                } label: {
                    Text(item.title)
                        .font(.pkText(15, selected ? .semibold : .medium, relativeTo: .subheadline))
                        .foregroundStyle(selected ? Pk.sazha : Pk.zola)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selected {
                                Capsule().fill(Pk.med)
                                Capsule().strokeBorder(Pk.sazha, lineWidth: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Pk.muka))
        .overlay(Capsule().strokeBorder(Pk.sazha, lineWidth: 2))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: source)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Источник"))
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

/// Деревянный валик свитка.
private struct ScrollRoll: View {
    var body: some View {
        ZStack {
            Capsule().fill(Color(hex: 0xEFDDBB))
            Capsule().strokeBorder(Pk.sazha, lineWidth: 2.5)
            HStack {
                roll
                Spacer()
                roll
            }
            .padding(.horizontal, 2.5)
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    private var roll: some View {
        Ellipse().fill(Color(hex: 0xD9C29A))
            .overlay(Ellipse().strokeBorder(Pk.sazha, lineWidth: 2))
            .overlay(Circle().fill(Color(hex: 0x7E4A22)).frame(width: 4, height: 4))
            .frame(width: 11, height: 20)
    }
}
