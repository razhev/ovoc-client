import SwiftUI
import NetworkExtension

/// Главный экран: сцена с печью сверху, под ней — плашка статуса, заголовок
/// и одна большая кнопка. Пока ключ не импортирован, вместо «Подключить» —
/// «Добавить ключ» (экран ImportView).
///
/// Голос «Печки»: шутка — только в заголовке («Испеклось!»), суть — в плашке
/// и пояснении («VPN включён»), кнопка — прямым глаголом.
///
/// Все видимые строки — через `Localizable.xcstrings` (русский — базовый,
/// английский — второй): литералы в `Text(...)` SwiftUI берёт как ключи
/// каталога сами, строки из `TunnelManager` приходят уже локализованными.
struct ContentView: View {
    @StateObject private var tunnel = TunnelManager()
    @State private var busy = false
    @State private var launchActionDone = false
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            StoveScreen(
                stage: stage,
                showKeyButton: tunnel.hasRealConfig,
                systemHint: tunnel.status.localizedHint,
                errorText: tunnel.lastError,
                notice: tunnel.notice,
                actionEnabled: !busy && tunnel.isLoaded,
                onImport: { showingImport = true },
                onToggle: toggle
            )
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingImport) {
                ImportView(tunnel: tunnel)
            }
            .onChange(of: tunnel.status) { status in
                // «ПЫХ!»: удар на вспышке и мягкий — когда колобок садится на окно.
                guard status == .connected else { return }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
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

    // MARK: - Состояние экрана

    private var stage: StoveStage {
        // Профили прочитаны, и боевого среди них нет. До конца загрузки —
        // «Отключено» с неактивной кнопкой, чтобы приглашение к импорту не мигало.
        // Поднятый туннель без боевого профиля — диагностическая пустышка
        // (`make dummy`): ей нужны обычный статус и кнопка «Отключить».
        if tunnel.isLoaded && !tunnel.hasRealConfig
            && (tunnel.status == .invalid || tunnel.status == .disconnected) {
            return .noKey
        }
        switch tunnel.status {
        case .invalid: return tunnel.isLoaded ? .lostProfile : .off
        case .connecting: return .connecting
        case .connected: return .on
        case .reasserting: return .reconnecting
        case .disconnecting: return .stopping
        default: return tunnel.lastError == nil ? .off : .failed
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
                // Любая ошибка окажется в tunnel.lastError — карточкой «Тесто порвалось».
                await tunnel.connect()
            }
        }
    }
}

/// Вёрстка главного экрана без логики туннеля: сцена, шапка, панель с кнопкой.
/// Отдельно от ContentView, чтобы любое состояние можно было показать как есть
/// (превью, стенд для симулятора — у самого приложения симулятора нет).
struct StoveScreen: View {
    let stage: StoveStage
    let showKeyButton: Bool
    let systemHint: String?
    let errorText: String?
    let notice: String?
    let actionEnabled: Bool
    let onImport: () -> Void
    let onToggle: () -> Void

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            // Сцена рисуется 390×470; на коротких экранах её верх (стена,
            // труба) обрезается, чтобы панели хватило места.
            let sceneHeight = min(geo.size.width * 470 / 390, (geo.size.height + top) * 0.56)

            ZStack(alignment: .top) {
                Pk.smetana

                SceneView(phase: stage.scene)
                    .frame(height: sceneHeight)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Color.clear.frame(height: sceneHeight - 32)
                    panel
                        .padding(.bottom, geo.safeAreaInsets.bottom)
                }

                navBar.padding(.top, top + 4)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Шапка поверх сцены

