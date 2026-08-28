import Foundation

/// Reads the limit windows out of `~/.claude.json`.
///
/// Claude Code caches the account's utilisation there and refreshes it as it
/// runs, so the numbers `/usage` used to print are already on disk. Reading
/// them directly is better than shelling out for them in every way that
/// matters here: it is instant rather than a twenty-second subprocess, it
/// needs no credential of its own, and it does not depend on a slash command
/// choosing to print anything — which is exactly what stopped happening.
///
/// The tradeoff is honest and worth stating: this cache only moves when Claude
/// Code runs. If you haven't used it in a day, the numbers are a day old, and
/// the panel says so rather than pretending otherwise.
enum UsageCache {

    static var path: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
    }

    struct Reading {
        var windows: [LimitWindow] = []
        var planNote: String = ""
        /// When the cache itself was last written.
        var cachedAt: Date?
    }

    static func read() -> Reading? {
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var out = Reading()
        out.cachedAt = (try? path.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate

        if let account = root["oauthAccount"] as? [String: Any],
           let tier = account["organizationRateLimitTier"] as? String {
            out.planNote = planLabel(tier)
        }

        guard let cached = root["cachedUsageUtilization"] as? [String: Any],
              let utilisation = cached["utilization"] as? [String: Any]
        else { return out.windows.isEmpty && out.planNote.isEmpty ? nil : out }

        // `limits` is the list the CLI itself renders: already ordered, already
        // labelled, and it carries the per-model window with the model's real
        // display name. Prefer it over the sibling per-bucket keys, which mix
        // in unreleased buckets under internal codenames.
        if let limits = utilisation["limits"] as? [[String: Any]] {
            out.windows = limits.compactMap(window(fromLimit:))
        }

        if out.windows.isEmpty {
            // Fallback for a shape that predates `limits`.
            for (key, value) in utilisation where key != "limits" {
                guard let bucket = value as? [String: Any],
                      let percent = numeric(bucket["utilization"]),
                      // Skip buckets that exist but have never been used —
                      // they are unreleased surfaces, not limits you have.
                      percent > 0 || key == "five_hour" || key == "seven_day"
                else { continue }
                let resetsRaw = bucket["resets_at"] as? String
                let resetsAt = resetsRaw.flatMap(parseTimestamp)
                out.windows.append(
                    LimitWindow(label: label(for: key), title: title(for: key),
                                percent: percent, resetsAt: resetsAt,
                                resetsRaw: resetsAt == nil ? resetsRaw : nil)
                )
            }
            out.windows.sort { rank(for: $0.title) < rank(for: $1.title) }
        }

        return out.windows.isEmpty && out.planNote.isEmpty ? nil : out
    }

    /// One entry of `cachedUsageUtilization.utilization.limits`.
    private static func window(fromLimit entry: [String: Any]) -> LimitWindow? {
        guard let percent = numeric(entry["percent"]) else { return nil }
        let kind = entry["kind"] as? String ?? ""
        let model = (entry["scope"] as? [String: Any])
            .flatMap { $0["model"] as? [String: Any] }
            .flatMap { $0["display_name"] as? String }

        let label: String
        let title: String
        switch kind {
        case "session":
            label = "Session"
            title = "Current session"
        case "weekly_all":
            label = "Week"
            title = "Current week (all models)"
        case "weekly_scoped":
            label = model ?? "Week"
            title = "Current week (\(model ?? "scoped"))"
        default:
            label = model ?? prettify(kind)
            title = prettify(kind)
        }

        let resetsRaw = entry["resets_at"] as? String
        let resetsAt = resetsRaw.flatMap(parseTimestamp)
        return LimitWindow(label: label, title: title, percent: percent,
                           resetsAt: resetsAt,
                           resetsRaw: resetsAt == nil ? resetsRaw : nil)
    }

    // MARK: - Field shapes

    private static func numeric(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    /// "2026-08-30T03:00:00.343297+00:00" — fractional seconds and an offset.
    private static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    // MARK: - Naming

    /// `five_hour` -> "Session", `seven_day` -> "Week", `seven_day_opus` -> "Opus".
    static func label(for key: String) -> String {
        switch key {
        case "five_hour":  return "Session"
        case "seven_day":  return "Week"
        default:
            guard key.hasPrefix("seven_day_") else { return prettify(key) }
            return prettify(String(key.dropFirst("seven_day_".count)))
        }
    }

    static func title(for key: String) -> String {
        switch key {
        case "five_hour": return "Current session"
        case "seven_day": return "Current week (all models)"
        default:
            guard key.hasPrefix("seven_day_") else { return prettify(key) }
            return "Current week (\(prettify(String(key.dropFirst("seven_day_".count)))))"
        }
    }

    /// Session first, the all-models week second, per-model weeks after.
    private static func rank(for title: String) -> Int {
        if title.contains("session") { return 0 }
        if title.contains("all models") { return 1 }
        return 2
    }

    private static func prettify(_ raw: String) -> String {
        raw.split(separator: "_")
            .map { word -> String in
                // Keep known product names cased the way people write them.
                switch word.lowercased() {
                case "oauth": return "OAuth"
                case "mcp":   return "MCP"
                default:      return word.prefix(1).uppercased() + word.dropFirst()
                }
            }
            .joined(separator: " ")
    }

    /// "default_claude_max_20x" -> "Max 20x plan".
    static func planLabel(_ tier: String) -> String {
        let t = tier.lowercased()
        if t.contains("max_20x") { return "Max 20x plan" }
        if t.contains("max_5x")  { return "Max 5x plan" }
        if t.contains("max")     { return "Max plan" }
        if t.contains("pro")     { return "Pro plan" }
        if t.contains("team")    { return "Team plan" }
        if t.contains("enterprise") { return "Enterprise plan" }
        return prettify(tier.replacingOccurrences(of: "default_", with: "")) + " plan"
    }
}
