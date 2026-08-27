import AppKit

/// Draws a glance's menu bar glyph: a ring filled to its headline fraction,
/// optionally followed by a short reading.
///
/// A glance with no natural ceiling — throughput, a service that is simply up
/// or down — has no fraction, and gets its SF Symbol tinted by severity instead.
enum MenuBarIcon {

    static func image(headline: Headline?, symbol: String, showText: Bool) -> NSImage {
        let glyphSize: CGFloat = 15
        let height: CGFloat = 16
        let color = nsColor(for: headline?.severity ?? .idle)

        let text: String? = {
            guard showText, let t = headline?.text, !t.isEmpty else { return nil }
            return t
        }()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let textSize = text.map { ($0 as NSString).size(withAttributes: [.font: font]) } ?? .zero
        let gap: CGFloat = text == nil ? 0 : 3
        let width = glyphSize + gap + textSize.width

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        if let fraction = headline?.fraction {
            drawRing(fraction: fraction, color: color, glyphSize: glyphSize, height: height)
        } else {
            drawSymbol(symbol, color: color, glyphSize: glyphSize, height: height)
        }

        if let text {
            (text as NSString).draw(
                at: NSPoint(x: glyphSize + gap, y: (height - textSize.height) / 2),
                withAttributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
        }

        image.unlockFocus()
        // Not a template: the severity colour is the whole point of the glyph.
        image.isTemplate = false
        return image
    }

    private static func drawRing(fraction: Double, color: NSColor,
                                 glyphSize: CGFloat, height: CGFloat) {
        let inset: CGFloat = 1.5
        let rect = NSRect(x: inset, y: (height - glyphSize) / 2 + inset * 0.5,
                          width: glyphSize - inset * 2, height: glyphSize - inset * 2)

        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = 2
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        track.stroke()

        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY),
                      radius: rect.width / 2,
                      startAngle: 90,
                      endAngle: 90 - 360 * CGFloat(min(fraction, 1)),
                      clockwise: true)
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    private static func drawSymbol(_ name: String, color: NSColor,
                                   glyphSize: CGFloat, height: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let s = symbol.size
        let rect = NSRect(x: (glyphSize - s.width) / 2,
                          y: (height - s.height) / 2,
                          width: s.width, height: s.height)
        color.set()
        symbol.isTemplate = true
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        // `draw` on a template image ignores the fill colour, so tint on top.
        rect.fill(using: .sourceAtop)
    }

    static func nsColor(for severity: Severity) -> NSColor {
        switch severity {
        case .idle: return NSColor.secondaryLabelColor
        case .ok:   return NSColor(red: 0.373, green: 0.706, blue: 0.612, alpha: 1)
        case .warn: return NSColor(red: 0.902, green: 0.678, blue: 0.302, alpha: 1)
        case .crit: return NSColor(red: 0.886, green: 0.365, blue: 0.325, alpha: 1)
        }
    }
}
