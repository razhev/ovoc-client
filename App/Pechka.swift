import SwiftUI

// «Печка» — мультяшная дизайн-система приложения: советский мультфильм 60-х,
// изба, печь и тесто вместо замков, ключей и щитов.
// Источник правды — холст Design «Печка — мультяшный OVoC Client»
// (страница «Дизайн-система»): цвета, шрифты, голос, компоненты, иконки, движение.
//
// Всё вырезано из бумаги: контур «сажей» 2–2,5 pt и сплошная тень вниз без
// размытия. Нажатие — деталь вдавливается на 3 pt и отпускается пружиной.

// MARK: - Цвета

enum Pk {
    /// Фон экранов и панели под сценой.
    static let smetana = Color(hex: 0xF6EBD4)
    /// Карточки, поля, кнопки второго плана, текст на рябине.
    static let muka = Color(hex: 0xFFF8EA)
    /// Текст, контуры и сплошные тени.
    static let sazha = Color(hex: 0x2A1F1B)
    /// Пояснения, подписи.
    static let zola = Color(hex: 0x66523F)
    /// Одна главная кнопка на экране.
    static let ryabina = Color(hex: 0xB83E27)
    /// Тень заголовков, «VPN включён», выбранный сегмент.
    static let med = Color(hex: 0xF2B33D)
    /// Ссылки, «Вставить», орнамент.
    static let izrazets = Color(hex: 0x2A6B68)
    /// Только текст и значок ошибки.
    static let klyukva = Color(hex: 0x9B2A1B)

    // Подложки плашек
    static let nochTint = Color(hex: 0xDDE2EE)
    static let medTint = Color(hex: 0xFBE3B0)
    static let mukaTint = Color(hex: 0xEADBC0)
    static let klyukvaTint = Color(hex: 0xF6D5CA)

    /// Стены избы — фон под сценой, пока она грузится.
    static let brevno = Color(hex: 0xCF9D66)
    /// Пунктиры-разделители.
    static let dash = Color(hex: 0xD4C2A2)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Шрифты
// Файлы — App/Fonts (Google Fonts, OFL), список — UIAppFonts в project.yml.
// relativeTo: размеры растут вместе с системным «Размером текста».

extension Font {
    /// Marmelad — заголовки, название приложения.
    static func pkDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Marmelad-Regular", size: size, relativeTo: style)
    }

    /// Rubik — всё, что читают.
    static func pkText(_ size: CGFloat, _ weight: PkWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style)
    }

    /// PT Mono — ключи, коды ошибок, логи.
    static func pkMono(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom("PTMono-Regular", size: size, relativeTo: style)
    }
}

enum PkWeight {
    case regular, medium, semibold

    var fontName: String {
        switch self {
        case .regular: return "Rubik-Regular"
        case .medium: return "Rubik-Medium"
        case .semibold: return "Rubik-SemiBold"
        }
    }
}

// MARK: - Текст

/// Заголовок экрана: Marmelad с медовой «печатной» тенью.
struct PkHeading: View {
    let text: Text
    var size: CGFloat = 40

    var body: some View {
        text
            .font(.pkDisplay(size))
            .foregroundStyle(Pk.sazha)
            .shadow(color: Pk.med, radius: 0, x: 2, y: 2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Кнопки

/// Большая кнопка: главная (рябина) или второго плана (мука).
/// Неактивная — пунктир без тени: «тесто ещё не подошло».
struct PkButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    var height: CGFloat = 64

    func makeBody(configuration: Configuration) -> some View {
        PkButtonBody(configuration: configuration, kind: kind, height: height)
    }
}

private struct PkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PkButtonStyle.Kind
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let fill = !isEnabled ? Pk.mukaTint : (kind == .primary ? Pk.ryabina : Pk.muka)
        let ink = !isEnabled ? Color(hex: 0x8A7766) : (kind == .primary ? Pk.muka : Pk.sazha)

        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.pkText(19, .semibold, relativeTo: .headline))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                ZStack {
                    if isEnabled {
                        Capsule().fill(Pk.sazha).offset(y: pressed ? 3 : 5)
                    }
                    Capsule().fill(fill)
                    if isEnabled {
                        Capsule().strokeBorder(Pk.sazha, lineWidth: 2.5)
                    } else {
                        Capsule().strokeBorder(Color(hex: 0xA8937A), style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))
                    }
                }
            }
            .offset(y: pressed ? 3 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .contentShape(Capsule())
    }
}

/// Малая кнопка 44 pt: «Выбрать файл…» и т. п.
struct PkSmallButtonStyle: ButtonStyle {
    var fill: Color = Pk.muka
    var ink: Color = Pk.sazha

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.pkText(16, .semibold, relativeTo: .callout))
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                ZStack {
                    Capsule().fill(Pk.sazha).offset(y: pressed ? 1 : 3)
                    Capsule().fill(fill)
                    Capsule().strokeBorder(Pk.sazha, lineWidth: 2)
                }
            }
            .offset(y: pressed ? 2 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
    }
}

