import SwiftUI

/// This machine: CPU, memory, network throughput and disk headroom.
@MainActor
final class SystemStore: GlanceStore {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var cpuHistory = SampleWindow(capacity: 60)
    @Published private(set) var memHistory = SampleWindow(capacity: 60)
    @Published private(set) var downHistory = SampleWindow(capacity: 60)
    @Published private(set) var upHistory = SampleWindow(capacity: 60)

    private let metrics = SystemMetrics()

    init() {
        super.init(id: "system", name: "System", symbol: "cpu")
    }

    // Rates need a short baseline to mean anything, and reading the kernel is
    // cheap — this is the one glance that wants a fast cadence.
    override class var defaultRefreshSeconds: Int { 3 }
    override class var refreshChoices: [Int] { [1, 2, 3, 5, 10, 30] }

    /// Which reading the menu bar ring tracks.
    enum MenuBarMetric: String, CaseIterable, Identifiable {
        case cpu, memory, network, pressed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cpu:     return "CPU"
            case .memory:  return "Memory"
            case .network: return "Network"
            case .pressed: return "Whichever is highest"
            }
        }
    }

    var menuBarMetric: MenuBarMetric {
        get {
            MenuBarMetric(rawValue: UserDefaults.standard.string(forKey: "system.menuBarMetric") ?? "")
                ?? .cpu
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "system.menuBarMetric")
            objectWillChange.send()
        }
    }

    override func load() async {
        let s = metrics.sample()
        snapshot = s
        cpuHistory.append(s.cpuTotal)
        memHistory.append(s.memoryFraction)
        downHistory.append(s.netDown)
        upHistory.append(s.netUp)
    }

    override var headline: Headline? {
        let s = snapshot
        switch menuBarMetric {
        case .cpu:
            return Headline(fraction: s.cpuTotal, text: "\(Int((s.cpuTotal * 100).rounded()))%")
        case .memory:
            return Headline(fraction: s.memoryFraction,
                            text: "\(Int((s.memoryFraction * 100).rounded()))%")
        case .network:
            // Throughput has no ceiling, so there is no honest ring to draw.
            let busiest = max(s.netDown, s.netUp)
            return Headline(fraction: nil,
                            text: compactRate(busiest),
                            severity: busiest > 1e5 ? .ok : .idle)
        case .pressed:
            let candidates: [(Double, String)] = [
                (s.cpuTotal, "CPU"), (s.memoryFraction, "MEM"), (s.diskUsedFraction, "DISK"),
            ]
            let top = candidates.max { $0.0 < $1.0 } ?? (0, "CPU")
            return Headline(fraction: top.0, text: "\(top.1) \(Int((top.0 * 100).rounded()))%")
        }
    }

    override var subtitle: String {
        let s = snapshot
        guard s.coreCount > 0 else { return "Reading the machine…" }
        return "\(s.coreCount) cores · \(compactRAM(s.memoryTotal)) · up \(compactDuration(s.uptime))"
    }

    override func menuExtras() -> AnyView {
        AnyView(
            Picker("Menu bar shows", selection: Binding(
                get: { self.menuBarMetric },
                set: { self.menuBarMetric = $0 }
            )) {
                ForEach(MenuBarMetric.allCases) { m in Text(m.title).tag(m) }
            }
        )
    }

    override func content(_ size: GlanceSize) -> AnyView {
        switch size {
        case .full:   return AnyView(SystemPanel(store: self))
        case .small:  return AnyView(SystemSmall(store: self))
        case .medium: return AnyView(SystemMedium(store: self))
        case .large:  return AnyView(SystemLarge(store: self))
        }
    }
}