    private var navBar: some View {
        HStack {
            // Смена ключа; пока ключа нет, вход в импорт — большая кнопка внизу.
            if showKeyButton {
                Button(action: onImport) {
                    PkIconView(icon: .sack)
                }
                .buttonStyle(PkRoundButtonStyle())
                .accessibilityLabel(Text("Сменить ключ"))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            Text(verbatim: Bundle.main.displayName)
                .font(.pkDisplay(17, relativeTo: .headline))
                .foregroundStyle(Pk.sazha)
                .padding(.horizontal, 15)
                .padding(.vertical, 5)
                .background {
                    ZStack {
                        Capsule().fill(Pk.sazha).offset(y: 3)
                        Capsule().fill(Pk.muka)
                        Capsule().strokeBorder(Pk.sazha, lineWidth: 2)
                    }
                }
                .accessibilityAddTraits(.isHeader)

            Spacer()

            NavigationLink {
                LogView()
            } label: {
                PkRoundFace { PkIconView(icon: .scroll) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Логи"))
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Панель под сценой

    private var panel: some View {
        VStack(spacing: 0) {
            PanelEdge()
            VStack(alignment: .leading, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PkChip(icon: stage.chipIcon, text: stage.chip, fill: stage.chipFill, ink: stage.chipInk)
                        PkHeading(text: stage.title)
                        if let hint = hint {
                            hint
                                .font(.pkText(16))
                                .foregroundStyle(Pk.zola)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if stage == .failed, let error = errorText {
                            PkMessageCard(icon: .smoke, badge: Pk.klyukvaTint, badgeInk: Pk.klyukva) {
                                // Подсказка + сырой код в квадратных скобках (см. TunnelManager.explain).
                                // Текст с кодом ошибки удобно скопировать и прислать.
                                Text(verbatim: error)
                                    .font(.pkText(15))
                                    .foregroundStyle(Pk.sazha)
                                    .textSelection(.enabled)
                            }
                        }
                        if let notice {
                            PkMessageCard(icon: .sack) {
                                Text(verbatim: notice)
                                    .font(.pkText(15, .medium))
                                    .foregroundStyle(Pk.sazha)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                }

                actionButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
            .background(Pk.smetana)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch stage {
        case .noKey, .lostProfile:
            Button(action: onImport) {
                Label { Text("Добавить ключ") } icon: { PkIconView(icon: .sack) }
            }
            .buttonStyle(PkButtonStyle(kind: .primary))
        case .off, .failed:
            Button(action: onToggle) {
                Label { Text("Подключить") } icon: { PkIconView(icon: .flame) }
            }
            .buttonStyle(PkButtonStyle(kind: .primary))
            .disabled(!actionEnabled)
        case .connecting:
            Button(action: onToggle) {
                Label { Text("Отменить") } icon: { PkIconView(icon: .moon) }
            }
            .buttonStyle(PkButtonStyle(kind: .secondary))
        case .on, .reconnecting, .stopping:
            Button(action: onToggle) {
                Label { Text("Отключить") } icon: { PkIconView(icon: .moon) }
            }
            .buttonStyle(PkButtonStyle(kind: .secondary))
            .disabled(stage == .stopping)
        }
    }

    /// Пояснение под заголовком: у промежуточных состояний — из TunnelManager.
    private var hint: Text? {
        if let systemHint, stage != .noKey {
            return Text(verbatim: systemHint)
        }
        switch stage {
        case .noKey: return Text("Чтобы подключаться к серверу, добавьте ключ vpn://… — его выдаёт владелец сервера.")
        case .off: return Text("Нажмите «Подключить» — Вовка растопит печь.")
        case .connecting: return Text("Обычно это занимает несколько секунд.")
        case .on: return Text("Трафик идёт через сервер.")
        default: return nil
        }
    }

}

/// Что показывает главный экран. Тексты — по доске «Голос» холста «Печка».
enum StoveStage {
    case noKey, lostProfile, off, connecting, on, reconnecting, stopping, failed

    var scene: StovePhase {
        switch self {
        case .noKey, .lostProfile: return .nokey
        case .off, .stopping: return .off
        case .connecting, .reconnecting: return .connecting
        case .on: return .on
        case .failed: return .error
        }
    }

    var title: Text {
        switch self {
        case .noKey: return Text("Ушат пустой")
        case .lostProfile: return Text("Рецепт потерялся")
        case .off: return Text("Печь остыла")
        case .connecting: return Text("Тянем-потянем…")
        case .on: return Text("Испеклось!")
        case .reconnecting: return Text("Подкидываем дров…")
        case .stopping: return Text("Гасим печь…")
        case .failed: return Text("Тесто порвалось")
        }
    }

    var chip: Text {
        switch self {
        case .noKey: return Text("Нет ключа")
        case .lostProfile: return Text("Нет профиля VPN")
        case .off: return Text("VPN выключен")
        case .connecting: return Text("Подключаемся…")
        case .on: return Text("VPN включён")
        case .reconnecting: return Text("Переподключаемся…")
        case .stopping: return Text("Отключаемся…")
        case .failed: return Text("Не подключилось")
        }
    }

    var chipIcon: PkIcon {
        switch self {
        case .noKey, .lostProfile: return .sack
        case .off, .stopping: return .moon
        case .connecting, .reconnecting: return .flame
        case .on: return .kolobok
        case .failed: return .smoke
        }
    }

    var chipFill: Color {
        switch self {
        case .noKey, .lostProfile: return Pk.mukaTint
        case .off, .stopping: return Pk.nochTint
        case .connecting, .reconnecting: return Pk.medTint
        case .on: return Pk.med
        case .failed: return Pk.klyukvaTint
        }
    }

    var chipInk: Color { self == .failed ? Pk.klyukva : Pk.sazha }
}
