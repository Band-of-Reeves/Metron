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

    /// Parses one transcript.
    ///
    /// Works on bytes, not `String`. A 1.2 GB corpus of 260k lines took 21
    /// seconds through `String.contains` and `line.data(using:)` — Swift's
    /// String comparison is grapheme-aware, and re-encoding every line to
    /// `Data` for JSONSerialization pays for the whole file twice. Scanning
    /// the UTF-8 directly and handing JSONSerialization a slice of the buffer
    /// it already has removes both.
    private func aggregate(url: URL, size: Int, modified: Date,
                           cal: Calendar) -> FileAggregate? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var agg = FileAggregate(size: size, modified: modified)

        // Local-day lookup keyed by the timestamp's "yyyy-MM-ddTHH" prefix, so
        // 96k records cost a few hundred calendar operations rather than 96k.
        var dayCache: [String: Date] = [:]

        let newline = UInt8(0x0A)
        let needle = Array("\"usage\"".utf8)

        var lineStart = data.startIndex
        while lineStart < data.endIndex {
            let lineEnd = data[lineStart...].firstIndex(of: newline) ?? data.endIndex
            defer { lineStart = lineEnd < data.endIndex ? lineEnd + 1 : data.endIndex }
            guard lineEnd > lineStart else { continue }
            let line = data[lineStart..<lineEnd]
            guard contains(line, needle) else { continue }

            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let stamp = obj["timestamp"] as? String,
                  stamp.count >= 13
            else { continue }

            let key = String(stamp.prefix(13))
            let day: Date
            if let hit = dayCache[key] {
                day = hit
            } else if let parsed = Self.localDay(fromISOHourPrefix: key, cal: cal) {
                dayCache[key] = parsed
                day = parsed
            } else {
                continue
            }

            let model = message["model"] as? String ?? "unknown"
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
                if split.cacheWrite5m + split.cacheWrite1h == 0 && fusedWrite > 0 {
                    split.cacheWrite5m = fusedWrite
                }
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

    /// Substring search over raw bytes.
    private func contains(_ haystack: Data, _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count, let first = needle.first else { return false }
        let limit = haystack.endIndex - needle.count
        var i = haystack.startIndex
        while i <= limit {
            if haystack[i] == first {
                var match = true
                for k in 1..<needle.count where haystack[i + k] != needle[k] {
                    match = false
                    break
                }
                if match { return true }
            }
            i += 1
        }
        return false
    }

    /// "2026-08-25T02" -> the local day that instant falls in.
    ///
    /// Claude Code writes UTC. Bucketing by the UTC date would put late-evening
    /// work on the wrong day for anyone west of Greenwich, so the instant is
    /// reconstructed and then handed to the local calendar — the same thing
    /// `TranscriptScanner` does, so the two glances agree about what "today" is.
    static func localDay(fromISOHourPrefix key: String, cal: Calendar) -> Date? {
        let chars = Array(key.utf8)
        guard chars.count >= 13 else { return nil }
        func num(_ range: Range<Int>) -> Int? {
            var v = 0
            for i in range {
                let c = chars[i]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let year = num(0..<4), let month = num(5..<7),
              let dayNum = num(8..<10), let hour = num(11..<13) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = dayNum; comps.hour = hour
        guard let instant = utc.date(from: comps) else { return nil }
        return cal.startOfDay(for: instant)
    }
}
