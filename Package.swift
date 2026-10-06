// swift-tools-version: 5.9
import PackageDescription

// Проверки Swift-части расширения на Mac: системные настройки представлены
// настоящими типами NetworkExtension, их применение в ОС заменяется в тестах.
// В приложение код попадает напрямую из PacketTunnel через XcodeGen.
let package = Package(
    name: "TunnelRuntime",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TunnelRuntime", dependencies: ["SharedRuntime"], path: "PacketTunnel/Runtime"),
        .target(name: "SharedRuntime", path: "Shared", resources: [.process("Resources")]),
        .testTarget(name: "TunnelRuntimeTests", dependencies: ["TunnelRuntime"], path: "Tests/TunnelRuntimeTests"),
        .testTarget(name: "SharedRuntimeTests", dependencies: ["SharedRuntime"], path: "Tests/SharedRuntimeTests"),
    ]
)
