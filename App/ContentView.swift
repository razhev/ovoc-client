import SwiftUI
import NetworkExtension

/// Единственный экран v1: статус + большая кнопка «Подключить».
/// Пока нет импортёра (M4), первое нажатие создаёт профиль-пустышку —
/// ровно то, что проверяет M1.
struct ContentView: View {
    @StateObject private var tunnel = TunnelManager()
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(tunnel.status == .connected ? .green : .secondary)

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
                .disabled(busy || tunnel.status == .disconnecting)

                if let error = tunnel.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
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
            .task { await tunnel.load() }
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
                // M1: профиля ещё нет — создаём пустышку (системный диалог
                // «…хочет добавить конфигурацию VPN» появится здесь).
                if !tunnel.hasProfile {
                    try? await tunnel.applyDummyProfile()
                }
                tunnel.start()
            }
        }
    }
}
