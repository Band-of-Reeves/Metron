import Foundation

/// The snapshot `katechon state` prints: the pool, the cells, the services,
/// and which image the machine booted.
struct KatechonState: Decodable, Equatable {
    struct Pool: Decodable, Equatable {
        var name: String?
        var health: String?
        var size: String?
        var allocated: String?
        var free: String?

        var fraction: Double {
            guard let total = zfsBytes(size), total > 0,
                  let used = zfsBytes(allocated) else { return 0 }
            return min(used / total, 1)
        }
        var isHealthy: Bool { (health ?? "").uppercased() == "ONLINE" }
    }

    struct Storage: Decodable, Equatable {
        var pool_name: String?
        var pool: Pool?
    }

    struct Cell: Decodable, Equatable, Identifiable {
        var name: String
        var used: String?
        var quota: String?
        var available: String?
        var state: String?
        var grants: Int?

        var id: String { name }
        var isRunning: Bool { state == "running" }

        /// nil when the cell has no quota — an unbounded cell has no fullness.
        var fraction: Double? {
            guard let quota = zfsBytes(quota), quota > 0,
                  let used = zfsBytes(used) else { return nil }
            return min(used / quota, 1)
        }
    }

    struct Service: Decodable, Equatable, Identifiable {
        var unit: String
        var state: String?
        var id: String { unit }

        var isUp: Bool { state == "active" }
        /// A socket-activated unit sits in `listening`, which is healthy.
        var isAcceptable: Bool { isUp || state == "listening" }
        var shortName: String {
            unit.replacingOccurrences(of: ".socket", with: "")
                .replacingOccurrences(of: ".service", with: "")
        }
    }

    struct Bootc: Decodable, Equatable {
        var readable: Bool?
        var booted: String?
        var rollback: String?
    }

    var katechon_version: String?
    var hostname: String?
    var kernel: String?
    var generated_at: String?
    var bootc: Bootc?
    var storage: Storage?
    var cells: [Cell]?
    var services: [Service]?

    var pool: Pool? { storage?.pool }
    var allCells: [Cell] { cells ?? [] }
    var allServices: [Service] { services ?? [] }

    /// The cell closest to its quota — the one worth knowing about.
    var fullestCell: Cell? {
        allCells.compactMap { c -> (Cell, Double)? in
            c.fraction.map { (c, $0) }
        }
        .max { $0.1 < $1.1 }?.0
    }

    var downServices: [Service] { allServices.filter { !$0.isAcceptable } }
}

/// Parses a ZFS human size — "1.81T", "930G", "12.5M", "-", "none".
func zfsBytes(_ text: String?) -> Double? {
    guard var s = text?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
          s != "-", s.lowercased() != "none" else { return nil }
    let multipliers: [(Character, Double)] = [
        ("K", 1024), ("M", 1024 * 1024), ("G", 1024 * 1024 * 1024),
        ("T", pow(1024, 4)), ("P", pow(1024, 5)),
    ]
    var multiplier = 1.0
    if let last = s.last, let m = multipliers.first(where: { $0.0 == last }) {
        multiplier = m.1
        s.removeLast()
    }
    guard let value = Double(s) else { return nil }
    return value * multiplier
}

/// Why a reading failed, in words worth showing on a widget.
struct KatechonProblem: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Reads KatechonOS over ssh.
///
/// `katechon-ui-serve` binds to 127.0.0.1 on the NAS, so there is no HTTP port
/// to reach from another machine unless you tunnel one. ssh is the transport
/// that actually exists — and, like the usage readout shelling out to an
/// already-authenticated `claude`, it means this widget holds no credential of
/// its own. Set `katechon.baseURL` in defaults to use HTTP instead when a
/// tunnel or a changed bind makes that possible.
enum KatechonFetcher {

    static var host: String {
        UserDefaults.standard.string(forKey: "katechon.host") ?? "katechon"
    }

    static var httpBase: URL? {
        UserDefaults.standard.string(forKey: "katechon.baseURL").flatMap(URL.init(string:))
    }

    static func fetch() async -> Result<KatechonState, KatechonProblem> {
        if let base = httpBase {
            return await fetchHTTP(base)
        }
        return await fetchSSH()
    }

    private static func fetchHTTP(_ base: URL) async -> Result<KatechonState, KatechonProblem> {
        var request = URLRequest(url: base.appendingPathComponent("api/state"))
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return .success(try JSONDecoder().decode(KatechonState.self, from: data))
        } catch {
            return .failure(KatechonProblem("Couldn't read \(base.absoluteString): \(error.localizedDescription)"))
        }
    }

    /// Wall-clock ceiling on one ssh attempt.
    ///
    /// `ConnectTimeout` only bounds the TCP connect. Name resolution is not
    /// covered by it: an unresolvable `.local` host can leave ssh wedged in
    /// mDNS for minutes, which would hang this glance's refresh loop forever —
    /// every later refresh joins the in-flight task, so one stuck process
    /// stops the widget updating at all. Hence a hard deadline and a kill.
    private static let deadlineSeconds = 12.0

    private static func fetchSSH() async -> Result<KatechonState, KatechonProblem> {
        let target = host
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-o", "BatchMode=yes",           // never sit at a password prompt
                    "-o", "ConnectTimeout=5",
                    "-o", "StrictHostKeyChecking=accept-new",
                    target, "katechon state",
                ]
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(
                        KatechonProblem("Couldn't run ssh: \(error.localizedDescription)")))
                    return
                }

                let killer = DispatchWorkItem {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + deadlineSeconds,
                                                  execute: killer)

                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let killed = killer.isCancelled == false && process.terminationReason == .uncaughtSignal
                killer.cancel()

                guard process.terminationStatus == 0, !killed else {
                    if killed {
                        continuation.resume(returning: .failure(KatechonProblem(
                            "\(target) didn't answer within \(Int(deadlineSeconds))s")))
                        return
                    }
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: .failure(KatechonProblem(
                        message.isEmpty ? "\(target) isn't answering" : Self.tidy(message, host: target))))
                    return
                }

                do {
                    let state = try JSONDecoder().decode(KatechonState.self, from: data)
                    continuation.resume(returning: .success(state))
                } catch {
                    continuation.resume(returning: .failure(KatechonProblem(
                        "\(target) answered, but not with a state snapshot")))
                }
            }
        }
    }

    /// ssh is verbose on failure; keep the one line that says what went wrong.
    private static func tidy(_ stderr: String, host: String) -> String {
        let line = stderr.split(separator: "\n").last.map(String.init) ?? stderr
        if line.contains("Could not resolve") || line.contains("Name or service not known") {
            return "Can't find \(host) on the network"
        }
        if line.contains("Connection refused") || line.contains("No route to host") {
            return "\(host) isn't reachable"
        }
        if line.contains("Permission denied") {
            return "\(host) refused the key — check ssh access"
        }
        if line.contains("command not found") {
            return "\(host) has no `katechon` on the path"
        }
        return line
    }
}
