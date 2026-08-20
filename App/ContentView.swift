import SwiftUI

/// Единственный экран v1: статус + большая кнопка «Подключить».
/// Пока это скелет без действия — подключение к NETunnelProviderManager
/// появится вместе с TunnelManager (фаза 0.5 / M1).
struct ContentView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Отключено")
                .font(.title2)

            Button {
                // TODO(0.5): TunnelManager.start()
            } label: {
                Text("Подключить")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}
