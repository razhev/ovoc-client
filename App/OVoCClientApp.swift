import SwiftUI

@main
struct OVoCClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

extension Bundle {
    /// Имя приложения, как его показывает iOS: CFBundleDisplayName из project.yml
    /// (без него система берёт CFBundleName). Под этим именем iOS спрашивает
    /// «…хочет добавить конфигурации VPN» — поэтому им же называются профиль
    /// в Настройках → VPN и главный экран. Переименование — одна строка в project.yml.
    var displayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName")
            ?? object(forInfoDictionaryKey: "CFBundleName")) as? String ?? ""
    }
}
