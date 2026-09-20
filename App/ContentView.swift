import SwiftUI
import NetworkExtension

/// Единственный экран v1: статус + большая кнопка «Подключить».
/// Пока нет импортёра (M4), первое нажатие создаёт профиль-пустышку —
/// ровно то, что проверяет M1.
struct ContentView: View {
    @StateObject private var tunnel = TunnelManager()
    @State private var busy = false
    @State private var launchActionDone = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(tunnel.status == .connected ? .green : .secondary)

                Text(tunnel.status.localizedText)
                    .font(.title2)

                // Видно, что именно поднимет кнопка: боевой туннель или пустышку M1.
                if tunnel.status != .invalid {
                    Text(tunnel.hasRealConfig ? "Профиль: сервер" : "Профиль: тестовая пустышка")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: toggle) {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
                .disabled(busy || tunnel.status == .disconnecting)

                if let notice = tunnel.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let error = tunnel.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        // Текст с кодом ошибки удобно скопировать и прислать.
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .navigationTitle("PersonalVPN")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        LogView()
                    } label: {
                        Image(systemName: "doc.text")
                    }
                }
            }
            .task {
                await tunnel.load()
                #if DEBUG
                // Отладка с Mac без нажатий на телефоне: `make connect` и
                // `make disconnect` запускают приложение с этими аргументами.
                // .task срабатывает при каждом появлении экрана — действие
                // запуска выполняем один раз.
                guard !launchActionDone else { return }
                launchActionDone = true
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-autoconnect") {
                    await tunnel.connect()
                } else if arguments.contains("-autodisconnect") {
                    tunnel.stop()
                }
                #endif
            }
        }
    }

    private var iconName: String {
        switch tunnel.status {
        case .connected: return "lock.shield.fill"
        case .connecting, .reasserting: return "arrow.triangle.2.circlepath"
        default: return "lock.shield"
        }
    }

    private var buttonTitle: String {
        switch tunnel.status {
        case .connected, .connecting, .reasserting: return "Отключить"
        default: return "Подключить"
        }
    }

    private func toggle() {
        switch tunnel.status {
        case .connected, .connecting, .reasserting:
            tunnel.stop()
        default:
            busy = true
            Task {
                defer { busy = false }
                // M1: профиля ещё нет — connect() создаст пустышку (системный
                // диалог «…хочет добавить конфигурации VPN» появится здесь).
                // Любая ошибка окажется в tunnel.lastError под кнопкой.
                await tunnel.connect()
            }
        }
    }
}
