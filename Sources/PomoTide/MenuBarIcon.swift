import AppKit

/// The app icon's ring and wave as a menu bar template image (only alpha counts).
enum MenuBarIcon {
    static func image(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: rect, ctx: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PomoTide"
        return image
    }

    /// Drawn on a 16 pt grid and scaled to `rect`.
    private static func draw(in rect: CGRect, ctx: CGContext) {
        let s = rect.width / 16
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let line = 1.6 * s
        let r = 7 * s - line / 2
        ctx.setLineCap(.round)
        ctx.setLineWidth(line)

        // Faint track and a three-quarter arc from the top, as in the app icon.
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        ctx.strokePath()
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.addArc(center: center, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 1.5 * .pi, clockwise: true)
        ctx.strokePath()

        // Water inside the ring, crest left of center.
        let inner = r - line / 2 - 1.1 * s
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: 2 * inner, height: 2 * inner))
        ctx.clip()
        let level = center.y - 0.7 * s
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for x in stride(from: rect.minX, through: rect.maxX, by: 0.25 * s) {
            wave.addLine(to: CGPoint(x: x, y: level + 0.9 * s * sin((x - rect.minX) / (7 * s) * 2 * .pi + 2.289)))
        }
        wave.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        wave.closeSubpath()
        ctx.addPath(wave)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
