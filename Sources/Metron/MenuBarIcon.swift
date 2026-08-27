import AppKit

/// Draws the menu bar glyph: a ring filled to the most-constrained window,
/// optionally followed by the percentage.
enum MenuBarIcon {

    static func image(percent: Double?, showPercent: Bool, color: NSColor) -> NSImage {
        let ringSize: CGFloat = 15
        let text: String? = {
            guard showPercent, let p = percent else { return nil }
            return "\(Int(p))%"
        }()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let textSize = text.map {
            ($0 as NSString).size(withAttributes: [.font: font])
        } ?? .zero
        let gap: CGFloat = text == nil ? 0 : 3
        let width = ringSize + gap + textSize.width
        let height: CGFloat = 16

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let inset: CGFloat = 1.5
        let rect = NSRect(x: inset, y: (height - ringSize) / 2 + inset * 0.5,
                          width: ringSize - inset * 2, height: ringSize - inset * 2)

        // Track
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = 2
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        track.stroke()

        // Filled arc
        if let p = percent, p > 0 {
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center,
                          radius: radius,
                          startAngle: 90,
                          endAngle: 90 - 360 * CGFloat(min(p, 100) / 100),
                          clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }

        if let text {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
            (text as NSString).draw(
                at: NSPoint(x: ringSize + gap, y: (height - textSize.height) / 2),
                withAttributes: attrs
            )
        }

        image.unlockFocus()
        // Not a template: the severity colour is the whole point of the glyph.
        image.isTemplate = false
        return image
    }

    static func nsColor(for percent: Double) -> NSColor {
        switch percent {
        case ..<70:  return NSColor(red: 0.373, green: 0.706, blue: 0.612, alpha: 1)
        case ..<90:  return NSColor(red: 0.902, green: 0.678, blue: 0.302, alpha: 1)
        default:     return NSColor(red: 0.886, green: 0.365, blue: 0.325, alpha: 1)
        }
    }
}
