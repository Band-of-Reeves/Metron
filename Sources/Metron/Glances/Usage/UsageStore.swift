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
    }

    override class var defaultRefreshSeconds: Int { 60 }

    override func load() async {
        // Limits and local history are independent — fetch them together.
        async let limits = UsageFetcher.fetch()
        async let local = scanner.scan()
        let (u, h) = await (limits, local)
        usage = u
        history = h
        error = u.error
    }

    /// What the menu bar shows: the window closest to its ceiling.
    var mostConstrained: LimitWindow? { usage.mostConstrained }

    override var headline: Headline? {
        guard let w = mostConstrained else { return nil }
        return Headline(fraction: w.fraction, text: "\(Int(w.percent))%")
    }

    override var subtitle: String {
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
