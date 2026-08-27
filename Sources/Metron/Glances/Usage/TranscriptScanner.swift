import Foundation

/// Aggregates local Claude Code transcripts into per-day, per-model activity.
///
/// This is the only source for the contribution heatmap. It reflects work done
/// on *this machine* through Claude Code — it does not see claude.ai chats or
/// other devices, exactly like the "what's contributing" block in /usage.
actor TranscriptScanner {

    private struct FileAggregate {
        let size: Int
        let modified: Date
        /// dayStart -> model -> output tokens
        var byDayModel: [Date: [String: Int]] = [:]
        var byDayRequests: [Date: Int] = [:]
    }

    private var cache: [String: FileAggregate] = [:]

    private var projectsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects")
    }

    /// Rescan, reusing cached aggregates for files that haven't changed.
    func scan(daysBack: Int = 119) -> LocalHistory {
        let fm = FileManager.default
        var history = LocalHistory()

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: -daysBack, to: today) else {
            return history
        }

        guard let walker = fm.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return history }

        var livePaths = Set<String>()

        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            let path = url.path
            livePaths.insert(path)

            let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = vals?.fileSize ?? -1
            let modified = vals?.contentModificationDate ?? .distantPast

            // A file whose size and mtime both match is byte-identical in practice.
            let agg: FileAggregate
            if let hit = cache[path], hit.size == size, hit.modified == modified {
                agg = hit
            } else if let fresh = autoreleasepool(invoking: {
                aggregate(url: url, size: size, modified: modified, cal: cal)
            }) {
                cache[path] = fresh
                agg = fresh
            } else {
                continue
            }

            for (day, models) in agg.byDayModel where day >= cutoff {
                var entry = history.days[day] ?? DayActivity(day: day)
                for (m, t) in models { entry.byModel[m, default: 0] += t }
                entry.requests += agg.byDayRequests[day] ?? 0
                history.days[day] = entry
            }
        }

        // Drop cache entries for transcripts that no longer exist.
        cache = cache.filter { livePaths.contains($0.key) }

        // Model split for the trailing 7 days, matching the weekly window.
        if let weekStart = cal.date(byAdding: .day, value: -6, to: today) {
            for (day, act) in history.days where day >= weekStart {
                for (m, t) in act.byModel {
                    history.modelTotalsThisWeek[m, default: 0] += t
                }
            }
        }
        history.totalRequests = history.days.values.reduce(0) { $0 + $1.requests }
        history.scannedAt = Date()
        return history
    }

    // MARK: - Per-file parsing

    private func aggregate(url: URL, size: Int, modified: Date, cal: Calendar) -> FileAggregate? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var agg = FileAggregate(size: size, modified: modified)

        // Cheap byte prefilter — most lines are user turns or tool results and
        // never touch the JSON parser.
        let usageNeedle = Array(#""usage""#.utf8)
        let assistantNeedle = Array(#""assistant""#.utf8)

        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var lineStart = 0
            let count = buf.count

            var i = 0
            while i <= count {
                if i == count || base[i] == 0x0A {
                    let len = i - lineStart
                    if len > 40 {
                        let slice = UnsafeBufferPointer(start: base + lineStart, count: len)
                        if contains(slice, usageNeedle), contains(slice, assistantNeedle) {
                            autoreleasepool {
                                let lineData = Data(bytes: base + lineStart, count: len)
                                ingest(lineData, into: &agg, cal: cal)
                            }
                        }
                    }
                    lineStart = i + 1
                }
                i += 1
            }
        }
        return agg
    }

    private func contains(_ hay: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        let n = needle.count
        guard hay.count >= n else { return false }
        let first = needle[0]
        var i = 0
        let limit = hay.count - n
        while i <= limit {
            if hay[i] == first {
                var j = 1
                while j < n, hay[i + j] == needle[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }

    private func ingest(_ lineData: Data, into agg: inout FileAggregate, cal: Calendar) {
        guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let when = Self.iso.date(from: stamp)
        else { return }

        let model = (message["model"] as? String) ?? "unknown"
        // Output tokens are the honest proxy for effort: cache reads are cheap
        // and would swamp the graph if counted.
        let out = (usage["output_tokens"] as? Int) ?? 0
        let day = cal.startOfDay(for: when)

        agg.byDayModel[day, default: [:]][model, default: 0] += out
        agg.byDayRequests[day, default: 0] += 1
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
