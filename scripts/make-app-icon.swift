#!/usr/bin/env swift
// Иконка приложения — `make icon`. Рисует ОДНУ картинку 1024×1024 (для iOS 17+
// Xcode сам делает из неё все размеры) в App/Assets.xcassets/AppIcon.appiconset/AppIcon.png.
//
// Только системные фреймворки Mac (CoreGraphics, ImageIO) — никаких
// зависимостей, запускается как скрипт: `swift scripts/make-app-icon.swift [путь.png]`.
//
// Рисунок — вариант «Мёд» с доски «Иконка приложения» холста «Печка»:
// белёная русская печь на медовом фоне, из устья с огнём выглядывает колобок.
// Никаких щитов и замков. Координаты — те же, что в SVG на холсте (y вниз):
// контекст перевёрнут, чтобы их можно было переносить как есть.
// Углы не скругляем: iOS накладывает маску сама, а картинка для App Store обязана
// быть квадратной и без альфа-канала (поэтому битмап — noneSkipLast).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

// Цвета «Печки» — sRGB, те же, что в App/Pechka.swift.
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1,
    ])!
}
let ink = rgb(0x2A1F1B)        // сажа
let med = rgb(0xF2B33D)        // мёд — фон
let sun = rgb(0xF7C866)
let muka = rgb(0xFFF8EA)
let pobelka = rgb(0xF1ECE1)
let pobelkaShade = rgb(0xDDD4C5)
let izrazets = rgb(0x2A6B68)
let ryabina = rgb(0xB83E27)
let soot = rgb(0x2B211E)

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fputs("FAIL: не удалось создать битмап\n", stderr)
    exit(1)
}
// Система координат как в SVG: начало сверху слева, y вниз.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)

/// Путь из SVG-строки: абсолютные M L C Q Z.
func svg(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var tokens: [String] = []
    var number = ""
    for ch in d {
        if ch.isLetter {
            if !number.isEmpty { tokens.append(number); number = "" }
            tokens.append(String(ch))
        } else if ch == " " || ch == "," {
            if !number.isEmpty { tokens.append(number); number = "" }
        } else if ch == "-" {
            if !number.isEmpty { tokens.append(number) }
            number = "-"
        } else {
            number.append(ch)
        }
    }
    if !number.isEmpty { tokens.append(number) }
    var i = 0
    var command = "M"
    func n() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    while i < tokens.count {
        if tokens[i].first!.isLetter {
            command = tokens[i]; i += 1
            if command == "Z" { path.closeSubpath(); continue }
        }
        switch command {
        case "M": path.move(to: CGPoint(x: n(), y: n())); command = "L"
        case "L": path.addLine(to: CGPoint(x: n(), y: n()))
        case "C":
            let c1 = CGPoint(x: n(), y: n()), c2 = CGPoint(x: n(), y: n())
            path.addCurve(to: CGPoint(x: n(), y: n()), control1: c1, control2: c2)
        case "Q":
            let c = CGPoint(x: n(), y: n())
            path.addQuadCurve(to: CGPoint(x: n(), y: n()), control: c)
        default: fputs("FAIL: команда \(command) не поддерживается\n", stderr); exit(1)
        }
    }
    return path
}

/// Арка устья: стенки вниз от центра дуги (cx, cy) радиуса r до y = bottom.
func arch(cx: CGFloat, cy: CGFloat, r: CGFloat, bottom: CGFloat, closed: Bool) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: cx - r, y: bottom))
    path.addLine(to: CGPoint(x: cx - r, y: cy))
    // По возрастанию угла от π до 2π — через верх (y вниз).
    path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
    path.addLine(to: CGPoint(x: cx + r, y: bottom))
    if closed { path.closeSubpath() }
    return path
}

func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}
func stroke(_ path: CGPath, _ color: CGColor = ink, width: CGFloat = 18) {
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath()
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
}
func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, degrees: CGFloat = 0) -> CGPath {
    var t = CGAffineTransform(translationX: x, y: y).rotated(by: degrees * .pi / 180)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
}

// ── Фон и солнышко ──
fill(rect(0, 0, 1024, 1024), med)
fill(circle(190, 200, 70), sun)

// ── Дымок и труба ──
stroke(svg("M 632 150 C 598 112 664 84 628 40 C 608 16 640 -6 660 -20"), muka, width: 34)
fill(rect(556, 150, 152, 220), pobelka); stroke(rect(556, 150, 152, 220))
fill(rect(536, 176, 192, 46, r: 8), pobelka); stroke(rect(536, 176, 192, 46, r: 8))

// ── Печь ──
fill(rect(196, 392, 632, 660), pobelka)
fill(rect(196, 392, 54, 660), pobelkaShade)
stroke(rect(196, 392, 632, 660))
fill(rect(164, 344, 696, 62, r: 14), pobelka); stroke(rect(164, 344, 696, 62, r: 14))

// Расписная арка и устье
stroke(arch(cx: 512, cy: 640, r: 194, bottom: 880, closed: false), izrazets, width: 16)
let mouth = arch(cx: 512, cy: 648, r: 168, bottom: 880, closed: true)
fill(mouth, soot); stroke(mouth)

// Огонь
fill(svg("M 384 876 C 360 790 400 740 408 660 C 438 700 452 640 470 590 C 490 650 520 670 512 560 C 560 620 590 660 600 610 C 640 690 670 780 640 876 Z"), rgb(0xE0542B))
fill(svg("M 420 876 C 404 810 430 770 440 710 C 462 740 478 700 490 660 C 506 710 530 720 530 650 C 566 700 590 740 604 876 Z"), rgb(0xF28C28))

// ── Колобок ──
fill(circle(512, 760, 112), rgb(0xD98A2B))
fill(circle(498, 744, 96), rgb(0xF0B03A))
stroke(circle(512, 760, 112))
fill(ellipse(462, 690, 30, 16, degrees: -30), rgb(0xFFE08A))
fill(ellipse(474, 742, 15, 22), ink); fill(ellipse(550, 742, 15, 22), ink)
fill(circle(479, 733, 6), rgb(0xFFFFFF)); fill(circle(555, 733, 6), rgb(0xFFFFFF))
fill(circle(438, 786, 20), rgb(0xEC8E7C)); fill(circle(588, 786, 20), rgb(0xEC8E7C))
let smile = svg("M 470 782 Q 512 836 556 782 Z")
fill(smile, rgb(0x7A2E1E)); stroke(smile, width: 12)

// ── Шесток и роспись ──
fill(rect(164, 872, 696, 56, r: 10), pobelka); stroke(rect(164, 872, 696, 56, r: 10))
let tulip = svg("M 512 470 C 470 450 468 414 486 404 C 494 424 504 430 512 436 C 520 430 530 424 538 404 C 556 414 554 450 512 470 Z")
fill(tulip, ryabina); stroke(tulip, width: 10)
for leaf in ["M 496 462 C 440 480 390 466 366 444 C 410 436 452 442 496 462 Z",
             "M 528 462 C 584 480 634 466 658 444 C 614 436 572 442 528 462 Z"] {
    fill(svg(leaf), izrazets); stroke(svg(leaf), width: 9)
}

// ── PNG без альфа-канала ──
guard let image = ctx.makeImage() else {
    fputs("FAIL: не удалось получить изображение\n", stderr)
    exit(1)
}
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("FAIL: не удалось открыть \(outputPath) на запись\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("FAIL: не удалось записать PNG\n", stderr)
    exit(1)
}
print("PASS иконка: \(outputPath) (\(size)×\(size), без альфа-канала)")
