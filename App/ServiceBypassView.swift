import SwiftUI

extension BypassService {
    var displayName: String {
        switch self {
        case .ozon: return "Ozon"
        case .wildberries: return "Wildberries"
        case .yandex: return String(localized: "Яндекс, включая Go")
        case .max: return "MAX"
        case .cdek: return String(localized: "СДЭК")
        case .gosuslugi: return String(localized: "Госуслуги")
        case .mosru: return "mos.ru"
        case .mosenergosbyt: return String(localized: "Мосэнергосбыт")
        }
    }
}

struct ServiceBypassView: View {
    @ObservedObject var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preferences = ServiceBypassSelectionModel()
    @State private var isReady = false
    @State private var showsServices = false

    private var canEdit: Bool {
        isReady && !preferences.isSaving && tunnel.canEditServiceBypass
    }

    private func select(_ services: Set<BypassService>) {
        guard canEdit else { return }
        preferences.updateSelection(services, save: tunnel.saveServiceBypass,
                                    readSaved: { tunnel.serviceBypassPolicy })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Исключить все", isOn: Binding(
                        get: { preferences.selection == Set(BypassService.allCases) },
                        set: { select($0 ? Set(BypassService.allCases) : []) }
                    ))
                    .disabled(!canEdit)

                    DisclosureGroup(isExpanded: $showsServices) {
                        ForEach(BypassService.allCases, id: \.self) { service in
                            Toggle(isOn: Binding(
                                get: { preferences.selection.contains(service) },
                                set: { enabled in
                                    var selection = preferences.selection
                                    if enabled { selection.insert(service) }
                                    else { selection.remove(service) }
                                    select(selection)
                                }
                            )) {
                                Text(verbatim: service.displayName)
                            }
                            .disabled(!canEdit)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Выбрать сервисы")
                            Text("Выбрано: \(preferences.selection.count) из \(BypassService.allCases.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Российские сервисы")
                } footer: {
                    if !isReady || preferences.isSaving || tunnel.profileOperationInProgress {
                        // Progress is shown separately, without an instruction
                        // to disconnect a VPN that is already disconnected.
                    } else if !tunnel.hasRealConfig {
                        Text("Сначала добавьте ключ VPN.")
                    } else if !tunnel.canEditServiceBypass {
                        Text("Для изменения исключений отключите VPN и дождитесь завершения текущей операции.")
                    } else {
                        Text("«Исключить все» включает все сервисы из списка. Выбранные сервисы работают напрямую, с IP вашей сети. Выбор сохраняется автоматически.")
                    }
                }

                if preferences.isSaving {
                    ProgressView("Сохранение…")
                } else if !isReady || tunnel.profileOperationInProgress {
                    ProgressView()
                }
                if let error = preferences.saveError.map(TunnelManager.explainBypass) ?? tunnel.serviceBypassError {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
                Section {
                    DisclosureGroup("Подробнее") {
                        Text("Исключения действуют по сетевым адресам. Другие сервисы на тех же адресах также могут идти без VPN.")
                        Text("Экспериментальная функция. Каталог ещё проверяется на устройствах; отдельные возможности сервисов могут не работать.")
                    }
                }
            }
            .tint(Pk.izrazets)
            .navigationTitle(Text("Без VPN"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .disabled(preferences.isSaving || tunnel.profileOperationInProgress)
                }
            }
            .interactiveDismissDisabled(preferences.isSaving || tunnel.profileOperationInProgress)
            .task {
                isReady = false
                await tunnel.reloadServiceBypassProfile()
                preferences.synchronize(tunnel.serviceBypassPolicy)
                isReady = true
            }
            .onChange(of: tunnel.serviceBypassPolicy) { preferences.synchronize($0) }
        }
    }
}
