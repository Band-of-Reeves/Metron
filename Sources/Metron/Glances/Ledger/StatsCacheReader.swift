import Foundation

/// Reads `~/.claude/stats-cache.json` — Claude Code's own roll-up, the thing
/// behind the CLI's stats screen.
///
/// The Ledger prices transcripts, not this file, because the roll-up fuses the
/// four token classes into one number per model per day and records no cache
/// TTL. What it *does* hold that transcripts cannot is the lifetime counters:
/// they keep accumulating after old transcripts are pruned.
///
/// It is also worth knowing what this file is not: it is written only when a
/// human opens the stats screen, it stops at yesterday, and it merges
/// additively without ever revisiting a day it has already computed. A session
/// still being appended to when it runs is frozen short forever. See
/// `docs/ledger/reconcile.sh`, which asserts that every *settled* day agrees
/// with the transcripts to the token.
enum StatsCacheReader {

    static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/stats-cache.json")
    }

    static func read() -> LifetimeStats? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(obj)
    }

    /// Split out so it can be tested against a literal rather than the machine.
    static func parse(_ obj: [String: Any]) -> LifetimeStats {
        var stats = LifetimeStats()
        stats.totalSessions = obj["totalSessions"] as? Int ?? 0
        stats.totalMessages = obj["totalMessages"] as? Int ?? 0

        if let stamp = obj["firstSessionDate"] as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            stats.firstSession = iso.date(from: stamp) ?? plain.date(from: stamp)
        }

        if let longest = obj["longestSession"] as? [String: Any] {
            // Milliseconds. A 495,332,330 here is 137.6 hours, not 15 years.
            let ms = (longest["duration"] as? Double) ?? Double(longest["duration"] as? Int ?? 0)
            stats.longestSessionSeconds = ms / 1000
            stats.longestSessionMessages = longest["messageCount"] as? Int ?? 0
        }

        if let hours = obj["hourCounts"] as? [String: Any] {
            let counts = hours.compactMapValues { $0 as? Int }
            if let peak = counts.max(by: { $0.value < $1.value }) {
                stats.peakHour = Int(peak.key)
            }
        }
        return stats
    }
}