/// Круглая кнопка-иконка 44 pt поверх сцены и в шапке.
struct PkRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PkRoundFace(pressed: configuration.isPressed) { configuration.label }
    }
}

/// Лицо круглой кнопки — отдельно, чтобы им же оформить NavigationLink и ShareLink.
struct PkRoundFace<Label: View>: View {
    var pressed = false
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .foregroundStyle(Pk.sazha)
            .frame(width: 44, height: 44)
            .background {
                ZStack {
                    Circle().fill(Pk.sazha).offset(y: pressed ? 1 : 3)
                    Circle().fill(Pk.muka)
                    Circle().strokeBorder(Pk.sazha, lineWidth: 2)
                }
            }
            .offset(y: pressed ? 2 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .contentShape(Circle())
    }
}

// MARK: - Плашки и карточки

/// Плашка статуса: всегда прямой текст, без шуток.
struct PkChip: View {
    let icon: PkIcon
    let text: Text
    var fill: Color = Pk.mukaTint
    var ink: Color = Pk.sazha

    var body: some View {
        HStack(spacing: 7) {
            PkIconView(icon: icon, size: 18)
            text.font(.pkText(14, .medium, relativeTo: .subheadline))
        }
        .foregroundStyle(ink)
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .padding(.vertical, 5)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(Pk.sazha, lineWidth: 2))
    }
}

/// Карточка: мука, контур, сплошная тень 4 pt.
struct PkCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Pk.sazha).offset(y: 4)
                    RoundedRectangle(cornerRadius: 18).fill(Pk.muka)
                    RoundedRectangle(cornerRadius: 18).strokeBorder(Pk.sazha, lineWidth: 2)
                }
            }
    }
}

/// Строка-карточка со значком в кружке: ошибка, уведомление.
struct PkMessageCard<Content: View>: View {
    let icon: PkIcon
    var badge: Color = Pk.medTint
    var badgeInk: Color = Pk.sazha
    @ViewBuilder let content: () -> Content

    var body: some View {
        PkCard {
            HStack(alignment: .top, spacing: 12) {
                PkIconView(icon: icon, size: 20)
                    .foregroundStyle(badgeInk)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(badge))
                    .overlay(Circle().strokeBorder(Pk.sazha, lineWidth: 2))
                VStack(alignment: .leading, spacing: 4) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Край панели под сценой: подзор с вышивкой

/// Панель с кружевным верхним краем (зубцы r13, шаг 26).
struct ScallopPanel: Shape {
    static let radius: CGFloat = 13
    static let depth: CGFloat = 14   // от верха фигуры до линии зубцов

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX - 6, y: rect.minY + Self.depth))
        Self.addScallops(to: &p, in: rect)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }

    static func addScallops(to p: inout Path, in rect: CGRect) {
        var x = rect.minX - 6
        let y = rect.minY + depth
        p.addLine(to: CGPoint(x: x, y: y))
        while x < rect.maxX + 6 {
            p.addArc(center: CGPoint(x: x + radius, y: y), radius: radius,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            x += radius * 2
        }
    }
}

/// Только контур зубцов — рисуется поверх панели.
struct ScallopLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX - 6, y: rect.minY + ScallopPanel.depth))
        ScallopPanel.addScallops(to: &p, in: rect)
        return p
    }
}

/// Верх панели: зубцы с рябиновыми «дырочками» и полоса вышивки (зигзаг + ромбы).
struct PanelEdge: View {
    var body: some View {
        ZStack(alignment: .top) {
            ScallopPanel().fill(Pk.smetana)
            ScallopLine().stroke(Pk.sazha, lineWidth: 2.5)
            Canvas { ctx, size in
                var x: CGFloat = 7
                while x < size.width + 13 {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: 8.2, width: 3.6, height: 3.6)), with: .color(Pk.ryabina))
                    x += 26
                }
                var zig = Path()
                var zx: CGFloat = -4
                zig.move(to: CGPoint(x: zx, y: 27))
                while zx < size.width + 4 {
                    zig.addLine(to: CGPoint(x: zx + 8, y: 22))
                    zig.addLine(to: CGPoint(x: zx + 16, y: 27))
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: zx + 8, y: 28))
                    diamond.addLine(to: CGPoint(x: zx + 11, y: 31))
                    diamond.addLine(to: CGPoint(x: zx + 8, y: 34))
                    diamond.addLine(to: CGPoint(x: zx + 5, y: 31))
                    diamond.closeSubpath()
                    ctx.fill(diamond, with: .color(Pk.izrazets))
                    zx += 16
                }
                ctx.stroke(zig, with: .color(Pk.ryabina), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
        .frame(height: 38)
        .accessibilityHidden(true)
    }
}
