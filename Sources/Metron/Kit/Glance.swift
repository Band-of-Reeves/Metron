import SwiftUI

/// How much room a glance has to say its piece.
///
/// The three widget sizes mirror what macOS gives desktop widgets, so a glance
/// laid out for `.medium` looks at home beside Weather or Calendar. `.full` is
/// the older, unconstrained readout — the menu bar popover, and the desk window
/// for anyone who wants everything at once.
enum GlanceSize: String, CaseIterable, Identifiable {
    case small, medium, large, full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        case .full:   return "Full"
        }
    }

    /// nil for `.full`, which sizes itself to its content.
    var dimensions: CGSize? {
        switch self {
        case .small:  return CGSize(width: 176, height: 176)
        case .medium: return CGSize(width: 376, height: 176)
        case .large:  return CGSize(width: 376, height: 376)
        case .full:   return nil
        }
    }

    var cornerRadius: CGFloat { self == .full ? 14 : 22 }

    /// Inner padding that keeps the content off the rounded corners.
    var padding: CGFloat {
        switch self {
        case .small:  return 14
        case .medium: return 16
        case .large:  return 18
        case .full:   return 0
        }
    }
}

/// Severity ramp shared by the menu bar glyph, rings and stat tiles.
enum Severity {
    case idle, ok, warn, crit

    /// The usual reading: a fraction of some ceiling, where full is bad.
    static func forFraction(_ f: Double) -> Severity {
        switch f {
        case ..<0.70: return .ok
        case ..<0.90: return .warn
        default:      return .crit
        }
    }
}

/// What a glance puts in the menu bar: at most a ring and a few characters.
///
/// `fraction` drives the ring. When it is nil the glyph falls back to the
/// glance's SF Symbol, which is what a glance without a natural ceiling
/// (throughput, a service that is simply up or down) wants.
struct Headline: Equatable {
    var fraction: Double?
    var text: String?
    var severity: Severity = .ok

    init(fraction: Double? = nil, text: String? = nil, severity: Severity? = nil) {
        self.fraction = fraction
        self.text = text
        self.severity = severity ?? fraction.map(Severity.forFraction) ?? .ok
    }
}

extension Severity: Equatable {}

/// One readout: a data source, a headline, and a view per size.
///
/// Subclasses supply `load()` and `content(_:)`. Everything else — the refresh
/// timer, coalescing concurrent refreshes, the ticking clock that drives
/// countdown labels — is handled here, because every glance needs it and none
/// of it is domain-specific.
@MainActor
class GlanceStore: ObservableObject {

    /// Stable key. Used for UserDefaults, so changing one resets that glance's
    /// window placement and enablement.
    let id: String
    let name: String
    /// SF Symbol, for menus and for the menu bar when there is no ring.
    let symbol: String

    @Published private(set) var isRefreshing = false
    @Published private(set) var updatedAt: Date = .distantPast
    @Published var error: String?
    /// Bumped on a timer so countdowns and "updated Nm ago" tick without a fetch.
    @Published var now = Date()

    /// Seconds between automatic refreshes. Subclasses override the default;
    /// the user's choice is stored per glance.
    class var defaultRefreshSeconds: Int { 60 }
    /// Refresh choices offered in this glance's menu.
    class var refreshChoices: [Int] { [30, 60, 300, 900] }

    var refreshSeconds: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "\(id).refreshSeconds")
            return v > 0 ? v : Self.defaultRefreshSeconds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "\(id).refreshSeconds")
            objectWillChange.send()
            restartTimer()
        }
    }

    private var timer: Timer?
    private var tick: Timer?
    private var inFlight: Task<Void, Never>?

    init(id: String, name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }

    /// Starts the timers and takes a first reading. Separate from `init` so a
    /// glance can be constructed cheaply — the registry builds every glance at
    /// launch but only starts the ones the user has turned on.
    func start() {
        guard timer == nil else { return }
        restartTimer()
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        Task { await refresh() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        tick?.invalidate(); tick = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(5, refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// Concurrent callers join the in-flight refresh rather than returning
    /// early, so a caller always sees fresh data when this returns.
    func refresh() async {
        if let existing = inFlight {
            await existing.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRefreshing = true
            defer { self.isRefreshing = false }
            await self.load()
            self.updatedAt = Date()
            self.now = Date()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    // MARK: - Subclass surface

    /// Fetch and publish. Called on the main actor; do the slow part with
    /// `await` on a detached executor if it is expensive.
    func load() async {}

    /// What the menu bar shows. nil hides this glance's ring entirely.
    var headline: Headline? { nil }

    /// One line under the title in the desk window and popover header.
    var subtitle: String { "" }

    /// The readout at a given size.
    func content(_ size: GlanceSize) -> AnyView { AnyView(EmptyView()) }

    /// Extra items for this glance's settings menu, above the shared ones.
    func menuExtras() -> AnyView { AnyView(EmptyView()) }

    // MARK: - Shared derived state

    var updatedLine: String {
        guard updatedAt != .distantPast else { return "Loading…" }
        let ago = now.timeIntervalSince(updatedAt)
        return ago < 60 ? "Updated just now" : "Updated \(compactDuration(ago)) ago"
    }
}
