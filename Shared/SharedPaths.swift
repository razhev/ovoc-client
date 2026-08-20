import Foundation

/// Пути к общим файлам приложения и расширения.
///
/// App Group — общий контейнер двух процессов (приложение ↔ расширение).
/// Расширение живёт отдельным процессом и иначе не может передать
/// приложению ни логи, ни текст последней ошибки.
enum SharedPaths {
    static let appGroupID = "group.com.razhev.personalvpn"

    /// nil возможен только при неправильных entitlements —
    /// это ошибка конфигурации сборки, а не рантайм-ситуация.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Кольцевой лог расширения (пишет RingLogger, читает LogView).
    static var logFileURL: URL? { containerURL?.appendingPathComponent("tunnel.log") }

    /// Последняя фатальная ошибка туннеля — приложение показывает её под кнопкой.
    static var lastErrorURL: URL? { containerURL?.appendingPathComponent("last_error.txt") }

    /// Импортированный конфиг (ImportedConfig в JSON).
    static var configURL: URL? { containerURL?.appendingPathComponent("config.json") }
}
