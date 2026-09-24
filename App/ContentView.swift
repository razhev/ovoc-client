import SwiftUI
import NetworkExtension

/// Главный экран: статус + большая кнопка «Подключить». Пока ключ не
/// импортирован, вместо неё — приглашение добавить ключ (экран ImportView).
struct ContentView: View {
    @StateObject private var tunnel = TunnelManager()
    @State private var busy = false
    @State private var launchActionDone = false
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(tunnel.status == .connected ? .green : .secondary)

                if needsKey {
                    // Первый запуск (или профиль удалён в Настройках): подключаться
                    // некуда — предлагаем импорт, а не кнопку «Подключить».
                    Text("Ключ не добавлен")
                        .font(.title2)

                    Text("Чтобы подключаться к серверу, добавьте ключ vpn://… — его выдаёт владелец сервера.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        showingImport = true
                    } label: {
                        Text("Добавить ключ")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 40)
                } else {
                    Text(tunnel.status.localizedText)
                        .font(.title2)

                    Button(action: toggle) {
                        Text(buttonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 40)
                    .disabled(busy || !tunnel.isLoaded || tunnel.status == .disconnecting)
                }

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
            .navigationTitle(Bundle.main.displayName)
            .toolbar {
                // Смена ключа; пока ключа нет, вход в импорт — большая кнопка по центру.
                ToolbarItem(placement: .navigationBarLeading) {
                    if tunnel.hasRealConfig {
                        Button {
                            showingImport = true
                        } label: {
                            Image(systemName: "key")
                        }
                        .accessibilityLabel("Сменить ключ")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        LogView()
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Логи")
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportView(tunnel: tunnel)
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
                } else if arguments.contains("-dummyprofile") {
                    await tunnel.connectDummy()
                }
                #endif
            }
        }
    }

    /// Профили прочитаны, и боевого среди них нет. До конца загрузки — false,
    /// чтобы приглашение к импорту не мигало при каждом запуске.
    /// Поднятый туннель без боевого профиля — это диагностическая пустышка
    /// (`make dummy`): ей нужны обычный статус и кнопка «Отключить».
    private var needsKey: Bool {
        tunnel.isLoaded && !tunnel.hasRealConfig
            && (tunnel.status == .invalid || tunnel.status == .disconnected)
    }

    private var iconName: String {
        if needsKey { return "key" }
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
                // Любая ошибка окажется в tunnel.lastError под кнопкой.
                await tunnel.connect()
            }
        }
    }
}
