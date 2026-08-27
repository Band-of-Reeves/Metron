import SwiftUI
import Combine

/// Every glance the app knows how to show, and which ones the user has on.
///
/// A glance costs nothing until it is enabled: all of them are constructed at
/// launch, but only enabled ones get timers and only enabled ones get a menu
/// bar slot. Turning one off stops its polling entirely.
@MainActor
final class GlanceRegistry: ObservableObject {
    static let shared = GlanceRegistry()

    let all: [GlanceStore]

    @Published private(set) var enabled: Set<String> = []

    @Published var showTextInMenuBar: Bool = true {
        didSet { UserDefaults.standard.set(showTextInMenuBar, forKey: "showTextInMenuBar") }
    }

    /// Non-nil when the last launch-at-login change failed.
    @Published var loginItemError: String?

    private init() {
        Self.migrateLegacyDefaults()

        all = [
            UsageStore(),
            SystemStore(),
            OMLXStore(),
            KatechonStore(),
        ]

        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: "enabledGlances") as? [String] {
            enabled = Set(saved).intersection(all.map(\.id))
        } else {
            // First run after the split: exactly what Metron did before.
            enabled = ["usage"]
        }
        if enabled.isEmpty { enabled = ["usage"] }

        showTextInMenuBar = defaults.object(forKey: "showTextInMenuBar") as? Bool ?? true
    }

    func store(_ id: String) -> GlanceStore? { all.first { $0.id == id } }

    var enabledStores: [GlanceStore] { all.filter { enabled.contains($0.id) } }

    func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let store = store(id) else { return }
        if on {
            enabled.insert(id)
            store.start()
        } else {
            // Never leave the user with no menu bar item and no way back in.
            guard enabled.count > 1 else { return }
            enabled.remove(id)
            store.stop()
            DeskWindowManager.shared.controller(for: store).hide()
        }
        UserDefaults.standard.set(Array(enabled), forKey: "enabledGlances")
    }

    /// Starts the enabled glances and restores their desk windows.
    func activate() {
        for store in enabledStores {
            store.start()
            DeskWindowManager.shared.controller(for: store).restoreIfNeeded()
        }
    }

    /// Metron 1.0 stored one glance's settings under unprefixed keys. Carry
    /// them across so an existing install keeps its refresh interval, its
    /// desktop window and where that window was parked.
    private static func migrateLegacyDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "didMigrateToGlances") else { return }

        let moves: [(String, String)] = [
            ("refreshSeconds",     "usage.refreshSeconds"),
            ("floatingPlacement",  "usage.desk.placement"),
            ("floatingVisible",    "usage.desk.visible"),
            ("floatingTopLeft",    "usage.desk.topLeft"),
        ]
        for (old, new) in moves where d.object(forKey: new) == nil {
            if let v = d.object(forKey: old) { d.set(v, forKey: new) }
        }
        if let legacyPercent = d.object(forKey: "showPercentInMenuBar") as? Bool,
           d.object(forKey: "showTextInMenuBar") == nil {
            d.set(legacyPercent, forKey: "showTextInMenuBar")
        }
        // The old desktop window was the full readout; keep it that way.
        if d.object(forKey: "usage.desk.size") == nil {
            d.set(GlanceSize.full.rawValue, forKey: "usage.desk.size")
        }
        d.set(true, forKey: "didMigrateToGlances")
    }
}
