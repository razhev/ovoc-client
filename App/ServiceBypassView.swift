import SwiftUI

extension BypassService {
    var displayName: String {
        switch self {
        case .ozon: return "Ozon"
        case .wildberries: return "Wildberries"
        case .yandex: return String(localized: "Яндекс, включая Go")
        }
    }
}

struct ServiceBypassView: View {
    @ObservedObject var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<BypassService> = []
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Выбранные сервисы будут подключаться напрямую и видеть IP вашей обычной сети.")
                    Text("Исключения действуют по сетевым адресам. Другие сервисы на тех же адресах также могут идти без VPN.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(BypassService.allCases, id: \.self) { service in
                        Toggle(isOn: Binding(
                            get: { selection.contains(service) },
                            set: { enabled in
                                if enabled { selection.insert(service) }
                                else { selection.remove(service) }
                                saveError = nil
                            }
                        )) {
                            Text(verbatim: service.displayName)
                        }
                    }
                    Button("Включить все") { selection = Set(BypassService.allCases) }
                    Button("Выключить все") { selection = [] }
                } header: {
                    Text("Российские сервисы")
                } footer: {
                    if !tunnel.hasRealConfig {
                        Text("Сначала добавьте ключ VPN.")
                    } else if !tunnel.canEditServiceBypass {
                        Text("Для изменения исключений отключите VPN и дождитесь завершения текущей операции.")
                    }
                }
                .disabled(!tunnel.canEditServiceBypass)

                Section {
                    Text("Экспериментальная функция. Каталог ещё проверяется на устройствах; отдельные возможности сервисов могут не работать.")
                    Text("После сохранения подключите VPN обычной кнопкой. Для проверки откройте сервис заново.")
                }
                if let error = saveError ?? tunnel.serviceBypassError {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
                Section {
                    Button("Сохранить") {
                        Task {
                            do {
                                try await tunnel.saveServiceBypass(ServiceBypassPolicy(services: selection))
                                dismiss()
                            } catch { saveError = TunnelManager.explainBypass(error) }
                        }
                    }
                    .disabled(!tunnel.canEditServiceBypass ||
                              ServiceBypassPolicy(services: selection) == tunnel.serviceBypassPolicy)
                    if tunnel.profileOperationInProgress { ProgressView() }
                }
            }
            .tint(Pk.izrazets)
            .navigationTitle(Text("Без VPN"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }.disabled(tunnel.profileOperationInProgress)
                }
            }
            .interactiveDismissDisabled(tunnel.profileOperationInProgress)
            .task {
                await tunnel.reloadServiceBypassProfile()
                selection = tunnel.serviceBypassPolicy?.services ?? []
            }
            .onChange(of: tunnel.serviceBypassPolicy) { policy in selection = policy?.services ?? [] }
            .onChange(of: tunnel.status) { _ in
                if !tunnel.canEditServiceBypass { selection = tunnel.serviceBypassPolicy?.services ?? [] }
            }
        }
    }
}
