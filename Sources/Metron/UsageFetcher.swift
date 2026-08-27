import Foundation

/// Runs `claude -p "/usage"` and turns its output into a `UsageSnapshot`.
///
/// `/usage` is a local slash command: it costs nothing and makes no model call,
/// it just reads the same claude.ai limits endpoint the desktop Usage pane uses.
enum UsageFetcher {

    // MARK: - Locating the CLI

    private static let candidatePaths = [
        "\(NSHomeDirectory())/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.claude/local/claude",
    ]

    private static var cachedBinary: String?

    static func locateClaude() -> String? {
        if let c = cachedBinary, FileManager.default.isExecutableFile(atPath: c) { return c }
        for p in candidatePaths where FileManager.default.isExecutableFile(atPath: p) {
            cachedBinary = p
            return p
        }
        // A GUI app inherits a minimal PATH, so ask a login shell as a last resort.
        if let found = runLoginShell("command -v claude")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !found.isEmpty,
           FileManager.default.isExecutableFile(atPath: found) {
            cachedBinary = found
            return found
        }
        return nil
    }

    private static func runLoginShell(_ command: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Fetch

    static func fetch() async -> UsageSnapshot {
        guard let bin = locateClaude() else {
            var s = UsageSnapshot()
            s.error = "Couldn't find the `claude` CLI."
            s.fetchedAt = Date()
            return s
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["-p", "/usage", "--output-format", "json"]
        // Run somewhere neutral so we don't pick up project config or hooks.
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        // Strip inherited Claude Code session variables — if Metron is ever
        // launched from inside a Claude Code session, they'd confuse the child.
        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key.hasPrefix("CLAUDE") || key == "CLAUDECODE" {
            env.removeValue(forKey: key)
        }
        env["CLAUDE_CODE_ENTRYPOINT"] = "metron"
        proc.environment = env

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        do { try proc.run() } catch {
            var s = UsageSnapshot()
            s.error = "Couldn't launch the CLI: \(error.localizedDescription)"
            s.fetchedAt = Date()
            return s
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["result"] as? String else {
            var s = UsageSnapshot()
            s.error = proc.terminationStatus == 0
                ? "Unexpected output from /usage."
                : "/usage exited with code \(proc.terminationStatus)."
            s.fetchedAt = Date()
            return s
        }

        var snap = parse(text)
        snap.fetchedAt = Date()
        if snap.windows.isEmpty && snap.error == nil {
            snap.error = "No limit windows reported — are you on a subscription plan?"
        }
        return snap
    }

    // MARK: - Parsing

    /// Turns the human-readable /usage text into structured values.
    /// Deliberately generic: any `Title: N% used · resets X` line becomes a
    /// window, so new server-side buckets show up without a code change.
    static func parse(_ text: String) -> UsageSnapshot {
        var snap = UsageSnapshot()
        var current: WritableKeyPath<UsageSnapshot, Drivers>?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("You are currently using") {
                snap.planNote = line
                continue
            }

            // "Current session: 19% used · resets Aug 22 at 8:10pm (America/New_York)"
            if let w = parseWindow(line) {
                snap.windows.append(w)
                continue
            }

            // "Last 24h · 2068 requests · 6 sessions"
            if let (span, reqs, sess) = parseSpanHeader(line) {
                let kp: WritableKeyPath<UsageSnapshot, Drivers> =
                    span.contains("24h") ? \.day : \.week
                snap[keyPath: kp].span = span
                snap[keyPath: kp].requests = reqs
                snap[keyPath: kp].sessions = sess
                current = kp
                continue
            }

            guard let kp = current else { continue }

            // "  Top skills: /claude-api 9%, /artifact-design 3%"
            if let (kind, items) = parseTopLine(line) {
                switch kind {
                case "skills": snap[keyPath: kp].skills = items
                case "subagents": snap[keyPath: kp].agents = items
                default: snap[keyPath: kp].mcpServers = items
                }
                continue
            }

            // "  99% of your usage came from subagent-heavy sessions"
            if line.range(of: #"^\d+% of your usage"#, options: .regularExpression) != nil {
                snap[keyPath: kp].behaviors.append(line)
            }
        }

        return snap
    }

    private static func parseWindow(_ line: String) -> LimitWindow? {
        let pattern = #"^(.+?):\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+(.+?))?$"#
        guard let m = line.firstMatch(pattern), m.count >= 3,
              let pct = Double(m[2]) else { return nil }
        let title = m[1]
        let resetRaw: String? = m.count > 3 && !m[3].isEmpty ? m[3] : nil
        return LimitWindow(
            label: shortLabel(for: title),
            title: title,
            percent: pct,
            resetsAt: resetRaw.flatMap { parseResetDate($0) },
            resetsRaw: resetRaw
        )
    }

    /// "Current week (all models)" -> "Week"; "Current week (Fable)" -> "Fable".
    private static func shortLabel(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("session") { return "Session" }
        if let open = title.firstIndex(of: "("), let close = title.lastIndex(of: ")"), open < close {
            let inner = String(title[title.index(after: open)..<close])
            if inner.lowercased().contains("all models") { return "Week" }
            // "Sonnet only" -> "Sonnet"
            return inner.replacingOccurrences(of: " only", with: "")
        }
        if t.contains("week") { return "Week" }
        return title
    }

    private static func parseSpanHeader(_ line: String) -> (String, Int, Int)? {
        let pattern = #"^Last\s+(\S+)\s*·\s*(\d+)\s+requests\s*·\s*(\d+)\s+sessions"#
        guard let m = line.firstMatch(pattern), m.count >= 4 else { return nil }
        return (m[1], Int(m[2]) ?? 0, Int(m[3]) ?? 0)
    }

    private static func parseTopLine(_ line: String) -> (String, [Contributor])? {
        let pattern = #"^Top\s+(skills|subagents|MCP servers):\s*(.+)$"#
        guard let m = line.firstMatch(pattern), m.count >= 3 else { return nil }
        let kind = m[1] == "MCP servers" ? "mcp" : m[1]
        let items: [Contributor] = m[2].components(separatedBy: ", ").compactMap { chunk in
            let piece = chunk.trimmingCharacters(in: .whitespaces)
            guard let sp = piece.lastIndex(of: " ") else { return nil }
            let name = String(piece[piece.startIndex..<sp])
            let pctStr = piece[piece.index(after: sp)...].replacingOccurrences(of: "%", with: "")
            guard let pct = Int(pctStr) else { return nil }
            return Contributor(name: name, pct: pct)
        }
        return items.isEmpty ? nil : (kind, items)
    }

    // MARK: - Reset-time parsing

    /// Parses the humanized reset string back into an instant.
    /// Handles "Aug 22 at 8:10pm (America/New_York)", "today at 11pm",
    /// "tomorrow at 8am" and weekday forms. Returns nil rather than guessing.
    static func parseResetDate(_ raw: String, now: Date = Date()) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces)

        // Pull an explicit timezone out of the trailing parenthetical.
        var tz = TimeZone.current
        if let open = s.lastIndex(of: "("), let close = s.lastIndex(of: ")"), open < close {
            let name = String(s[s.index(after: open)..<close])
            if let parsed = TimeZone(identifier: name) ?? TimeZone(abbreviation: name) {
                tz = parsed
            }
            s = String(s[s.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        // Relative day forms resolve against "now" in the reported zone.
        let lower = s.lowercased()
        for (word, offset) in [("today", 0), ("tomorrow", 1), ("yesterday", -1)] {
            guard lower.hasPrefix(word) else { continue }
            let timePart = String(s.dropFirst(word.count))
                .replacingOccurrences(of: "at", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let tod = parseTimeOfDay(timePart) else { return nil }
            guard let base = cal.date(byAdding: .day, value: offset, to: now) else { return nil }
            return cal.date(bySettingHour: tod.h, minute: tod.m, second: 0, of: base)
        }

        // Absolute forms: "Aug 22 at 8:10pm" / "Aug 22 at 8pm".
        for fmt in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, h:mma", "MMM d"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = tz
            df.dateFormat = fmt
            guard let d = df.date(from: s) else { continue }
            // DateFormatter defaults a missing year to 1970 — graft on the
            // right one, bumping forward if that lands in the past.
            var comps = cal.dateComponents([.month, .day, .hour, .minute], from: d)
            let nowComps = cal.dateComponents([.year], from: now)
            comps.year = nowComps.year
            guard var result = cal.date(from: comps) else { continue }
            if result < now.addingTimeInterval(-36 * 3600) {
                comps.year = (comps.year ?? 2026) + 1
                result = cal.date(from: comps) ?? result
            }
            return result
        }
        return nil
    }

    private static func parseTimeOfDay(_ s: String) -> (h: Int, m: Int)? {
        for fmt in ["h:mma", "ha", "H:mm"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            df.timeZone = TimeZone(secondsFromGMT: 0)
            if let d = df.date(from: s) {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(secondsFromGMT: 0)!
                let c = cal.dateComponents([.hour, .minute], from: d)
                return (c.hour ?? 0, c.minute ?? 0)
            }
        }
        return nil
    }
}

// MARK: - Small regex helper

extension String {
    /// Returns the full match plus capture groups, or nil. Missing optional
    /// groups come back as "".
    func firstMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let m = re.firstMatch(in: self, range: range) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: self) else { return "" }
            return String(self[r])
        }
    }
}
