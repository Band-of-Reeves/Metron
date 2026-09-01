import Foundation

/// The five token classes that carry different prices, plus web searches.
///
/// Keeping the two cache-write TTLs apart is the whole reason the Ledger reads
/// transcripts rather than Claude Code's own stats roll-up: the roll-up fuses
/// them, and a 1-hour write costs 1.6x a 5-minute one. On this machine 70% of
/// cache writes are at the 1-hour rate, so fusing them understates the total by
/// about 18%.
struct TokenSplit: Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var webSearches = 0

    var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    static func + (a: TokenSplit, b: TokenSplit) -> TokenSplit {
        TokenSplit(input: a.input + b.input,
                   output: a.output + b.output,
                   cacheRead: a.cacheRead + b.cacheRead,
                   cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m,
                   cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h,
                   webSearches: a.webSearches + b.webSearches)
    }

    static func += (a: inout TokenSplit, b: TokenSplit) { a = a + b }
}

/// One day's tokens, per model.
struct LedgerDay: Equatable, Identifiable {
    let day: Date
    var byModel: [String: TokenSplit] = [:]

    var id: Date { day }
    var tokens: TokenSplit { byModel.values.reduce(TokenSplit(), +) }
    var cost: Double { byModel.reduce(0) { $0 + Pricing.cost(of: $1.value, model: $1.key) } }
}

/// A model's contribution over some window.
struct ModelCost: Identifiable, Equatable {
    let model: String
    let tokens: TokenSplit
    let cost: Double
    let confidence: Pricing.Confidence

    var id: String { model }
    var isLocal: Bool { confidence == .local }

    /// "claude-opus-5" -> "Opus 5", matching ModelBreakdown's naming.
    var shortName: String { ModelStyle.label(for: model) }

    static func == (a: ModelCost, b: ModelCost) -> Bool {
        a.model == b.model && a.tokens == b.tokens && a.cost == b.cost
    }
}

/// Everything the Ledger draws.
struct LedgerReading: Equatable {
    var days: [Date: LedgerDay] = [:]
    /// Lifetime totals from stats-cache.json, which outlives pruned transcripts.
    var lifetime: LifetimeStats?
    var output: OutputStats?
    var scannedAt: Date = .distantPast
    /// True when the figures come from transcripts (exact) rather than the
    /// stats roll-up (estimated). Shown in the footer; never hidden.
    var isExact = true

    var sortedDays: [LedgerDay] { days.values.sorted { $0.day < $1.day } }

    /// The window the CLI's own stats screen offers, mirrored here.
    enum Window: String, CaseIterable, Identifiable {
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case allTime = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .allTime: return nil
            }
        }
    }

    func days(in window: Window) -> [LedgerDay] {
        let all = sortedDays
        guard let n = window.days else { return all }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: -(n - 1), to: today) else { return all }
        return all.filter { $0.day >= cutoff }
    }

    func cost(in window: Window) -> Double {
        days(in: window).reduce(0) { $0 + $1.cost }
    }

    func models(in window: Window) -> [ModelCost] {
        var totals: [String: TokenSplit] = [:]
        for day in days(in: window) {
            for (m, t) in day.byModel { totals[m, default: TokenSplit()] += t }
        }
        return totals.filter { $0.value.total > 0 }.map { model, tokens in
            let (_, confidence) = Pricing.rate(for: model)
            return ModelCost(model: model, tokens: tokens,
                             cost: Pricing.cost(of: tokens, model: model),
                             confidence: confidence)
        }
        .sorted { $0.cost == $1.cost ? $0.tokens.total > $1.tokens.total : $0.cost > $1.cost }
    }

    /// What the subscription cost over the same window, and the multiple.
    ///
    /// The comparison is only honest against elapsed calendar time, not against
    /// active days: you pay for the month whether or not you open the laptop.
    static let subscriptionPerMonth = 200.0

    func subscriptionPaid(in window: Window) -> Double {
        let elapsed: Double
        if let n = window.days {
            elapsed = Double(n)
        } else {
            guard let first = sortedDays.first?.day else { return 0 }
            elapsed = max(1, Date().timeIntervalSince(first) / 86_400)
        }
        return Self.subscriptionPerMonth / 30.0 * elapsed
    }

    func multiple(in window: Window) -> Double? {
        let paid = subscriptionPaid(in: window)
        guard paid > 0 else { return nil }
        return cost(in: window) / paid
    }

    var peakDay: LedgerDay? { days.values.max { $0.cost < $1.cost } }
}

/// Lifetime counters from `~/.claude/stats-cache.json`. These survive
/// transcript pruning, so they are the one thing the roll-up does better.
struct LifetimeStats: Equatable {
    var totalSessions = 0
    var totalMessages = 0
    var firstSession: Date?
    var longestSessionSeconds: Double = 0
    var longestSessionMessages = 0
    /// Hour of day (0–23) with the most activity.
    var peakHour: Int?
}

/// Evidence of what the money produced, from git.
struct OutputStats: Equatable {
    var commits = 0
    var filesChanged = 0
    var insertions = 0
    var deletions = 0
    var repos = 0
    var activeDays = 0
    /// commits per day, keyed the same way as LedgerDay.
    var commitsByDay: [Date: Int] = [:]
    var byRepo: [RepoOutput] = []
}

struct RepoOutput: Identifiable, Equatable {
    let name: String
    var commits = 0
    var filesChanged = 0
    var insertions = 0
    var deletions = 0
    var lastCommit: Date?
    var id: String { name }
}
