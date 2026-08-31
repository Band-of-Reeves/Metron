import Foundation

/// What a model's tokens would have cost on the Anthropic API.
///
/// Metron is used on a subscription, where `costUSD` in Claude Code's own
/// records is always zero. The Ledger's whole job is the counterfactual: what
/// the same work would have been billed at API rates. That makes the numbers
/// below load-bearing, so they carry their source and the date they were read.
enum Pricing {

    /// USD per million tokens. Cache prices are multipliers on `input` rather
    /// than separate figures, so a base-price change stays internally
    /// consistent — Anthropic prices caching that way too.
    struct Rate {
        let input: Double
        let output: Double

        static let cacheRead = 0.10    // 0.1x input
        static let cacheWrite5m = 1.25 // 1.25x input
        static let cacheWrite1h = 2.00 // 2x input
        /// USD per web search request.
        static let webSearch = 10.0 / 1000
    }

    /// Where these came from, shown in the panel footer. A number this large is
    /// only allowed on screen if it says what it was computed from.
    static let source = "platform.claude.com/docs/en/about-claude/pricing"
    static let fetched = "2026-08-31"

    private static let table: [String: Rate] = [
        "claude-fable-5":   Rate(input: 10, output: 50),
        "claude-opus-5":    Rate(input: 5,  output: 25),
        "claude-opus-4-8":  Rate(input: 5,  output: 25),
        "claude-opus-4-7":  Rate(input: 5,  output: 25),
        "claude-opus-4-6":  Rate(input: 5,  output: 25),
        "claude-sonnet-5":  Rate(input: 2,  output: 10),
        "claude-sonnet-4-6": Rate(input: 3, output: 15),
        "claude-haiku-4-5": Rate(input: 1,  output: 5),
    ]

    /// How confident the price for a model is.
    enum Confidence {
        case exact       // a published rate for this exact model
        case tier        // matched by tier from the name
        case assumed     // no match; priced at Opus rates and said so
        case local       // not an API model at all — runs on this machine
    }

    /// A model id that is not Anthropic's. These are served by oMLX on this
    /// machine and cost nothing but electricity — which is a point worth making
    /// on screen, not a reason to hide the row.
    static func isLocal(_ model: String) -> Bool {
        !model.hasPrefix("claude-")
    }

    /// The rate for a model id, and how much to trust it.
    ///
    /// Never returns nil. A model that falls through every rule is priced at
    /// Opus rates and flagged: guessing low would flatter the total, and the
    /// Ledger exists precisely not to do that. Silently dropping an unknown
    /// model would be worse still — a missing row reads as "this was free".
    static func rate(for model: String) -> (Rate, Confidence) {
        if isLocal(model) { return (Rate(input: 0, output: 0), .local) }
        if let hit = table[model] { return (hit, .exact) }

        // Dated snapshots: claude-haiku-4-5-20251001 -> claude-haiku-4-5.
        let undated = stripSnapshotDate(model)
        if undated != model, let hit = table[undated] { return (hit, .exact) }

        // A release we have no entry for yet, matched on tier by name.
        let name = model.lowercased()
        if name.contains("fable") || name.contains("mythos") {
            return (table["claude-fable-5"]!, .tier)
        }
        if name.contains("opus")   { return (table["claude-opus-5"]!, .tier) }
        if name.contains("sonnet") { return (table["claude-sonnet-5"]!, .tier) }
        if name.contains("haiku")  { return (table["claude-haiku-4-5"]!, .tier) }

        return (table["claude-opus-5"]!, .assumed)
    }

    /// Drops a trailing `-YYYYMMDD`, which is how Claude Code writes snapshots.
    static func stripSnapshotDate(_ model: String) -> String {
        let parts = model.split(separator: "-")
        guard let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) else {
            return model
        }
        return parts.dropLast().joined(separator: "-")
    }

    /// The cost of one bucket of tokens, in USD.
    static func cost(of t: TokenSplit, model: String) -> Double {
        let (rate, _) = rate(for: model)
        let perToken = (Double(t.input) * rate.input
                        + Double(t.output) * rate.output
                        + Double(t.cacheRead) * rate.input * Rate.cacheRead
                        + Double(t.cacheWrite5m) * rate.input * Rate.cacheWrite5m
                        + Double(t.cacheWrite1h) * rate.input * Rate.cacheWrite1h) / 1_000_000
        return perToken + Double(t.webSearches) * Rate.webSearch
    }
}
