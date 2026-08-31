import Foundation

/// Counts what the money produced: commits, files and lines across the user's
/// repositories.
///
/// Cost alone is a flex. Cost next to output is an argument, and the argument
/// only works if the output side cannot be gamed — so the line counts exclude
/// generated, vendored and data paths, and lines are never the denominator of
/// a dollar figure. Commits and files changed are the headline.
///
/// Reads `ledger.repoRoot` from defaults; `~/Projects` otherwise. A machine
/// with no repositories there gets no output pane and keeps the cost pane,
/// rather than losing the whole glance.
actor GitOutputScanner {
    static let shared = GitOutputScanner()

    /// Excluding `*.json` and `*.csv` wholesale undercounts real config work.
    /// That is deliberately the direction to be wrong in: a counterweight that
    /// can be inflated by committing a data file is not evidence of anything.
    private static let excludes = [
        ":(exclude)*.lock", ":(exclude)*-lock.json", ":(exclude)*.pbxproj",
        ":(exclude)vendor/**", ":(exclude)third_party/**",
        ":(exclude)**/node_modules/**", ":(exclude)Pods/**",
        ":(exclude)*.min.js", ":(exclude)*.svg",
        ":(exclude)*.json", ":(exclude)*.csv",
    ]

    private var lastScan: (at: Date, stats: OutputStats)?

    static var repoRoot: URL {
        if let custom = UserDefaults.standard.string(forKey: "ledger.repoRoot"), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects")
    }

    /// Author filter, so a shared repo counts this user's work rather than
    /// everyone's. Falls back to the global git identity.
    private static var authorEmail: String? {
        if let set = UserDefaults.standard.string(forKey: "ledger.authorEmail"), !set.isEmpty {
            return set
        }
        return run("/usr/bin/git", ["config", "--global", "user.email"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func scan(daysBack: Int = 30) -> OutputStats? {
        // git log across ~20 repositories is not free; a five-minute floor keeps
        // a 15-minute refresh from paying for it every time.
        if let last = lastScan, Date().timeIntervalSince(last.at) < 300 { return last.stats }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: Self.repoRoot, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let since = "\(daysBack) days ago"
        var stats = OutputStats()

        for entry in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.appendingPathComponent(".git").path,
                                isDirectory: &isDir) else { continue }
            if let repo = Self.scanRepo(entry, since: since, cal: cal) {
                guard repo.stats.commits > 0 else { continue }
                stats.commits += repo.stats.commits
                stats.filesChanged += repo.stats.filesChanged
                stats.insertions += repo.stats.insertions
                stats.deletions += repo.stats.deletions
                stats.byRepo.append(repo.stats)
                for (day, n) in repo.commitsByDay { stats.commitsByDay[day, default: 0] += n }
            }
        }

        stats.repos = stats.byRepo.count
        stats.activeDays = stats.commitsByDay.count
        stats.byRepo.sort { $0.commits > $1.commits }
        guard stats.repos > 0 else { return nil }

        lastScan = (Date(), stats)
        return stats
    }

    private static func scanRepo(_ url: URL, since: String,
                                 cal: Calendar) -> (stats: RepoOutput, commitsByDay: [Date: Int])? {
        var args = ["-C", url.path, "log", "--since=\(since)",
                    "--numstat", "--date=short", "--pretty=format:%x01%ad"]
        if let email = authorEmail { args.append("--author=\(email)") }
        args.append("--")
        args.append(contentsOf: excludes)

        guard let out = run("/usr/bin/git", args), !out.isEmpty else { return nil }

        var repo = RepoOutput(name: url.lastPathComponent)
        var byDay: [Date: Int] = [:]
        let dayFormat = DateFormatter()
        dayFormat.dateFormat = "yyyy-MM-dd"
        dayFormat.timeZone = .current
        var currentDay: Date?

        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\u{01}") {
                repo.commits += 1
                let stamp = String(line.dropFirst())
                if let day = dayFormat.date(from: stamp).map({ cal.startOfDay(for: $0) }) {
                    currentDay = day
                    byDay[day, default: 0] += 1
                    if repo.lastCommit == nil { repo.lastCommit = day }
                }
                continue
            }
            // "12\t3\tpath" — a binary file writes "-" for both counts.
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            repo.filesChanged += 1
            repo.insertions += Int(cols[0]) ?? 0
            repo.deletions += Int(cols[1]) ?? 0
        }
        _ = currentDay
        return repo.commits > 0 ? (repo, byDay) : nil
    }

    /// Runs a command and returns stdout, or nil if it fails.
    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // A repository mid-rebase, or one on a network volume that has gone
        // away, can otherwise wedge the refresh.
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
