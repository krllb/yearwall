// Draws the app icon into Resources/AppIcon.icns.
//
//     swift Scripts/make-icon.swift
//
// The same picture as the wallpaper: a grid of days, the elapsed ones joined
// into bars, today in the Black theme's accent, the rest dimmed.
import AppKit

let columns = 7
let rows = 5
let today = 11

func drawIcon(size: CGFloat, into context: CGContext) {
    let unit = size / 1024
    // Big Sur grid: an 824pt body inset 100pt, continuous corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: unit, y: unit))
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit).cgPath

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 28 * unit,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [NSColor(white: 0.16, alpha: 1).cgColor, NSColor(white: 0.02, alpha: 1).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    let diameter = 56 * unit
    let columnGap = 28 * unit
    let rowGap = 44 * unit
    let width = CGFloat(columns) * diameter + CGFloat(columns - 1) * columnGap
    let height = CGFloat(rows) * diameter + CGFloat(rows - 1) * rowGap
    let origin = CGPoint(x: body.midX - width / 2, y: body.midY + height / 2)

    func center(_ index: Int) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(index % columns) * (diameter + columnGap) + diameter / 2,
            y: origin.y - CGFloat(index / columns) * (diameter + rowGap) - diameter / 2
        )
    }

    let elapsed = NSColor(white: 0.92, alpha: 1).cgColor
    let remaining = NSColor(white: 1, alpha: 0.22).cgColor
    let accent = NSColor(srgbRed: 1, green: 0x6B / 255, blue: 0x57 / 255, alpha: 1).cgColor

    context.setStrokeColor(elapsed)
    context.setLineWidth(diameter)
    context.setLineCap(.round)
    for row in 0 ..< rows {
        let first = row * columns
        let last = min(first + columns - 1, today)
        guard last > first else { continue }
        context.move(to: center(first))
        context.addLine(to: center(last))
        context.strokePath()
    }

    for index in 0 ..< rows * columns {
        let color = index == today ? accent : index < today ? elapsed : remaining
        let point = center(index)
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                       width: diameter, height: diameter))
    }
    context.restoreGState()
}

func png(pixels: Int) -> Data {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(size: CGFloat(pixels), into: context)
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("wrote \(output.path)")
