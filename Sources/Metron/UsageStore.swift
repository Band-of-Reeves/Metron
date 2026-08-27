import SwiftUI
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage = UsageSnapshot()
    @Published private(set) var history = LocalHistory()
    @Published private(set) var isRefreshing = false
    /// Drives the countdown labels without re-fetching.
    @Published var now = Date()
    /// Non-nil when the last launch-at-login change failed.
    @Published var loginItemError: String?

    @AppStorage("refreshSeconds") var refreshSeconds: Int = 60 {
        didSet { restartTimer() }
    }
    @AppStorage("showPercentInMenuBar") var showPercentInMenuBar: Bool = true
    @AppStorage("floatingPlacement") var floatingPlacement: String = "onTop" {
        didSet { FloatingPanelController.shared.applyPlacement() }
    }

    private let scanner = TranscriptScanner()
    private var inFlight: Task<Void, Never>?
    private var timer: Timer?
    private var tick: Timer?

    init() {
        restartTimer()
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        Task { await refresh() }
        // Bring the desktop window back if it was open when we last quit.
        Task { @MainActor in
            FloatingPanelController.shared.restoreIfNeeded(store: self)
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(20, refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// Refreshes both sources. Concurrent callers join the in-flight refresh
    /// rather than returning early, so a caller always sees fresh data.
    func refresh() async {
        if let existing = inFlight {
            await existing.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRefreshing = true
            defer { self.isRefreshing = false }

            // Limits and local history are independent — fetch them together.
            async let limits = UsageFetcher.fetch()
            async let local = self.scanner.scan()

            let (u, h) = await (limits, local)
            self.usage = u
            self.history = h
            self.now = Date()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// What the menu bar shows: the window closest to its ceiling.
    var headline: LimitWindow? { usage.mostConstrained }
}
