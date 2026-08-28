import SwiftUI

/// Claude usage: the limit windows from `/usage`, plus a local read of this
/// machine's transcripts for the heatmap and model split.
@MainActor
final class UsageStore: GlanceStore {
    @Published private(set) var usage = UsageSnapshot()
    @Published private(set) var history = LocalHistory()

    private let scanner = TranscriptScanner()

    init() {
        super.init(id: "usage", name: "Claude usage", symbol: "gauge.with.needle")
        // Come back up with the last numbers we had, rather than an empty panel
        // that fills in a few seconds later — or never, if the source is down.
        if var cached = LastGood.load(UsageSnapshot.self, as: "usage-limits") {
            cached.isStale = true
            usage = cached
        }
    }

    override class var defaultRefreshSeconds: Int { 60 }

    override func load() async {
        // Limits and local history are independent — fetch them together.
        async let limits = UsageFetcher.fetch()
        async let local = scanner.scan()
        var (u, h) = await (limits, local)
        history = h

        if !u.windows.isEmpty {
            usage = u
            LastGood.save(u, as: "usage-limits")
            error = u.error
            return
        }

        // The fetch came back with nothing. Keep whatever we last had and say
        // how old it is, rather than throwing away a good reading because one
        // refresh failed — `/usage` going quiet should not blank the rings.
        guard !usage.windows.isEmpty else {
            usage = u
            error = u.error
            return
        }
        var kept = usage
        kept.isStale = true
        kept.error = u.error
        usage = kept
        error = u.error
    }

    /// How old the limit numbers are when they're stale.
    var limitsAge: TimeInterval? {
        guard usage.isStale, usage.fetchedAt != .distantPast else { return nil }
        return now.timeIntervalSince(usage.fetchedAt)
    }

    /// What the menu bar shows: the window closest to its ceiling.
    var mostConstrained: LimitWindow? { usage.mostConstrained }

    override var headline: Headline? {
        guard let w = mostConstrained else { return nil }
        return Headline(fraction: w.fraction, text: "\(Int(w.percent))%")
    }

    override var subtitle: String {
        if let age = limitsAge {
            return "Limits as of \(compactDuration(age)) ago"
        }
        if usage.planNote.contains("subscription") { return "Subscription plan" }
        if !usage.planNote.isEmpty { return usage.planNote }
        return "Claude Code usage"
    }

    override func content(_ size: GlanceSize) -> AnyView {
        switch size {
        case .full:   return AnyView(PanelView(store: self))
        case .small:  return AnyView(UsageSmall(store: self))
        case .medium: return AnyView(UsageMedium(store: self))
        case .large:  return AnyView(UsageLarge(store: self))
        }
    }
}
