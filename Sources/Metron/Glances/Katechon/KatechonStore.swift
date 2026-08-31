import SwiftUI

/// KatechonOS on the NAS: pool health, cell quotas, services, boot image.
@MainActor
final class KatechonStore: GlanceStore {
    @Published private(set) var state: KatechonState?
    @Published private(set) var reachable = false

    init() {
        super.init(id: "katechon", name: "KatechonOS", symbol: "externaldrive.connected.to.line.below")
    }

    // A NAS changes slowly, and each read is an ssh round trip.
    override class var defaultRefreshSeconds: Int { 300 }
    override class var refreshChoices: [Int] { [60, 300, 900, 3600] }

    override func load() async {
        switch await KatechonFetcher.fetch() {
        case .success(let s):
            state = s
            reachable = true
            error = nil
        case .failure(let problem):
            reachable = false
            state = nil
            error = problem.message
        }
    }

    override func applyFixture(_ data: Data) -> Bool {
        guard let s = try? JSONDecoder().decode(KatechonState.self, from: data) else { return false }
        state = s
        reachable = true
        error = nil
        return true
    }

    override var headline: Headline? {
        guard reachable, let s = state else {
            return Headline(fraction: nil, text: "—", severity: .idle)
        }
        // A degraded pool outranks a full one: a widget's job is to surface the
        // thing you would otherwise learn about too late.
        if let pool = s.pool, !pool.isHealthy {
            return Headline(fraction: pool.fraction,
                            text: pool.health?.uppercased() ?? "?",
                            severity: .crit)
        }
        if !s.downServices.isEmpty {
            return Headline(fraction: s.pool?.fraction,
                            text: "\(s.downServices.count) down",
                            severity: .warn)
        }
        let fraction = s.pool?.fraction ?? 0
        return Headline(fraction: fraction, text: "\(Int((fraction * 100).rounded()))%")
    }

    override var subtitle: String {
        guard reachable, let s = state else { return "Not reachable" }
        var parts: [String] = []
        if let h = s.hostname { parts.append(h) }
        if let v = s.katechon_version { parts.append("v\(v)") }
        if let cells = s.cells { parts.append("\(cells.count) cells") }
        return parts.joined(separator: " · ")
    }

    override func menuExtras() -> AnyView {
        AnyView(
            Text("Reading \(KatechonFetcher.host) over ssh")
        )
    }

    override func content(_ size: GlanceSize) -> AnyView {
        switch size {
        case .full:   return AnyView(KatechonPanel(store: self))
        case .small:  return AnyView(KatechonSmall(store: self))
        case .medium: return AnyView(KatechonMedium(store: self))
        case .large:  return AnyView(KatechonLarge(store: self))
        }
    }
}
