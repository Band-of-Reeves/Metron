import Foundation

/// One rate-limit window as reported by `claude -p "/usage"`.
struct LimitWindow: Identifiable, Equatable {
    let id = UUID()
    /// Short label for the ring, e.g. "Session", "Week", "Fable".
    let label: String
    /// Full title as the CLI printed it, e.g. "Current week (all models)".
    let title: String
    /// 0...100
    let percent: Double
    /// Absolute reset instant, when we could parse one.
    let resetsAt: Date?
    /// Raw reset text, kept as a fallback when parsing fails.
    let resetsRaw: String?

    var fraction: Double { min(max(percent / 100, 0), 1) }
}

/// A named contributor (skill, subagent, MCP server) with its share of usage.
struct Contributor: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let pct: Int
}

/// The "what's contributing" block for one time span.
struct Drivers: Equatable {
    var span: String = ""
    var requests: Int = 0
    var sessions: Int = 0
    var behaviors: [String] = []
    var skills: [Contributor] = []
    var agents: [Contributor] = []
    var mcpServers: [Contributor] = []
}

/// Everything the `/usage` command told us.
struct UsageSnapshot: Equatable {
    var windows: [LimitWindow] = []
    var day: Drivers = Drivers()
    var week: Drivers = Drivers()
    var planNote: String = ""
    var fetchedAt: Date = .distantPast
    var error: String? = nil

    /// The window closest to its ceiling — what the menu bar should show.
    var mostConstrained: LimitWindow? {
        windows.max(by: { $0.percent < $1.percent })
    }
}

/// One day of locally-observed activity, split by model.
struct DayActivity: Equatable {
    let day: Date
    /// model id -> output tokens
    var byModel: [String: Int] = [:]
    var requests: Int = 0
    var total: Int { byModel.values.reduce(0, +) }
}

/// Aggregated local transcript history used for the heatmap and model split.
struct LocalHistory: Equatable {
    var days: [Date: DayActivity] = [:]
    var modelTotalsThisWeek: [String: Int] = [:]
    var scannedAt: Date = .distantPast
    var totalRequests: Int = 0

    var peakDayTotal: Int {
        days.values.map(\.total).max() ?? 0
    }
}

/// Display metadata for the models we expect to see.
enum ModelStyle {
    /// Human label for a raw model id.
    static func label(for id: String) -> String {
        if id.hasPrefix("claude-opus-5") { return "Opus 5" }
        if id.hasPrefix("claude-fable-5") { return "Fable 5" }
        if id.hasPrefix("claude-sonnet-5") { return "Sonnet 5" }
        if id.hasPrefix("claude-opus-4-8") { return "Opus 4.8" }
        if id.hasPrefix("claude-opus-4-6") { return "Opus 4.6" }
        if id.hasPrefix("claude-haiku-4-5") { return "Haiku 4.5" }
        if id.hasPrefix("claude-sonnet-4") { return "Sonnet 4" }
        if id == "<synthetic>" { return "Synthetic" }
        // Local / third-party models: keep the first token, trimmed.
        let head = id.split(separator: "-").prefix(2).joined(separator: "-")
        return head.count > 18 ? String(head.prefix(18)) : head
    }

    /// Stable ordering so the legend doesn't jump around between refreshes.
    static func rank(for id: String) -> Int {
        if id.hasPrefix("claude-opus-5") { return 0 }
        if id.hasPrefix("claude-fable-5") { return 1 }
        if id.hasPrefix("claude-sonnet-5") { return 2 }
        if id.hasPrefix("claude-opus-4") { return 3 }
        if id.hasPrefix("claude-haiku") { return 4 }
        return 9
    }
}
