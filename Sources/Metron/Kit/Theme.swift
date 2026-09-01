import SwiftUI

enum Theme {
    // Anthropic-adjacent warm accent, plus a severity ramp for the gauges.
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757
    static let ok     = Color(red: 0.373, green: 0.706, blue: 0.612)   // #5FB49C
    static let warn   = Color(red: 0.902, green: 0.678, blue: 0.302)   // #E6AD4D
    static let crit   = Color(red: 0.886, green: 0.365, blue: 0.325)   // #E25D53
    static let idle   = Color.secondary

    /// Cool counterpart to `accent`, for the second series in a two-line chart
    /// (network down vs up, prefill vs generation).
    static let cool   = Color(red: 0.431, green: 0.596, blue: 0.855)   // #6E98DA

    static func color(_ s: Severity) -> Color {
        switch s {
        case .idle: return idle
        case .ok:   return ok
        case .warn: return warn
        case .crit: return crit
        }
    }

    /// Gauge colour by how close a window is to its ceiling (percent, 0...100).
    static func severity(_ pct: Double) -> Color {
        color(Severity.forFraction(pct / 100))
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

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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
    // The Ledger counts cache reads, which run to billions — "15003.8M" is a
    // number nobody can read at a glance.
    case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1_000_000_000)
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...:     return String(format: "%.0fk", Double(n) / 1_000)
    default:           return "\(n)"
    }
}

/// Bytes as "1.4 GB" / "812 MB". Decimal units, the way macOS reports storage.
func compactBytes(_ bytes: Double, unit: String = "B") -> String {
    let n = abs(bytes)
    switch n {
    case 1e12...: return String(format: "%.2f T%@", bytes / 1e12, unit)
    case 1e9...:  return String(format: "%.2f G%@", bytes / 1e9, unit)
    case 1e6...:  return String(format: "%.1f M%@", bytes / 1e6, unit)
    case 1e3...:  return String(format: "%.0f k%@", bytes / 1e3, unit)
    default:      return String(format: "%.0f %@", bytes, unit)
    }
}

/// Bytes in binary units, which is how macOS reports memory: a 128 GiB
/// machine says "128 GB", not the 137.44 GB its decimal size would give.
func compactRAM(_ bytes: Double) -> String {
    let n = abs(bytes)
    let gib = 1024.0 * 1024 * 1024, mib = 1024.0 * 1024
    switch n {
    case gib...: return String(format: "%.2f GB", bytes / gib)
    case mib...: return String(format: "%.0f MB", bytes / mib)
    case 1024...: return String(format: "%.0f KB", bytes / 1024)
    default:     return String(format: "%.0f B", bytes)
    }
}

/// Throughput, kept short enough for the menu bar: "12.4M/s".
func compactRate(_ bytesPerSecond: Double) -> String {
    let n = bytesPerSecond
    switch n {
    case 1e9...: return String(format: "%.1fG/s", n / 1e9)
    case 1e6...: return String(format: "%.1fM/s", n / 1e6)
    case 1e3...: return String(format: "%.0fk/s", n / 1e3)
    default:     return "idle"
    }
}
