import SwiftUI

/// What this subscription's work would have cost on the API, against what it
/// produced.
///
/// The numbers are large, so the panel's job is to be checkable rather than
/// impressive: every figure names its source, the pricing table carries its
/// fetch date, and anything estimated says so. `docs/ledger/reconcile.sh`
/// proves the source choice from the command line.
@MainActor
final class LedgerStore: GlanceStore {
    @Published private(set) var reading = LedgerReading()
    @Published var window: LedgerReading.Window = .thirtyDays {
        didSet {
            UserDefaults.standard.set(window.rawValue, forKey: "ledger.window")
            objectWillChange.send()
        }
    }

    private let tokens = TokenLedgerScanner.shared
    private let git = GitOutputScanner.shared

    init() {
        super.init(id: "ledger", name: "Ledger", symbol: "scalemass")
        if let saved = UserDefaults.standard.string(forKey: "ledger.window"),
           let w = LedgerReading.Window(rawValue: saved) {
            window = w
        }
    }

    // The underlying data moves slowly — transcripts are appended as you work,
    // but a dollar figure that twitches every minute would be noise.
    override class var defaultRefreshSeconds: Int { 900 }
    override class var refreshChoices: [Int] { [300, 900, 3600, 21600] }

    override func load() async {
        // Three independent sources; none should hold up the others.
        async let days = tokens.scan()
        async let output = git.scan()
        let lifetime = StatsCacheReader.read()

        var fresh = LedgerReading()
        fresh.days = await days
        fresh.output = await output
        fresh.lifetime = lifetime
        fresh.scannedAt = Date()
        fresh.isExact = !fresh.days.isEmpty

        guard !fresh.days.isEmpty else {
            // No transcripts at all — say so plainly rather than showing $0,
            // which would read as "you used nothing" instead of "nothing read".
            error = "No Claude Code transcripts under ~/.claude/projects yet."
            return
        }
        reading = fresh
        error = nil
    }

    override var headline: Headline? {
        guard !reading.days.isEmpty else {
            return Headline(fraction: nil, text: "—", severity: .idle)
        }
        // Cost has no ceiling, so there is no ring and no severity ramp. A
        // dollar figure is not a gauge and should not pretend to be one.
        return Headline(fraction: nil, text: compactMoney(reading.cost(in: window)), severity: .idle)
    }

    override var subtitle: String {
        guard !reading.days.isEmpty else { return "Nothing scanned yet" }
        let cost = reading.cost(in: window)
        guard let multiple = reading.multiple(in: window) else {
            return "\(money(cost)) / \(window.rawValue)"
        }
        return "\(money(cost)) / \(window.rawValue) · \(Int(multiple.rounded()))x subscription"
    }

    override func menuExtras() -> AnyView {
        AnyView(
            Picker("Window", selection: Binding(
                get: { self.window },
                set: { self.window = $0 })) {
                    ForEach(LedgerReading.Window.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
        )
    }

    override func content(_ size: GlanceSize) -> AnyView {
        switch size {
        case .full:   return AnyView(LedgerPanel(store: self))
        case .small:  return AnyView(LedgerSmall(store: self))
        case .medium: return AnyView(LedgerMedium(store: self))
        case .large:  return AnyView(LedgerLarge(store: self))
        }
    }
}

/// "$18,976" — the exact figure, for panels with room for it.
func money(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = v < 100 ? 2 : 0
    f.minimumFractionDigits = v < 100 ? 2 : 0
    return f.string(from: NSNumber(value: v)) ?? "$0"
}

/// "$19.0k" — for the menu bar and small widgets, where the exact dollar is
/// less useful than the order of magnitude.
func compactMoney(_ v: Double) -> String {
    if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "$%.1fk", v / 1_000) }
    if v >= 100 { return String(format: "$%.0f", v) }
    return String(format: "$%.2f", v)
}
