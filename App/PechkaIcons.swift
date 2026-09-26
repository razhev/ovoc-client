import SwiftUI

// Иконки «Печки»: предметы из избы вместо системных замков, ключей и щитов.
// Сетка 24, штрих 2 pt, круглые концы; цвет — foregroundStyle.
// Контуры — те же SVG-пути, что на доске «Иконки» холста Design.

enum PkIcon: CaseIterable {
    case pechka, flame, kolobok, moon, smoke, sack, scroll, basket, kalach, chest, clipboard, back

    /// SVG-пути в сетке 24×24 (только абсолютные команды M L H V C Q A Z).
    var paths: [String] {
        switch self {
        case .pechka:
            return ["M3 20.5H21", "M5.5 9.5H18.5A1 1 0 0 1 19.5 10.5V20.5H4.5V10.5A1 1 0 0 1 5.5 9.5Z", "M3.5 9.5H20.5",
                    "M8.5 20.5V16.5A3.5 3.5 0 0 1 15.5 16.5V20.5", "M13.5 9.5V3.5H17V9.5", "M7 12.5H8.5M15.5 12.5H17"]
        case .flame:
            return ["M12 21C8 21 5.5 18.4 5.5 15C5.5 11.5 8 9.8 9 7C9.6 9 10.8 10 11.8 10.3C11.2 7.5 12.5 4.5 15 3C14.8 6.2 18.5 8.8 18.5 14.6C18.5 18.3 15.9 21 12 21Z",
                    "M12 21C10.3 21 9.4 19.8 9.4 18.4C9.4 16.6 11 15.8 11.6 14.2C13 15.2 14.6 16.4 14.6 18.4C14.6 19.8 13.7 21 12 21Z"]
        case .kolobok:
            return ["M3.5 12.5A8.5 8.5 0 1 1 20.5 12.5A8.5 8.5 0 1 1 3.5 12.5Z", "M8.8 14.5C10.4 16.6 13.6 16.6 15.2 14.5", "M9.3 10.3V11.2M14.7 10.3V11.2"]
        case .moon:
            return ["M19.5 14.5A7.8 7.8 0 1 1 10 4.5A6.2 6.2 0 0 0 19.5 14.5Z"]
        case .smoke:
            return ["M6.5 17C4.3 17 3 15.6 3 13.9C3 12.2 4.5 11 6.2 11.2C6.6 8.9 8.6 7.6 10.8 7.9C12 6.1 14.8 5.6 16.5 7.2C18.8 7 20.8 8.8 20.6 11C21.8 11.8 22.2 13.4 21.4 14.8C20.8 16.2 19.6 17 18 17Z",
                    "M7.5 20.5H10.5M13.5 20.5H17"]
        case .sack:
            return ["M8.5 7.5C5.2 9.8 4 13.5 4.8 16.8C5.6 20.2 8.6 21 12 21C15.4 21 18.4 20.2 19.2 16.8C20 13.5 18.8 9.8 15.5 7.5",
                    "M8.5 7.5H15.5", "M9.6 7.5C8.8 5.8 8.5 4.3 9.3 3.2C10.5 4.1 11.2 4.6 12 4.6C12.8 4.6 13.5 4.1 14.7 3.2C15.5 4.3 15.2 5.8 14.4 7.5",
                    "M9.5 14.5C10.8 13.4 13.2 13.4 14.5 14.5"]
        case .scroll:
            return ["M8 5H17.5C19 5 19 8 17.5 8H16.5V17.5C16.5 19 15.5 20 14 20H6.5C5 20 5 17 6.5 17H13.5",
                    "M8 5C6.5 5 6.5 8 8 8V17", "M10.5 10.5H13.5M10.5 13.5H13.5"]
        case .basket:
            return ["M3.5 11.5H20.5L18.8 19.3C18.6 20.3 17.8 21 16.8 21H7.2C6.2 21 5.4 20.3 5.2 19.3Z",
                    "M9 11.5L9.6 21M15 11.5L14.4 21M4.6 16H19.4", "M12 8.5V2.8M9.3 5.3L12 2.8L14.7 5.3"]
        case .kalach:
            return ["M19.5 12.5A7.5 7.5 0 1 1 16.9 6.8", "M17.3 2.8V7.2H21.7", "M9.5 9.5L10.5 10.5M13.5 13.5L14.5 14.5M9.5 14.5L10.5 13.5"]
        case .chest:
            return ["M5 9.5H19A1.5 1.5 0 0 1 20.5 11V19A1.5 1.5 0 0 1 19 20.5H5A1.5 1.5 0 0 1 3.5 19V11A1.5 1.5 0 0 1 5 9.5Z",
                    "M3.5 9.5C3.5 6 6 4.5 12 4.5C18 4.5 20.5 6 20.5 9.5", "M3.5 13H20.5", "M10.5 11.5H13.5V15.5H10.5Z"]
        case .clipboard:
            return ["M7.5 4.5H16.5A2 2 0 0 1 18.5 6.5V19A2 2 0 0 1 16.5 21H7.5A2 2 0 0 1 5.5 19V6.5A2 2 0 0 1 7.5 4.5Z",
                    "M10 2.5H14C14.6 2.5 15 2.9 15 3.5V4.5C15 5.1 14.6 5.5 14 5.5H10C9.4 5.5 9 5.1 9 4.5V3.5C9 2.9 9.4 2.5 10 2.5Z",
                    "M9 11H15M9 14.5H13"]
        case .back:
            return ["M14.5 5L7.5 12L14.5 19"]
        }
    }
}

