// Renders the PomoTide app icon and builds Resources/AppIcon.icns.
//
// Usage: swift tools/make_icon.swift
// Needs only the Command Line Tools (CoreGraphics and iconutil).

import AppKit
import CoreGraphics

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a 1024 x 1024 canvas (macOS icon grid: 824 pt body, 100 pt margin).
func draw(in ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the body, as on other macOS icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x2563C9))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: teal to blue, top to bottom.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x5BD0E0), color(0x2F7FE0), color(0x2050C0)] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Gentle highlight in the upper half.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 900), endRadius: 560, options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 255
    let lineWidth: CGFloat = 58

    // Water inside the ring: two waves, the back one fainter.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - radius + lineWidth / 2 + 14, y: center.y - radius + lineWidth / 2 + 14,
                              width: 2 * (radius - lineWidth / 2 - 14), height: 2 * (radius - lineWidth / 2 - 14)))
    ctx.clip()
    for (level, amplitude, phase, alpha) in [(CGFloat(500), CGFloat(26), CGFloat(0.9), CGFloat(0.35)),
                                             (CGFloat(455), CGFloat(30), CGFloat(0), CGFloat(0.95))] {
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: 200, y: 0))
        for x in stride(from: CGFloat(200), through: 824, by: 4) {
            wave.addLine(to: CGPoint(x: x, y: level + amplitude * sin((x - 200) / 240 * .pi * 2 + phase)))
        }
        wave.addLine(to: CGPoint(x: 824, y: 0))
        wave.closeSubpath()
        ctx.addPath(wave)
        ctx.setFillColor(color(0xFFFFFF, alpha))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Ring track and progress arc, like the timer in the popover.
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xFFFFFF, 0.28))
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    ctx.strokePath()
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 1.5 * .pi, clockwise: true)
    ctx.strokePath()
}

func render(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(in: ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: iconset.appending(path: "icon_512x512@2x.png"))

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
