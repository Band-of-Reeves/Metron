import Foundation

/// Reads `~/.claude/projects/**/*.jsonl` into per-day, per-model token splits.
///
/// Separate from `TranscriptScanner`, which counts output tokens for the
/// heatmap and nothing else. The Ledger needs all five priced classes and the
/// cache-write TTL, so it parses the same files differently rather than
/// widening a type the usage glance depends on.
///
/// Caching is per file by size and mtime, like `TranscriptScanner` — a cold
/// scan of ~6,900 files is about a second, and refreshes after that touch only
/// what changed.
actor TokenLedgerScanner {
    static let shared = TokenLedgerScanner()

    private struct FileAggregate {
        let size: Int
        let modified: Date
        var byDayModel: [Date: [String: TokenSplit]] = [:]
    }

    private var cache: [String: FileAggregate] = [:]

    private var projectsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }

    func scan(daysBack: Int = 400) -> [Date: LedgerDay] {
        let fm = FileManager.default
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: -daysBack, to: today),
              let walker = fm.enumerator(
                at: projectsURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles])
        else { return [:] }

        var days: [Date: LedgerDay] = [:]
        var livePaths = Set<String>()

        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            livePaths.insert(url.path)

            let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = vals?.fileSize ?? -1
            let modified = vals?.contentModificationDate ?? .distantPast

            let agg: FileAggregate
            if let hit = cache[url.path], hit.size == size, hit.modified == modified {
                agg = hit
            } else if let fresh = autoreleasepool(invoking: {
                aggregate(url: url, size: size, modified: modified, cal: cal)
            }) {
                cache[url.path] = fresh
                agg = fresh
            } else {
                continue
            }

            for (day, models) in agg.byDayModel where day >= cutoff {
                var entry = days[day] ?? LedgerDay(day: day)
                for (m, split) in models { entry.byModel[m, default: TokenSplit()] += split }
                days[day] = entry
            }
        }

        cache = cache.filter { livePaths.contains($0.key) }
        return days
    }

    private func aggregate(url: URL, size: Int, modified: Date,
                           cal: Calendar) -> FileAggregate? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var agg = FileAggregate(size: size, modified: modified)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Cheap reject before paying for JSON parsing: the overwhelming
            // majority of transcript lines carry no usage at all.
            guard line.contains("\"usage\"") else { continue }
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let model = message["model"] as? String ?? "unknown"
            guard let stamp = obj["timestamp"] as? String,
                  let date = iso.date(from: stamp) ?? isoPlain.date(from: stamp)
            else { continue }
            let day = cal.startOfDay(for: date)

            var split = TokenSplit()
            split.input = usage["input_tokens"] as? Int ?? 0
            split.output = usage["output_tokens"] as? Int ?? 0
            split.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

            // The TTL breakdown is the reason this scanner exists. When it is
            // absent, fall back to the fused total at the 5-minute rate and
            // accept the understatement rather than inventing a split.
            let fusedWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
            if let creation = usage["cache_creation"] as? [String: Any] {
                split.cacheWrite5m = creation["ephemeral_5m_input_tokens"] as? Int ?? 0
                split.cacheWrite1h = creation["ephemeral_1h_input_tokens"] as? Int ?? 0
                // Trust the fused figure if the parts do not add up to it.
                let parts = split.cacheWrite5m + split.cacheWrite1h
                if parts == 0 && fusedWrite > 0 { split.cacheWrite5m = fusedWrite }
            } else {
                split.cacheWrite5m = fusedWrite
            }

            if let tools = usage["server_tool_use"] as? [String: Any] {
                split.webSearches = tools["web_search_requests"] as? Int ?? 0
            }

            agg.byDayModel[day, default: [:]][model, default: TokenSplit()] += split
        }
        return agg
    }
}