struct PkIconView: View {
    let icon: PkIcon
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            ForEach(Array(icon.paths.enumerated()), id: \.offset) { _, d in
                SVGPath(d: d, box: CGSize(width: 24, height: 24))
                    .stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Фигура из строки SVG-пути, растянутая из box в свой прямоугольник.
/// Поддерживает абсолютные M L H V C Q A Z — ровно то, что есть в рисунках «Печки».
struct SVGPath: Shape {
    let d: String
    var box = CGSize(width: 24, height: 24)

    func path(in rect: CGRect) -> Path {
        let path = SVGPath.parse(d)
        let sx = rect.width / box.width, sy = rect.height / box.height
        return path.applying(CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: rect.minX, ty: rect.minY))
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens: [Substring] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(Substring(number)); number = "" } }
        for ch in d {
            if ch.isLetter {
                flush(); tokens.append(Substring(String(ch)))
            } else if ch == "-" {
                flush(); number = "-"
            } else if ch == "," || ch == " " || ch == "\n" {
                flush()
            } else if ch == "." && number.contains(".") {
                flush(); number = "."
            } else {
                number.append(ch)
            }
        }
        flush()

        var i = 0
        var command: Character = "M"
        var current = CGPoint.zero
        func num() -> CGFloat {
            defer { i += 1 }
            return CGFloat(Double(tokens[i]) ?? 0)
        }
        func hasNumber() -> Bool { i < tokens.count && !(tokens[i].first?.isLetter ?? false) }

        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                command = c
                i += 1
                if c == "Z" { path.closeSubpath(); continue }
            }
            guard hasNumber() else { continue }
            switch command {
            case "M":
                current = CGPoint(x: num(), y: num())
                path.move(to: current)
                command = "L"   // пары после M — это L
            case "L":
                current = CGPoint(x: num(), y: num())
                path.addLine(to: current)
            case "H":
                current.x = num()
                path.addLine(to: current)
            case "V":
                current.y = num()
                path.addLine(to: current)
            case "C":
                let c1 = CGPoint(x: num(), y: num()), c2 = CGPoint(x: num(), y: num())
                current = CGPoint(x: num(), y: num())
                path.addCurve(to: current, control1: c1, control2: c2)
            case "Q":
                let c1 = CGPoint(x: num(), y: num())
                current = CGPoint(x: num(), y: num())
                path.addQuadCurve(to: current, control: c1)
            case "A":
                let r = num()
                _ = num(); _ = num()                // ry и поворот: у нас только круговые дуги
                let large = num() != 0, sweep = num() != 0
                let end = CGPoint(x: num(), y: num())
                addArc(&path, from: current, to: end, radius: r, large: large, sweep: sweep)
                current = end
            default:
                i += 1
            }
        }
        return path
    }

    /// Круговая дуга SVG (конечные точки) → центр и углы.
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, radius: CGFloat, large: Bool, sweep: Bool) {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let chord = sqrt(dx * dx + dy * dy)
        guard chord > 0 else { return }
        let r = max(radius, chord / 2)
        let h = sqrt(max(r * r - chord * chord / 4, 0))
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        // Центр по одну из сторон хорды: выбор задают флаги large и sweep.
        let sign: CGFloat = large == sweep ? -1 : 1
        let center = CGPoint(x: mid.x - sign * h * dy / chord, y: mid.y + sign * h * dx / chord)
        let a0 = atan2(p0.y - center.y, p0.x - center.x)
        let a1 = atan2(p1.y - center.y, p1.x - center.x)
        // sweep = 1 — по возрастанию угла (по часовой на экране).
        path.addArc(center: center, radius: r, startAngle: .radians(Double(a0)), endAngle: .radians(Double(a1)), clockwise: !sweep)
    }
}
