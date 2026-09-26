import SwiftUI

@main
struct OVoCClientApp: App {
    init() {
        // Системная шапка (логи, импорт) — в цветах «Печки». Шрифт заголовков
        // задают сами экраны (ToolbarItem .principal): подмена шрифта через
        // UINavigationBarAppearance на iOS 26 прячет крупный заголовок.
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(Pk.smetana)
        bar.shadowColor = .clear
        let ink = UIColor(Pk.sazha)
        bar.titleTextAttributes = [.foregroundColor: ink]
        bar.largeTitleTextAttributes = [.foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().tintColor = ink
    }

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
