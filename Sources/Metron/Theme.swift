import SwiftUI

enum Theme {
    // Anthropic-adjacent warm accent, plus a severity ramp for the gauges.
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757
    static let ok     = Color(red: 0.373, green: 0.706, blue: 0.612)   // #5FB49C
    static let warn   = Color(red: 0.902, green: 0.678, blue: 0.302)   // #E6AD4D
    static let crit   = Color(red: 0.886, green: 0.365, blue: 0.325)   // #E25D53

    /// Gauge colour by how close the window is to its ceiling.
    static func severity(_ pct: Double) -> Color {
        switch pct {
        case ..<70: return ok
        case ..<90: return warn
        default:    return crit
        }
    }

    static let track = Color.primary.opacity(0.10)
    static let hairline = Color.primary.opacity(0.08)
    static let subtle = Color.secondary.opacity(0.85)

    /// Heatmap ramp: empty cell through to the busiest day.
    static func heat(_ t: Double) -> Color {
        if t <= 0 { return Color.primary.opacity(0.06) }
        // Perceptual-ish ease so light days stay visible.
        let e = pow(min(max(t, 0), 1), 0.55)
        return accent.opacity(0.18 + 0.82 * e)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// Formats a duration as "3h 12m" / "2d 4h" / "6m".
func compactDuration(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
    if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
    if m > 0 { return "\(m)m" }
    return "under a minute"
}

func compactTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...:     return String(format: "%.0fk", Double(n) / 1_000)
    default:           return "\(n)"
    }
}
