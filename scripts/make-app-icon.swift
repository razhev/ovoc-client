#!/usr/bin/env swift
// Иконка приложения — `make icon`. Рисует ОДНУ картинку 1024×1024 (для iOS 17+
// Xcode сам делает из неё все размеры) в App/Assets.xcassets/AppIcon.appiconset/AppIcon.png.
//
// Только системные фреймворки Mac (CoreGraphics, CoreText, ImageIO) — никаких
// зависимостей, запускается как скрипт: `swift scripts/make-app-icon.swift [путь.png]`.
//
// Дизайн намеренно сдержанный: тёмно-синий фон, контур щита акцентным цветом
// (тот же #3D9EF2, что в AccentColor.colorset) и буквы «OVoC» — без мелкого
// текста, который на иконке 60 pt нечитаем. Углы не скругляем: iOS накладывает
// маску сама, а картинка для App Store обязана быть квадратной и без альфа-канала
// (поэтому битмап — noneSkipLast, без прозрачности).

import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

// Цвета — sRGB. Акцент = AccentColor.colorset (#3D9EF2).
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}
let accent = rgb(0x3D9EF2)
let backgroundTop = rgb(0x16294A)
let backgroundBottom = rgb(0x0B1626)
let letters = rgb(0xFFFFFF)

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fputs("FAIL: не удалось создать битмап\n", stderr)
    exit(1)
}
let s = CGFloat(size)

// ── Фон: вертикальный градиент ──
let gradient = CGGradient(colorsSpace: colorSpace, colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// ── Щит (координаты y — снизу вверх, как в CoreGraphics) ──
let left: CGFloat = 232, right: CGFloat = 792, top: CGFloat = 800
let shoulder: CGFloat = 500     // где прямые бока переходят в дугу к острию
let tip: CGFloat = 176          // остриё внизу
let midX = s / 2
let shield = CGMutablePath()
shield.move(to: CGPoint(x: left, y: top))
shield.addLine(to: CGPoint(x: right, y: top))
shield.addLine(to: CGPoint(x: right, y: shoulder))
shield.addQuadCurve(to: CGPoint(x: midX, y: tip), control: CGPoint(x: right, y: 270))
shield.addQuadCurve(to: CGPoint(x: left, y: shoulder), control: CGPoint(x: left, y: 270))
shield.closeSubpath()

// Лёгкая заливка для глубины, затем контур.
ctx.addPath(shield)
ctx.setFillColor(rgb(0x3D9EF2, alpha: 0.14))
ctx.fillPath()

ctx.addPath(shield)
ctx.setStrokeColor(accent)
ctx.setLineWidth(40)
ctx.setLineJoin(.round)
ctx.strokePath()

// ── Буквы «OVoC» — по центру щита, шрифт системный (SF Rounded), жирный ──
let fontSize: CGFloat = 176
let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let font = baseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? baseFont
let text = NSAttributedString(string: "OVoC", attributes: [
    kCTFontAttributeName as NSAttributedString.Key: font,
    kCTForegroundColorAttributeName as NSAttributedString.Key: letters,
])
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
// Оптический центр щита чуть выше геометрического: остриё снизу «тянет» вес.
let centerY: CGFloat = (top + tip) / 2 + 40
ctx.textPosition = CGPoint(x: midX - bounds.midX, y: centerY - bounds.midY)
CTLineDraw(line, ctx)

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
