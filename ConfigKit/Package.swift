// swift-tools-version: 5.9
import PackageDescription

// ВСЯ логика разбора ключа vpn:// живёт здесь — в пакете, который собирается
// и на macOS: `swift test` гоняет юнит-тесты на Mac без телефона и подписи.
let package = Package(
    name: "ConfigKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ConfigKit", targets: ["ConfigKit"])
    ],
    targets: [
        // Системный zlib (libz). НЕ Compression.framework: его COMPRESSION_ZLIB —
        // это raw deflate БЕЗ zlib-заголовка, формат qCompress молча не совпадёт.
        .systemLibrary(name: "Czlib", path: "Sources/Czlib"),
        .target(name: "ConfigKit", dependencies: ["Czlib"]),
        .testTarget(name: "ConfigKitTests", dependencies: ["ConfigKit"]),
    ]
)
