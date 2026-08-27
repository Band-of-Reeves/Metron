import SwiftUI
import AppKit
import Combine

/// One status item per enabled glance.
///
/// Metron used a single SwiftUI `MenuBarExtra`, which cannot be added or
/// removed while the app runs. Managing `NSStatusItem`s directly is what lets
/// a glance be turned on and off from the menu — and it keeps each glance in
/// its own fixed slot, which is the whole point of reading them at a glance.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var items: [String: NSStatusItem] = [:]
    private var popovers: [String: NSPopover] = [:]
    private var storeSubs: [String: AnyCancellable] = [:]
    private var registrySub: AnyCancellable?
    private let registry = GlanceRegistry.shared

    func start() {
        sync()
        registrySub = registry.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.sync() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { DeskWindowManager.shared.clampAll() }
        }
    }

    /// Adds and removes status items so they match the enabled glances.
    private func sync() {
        let wanted = registry.enabledStores
        let wantedIDs = Set(wanted.map(\.id))

        for (id, item) in items where !wantedIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
            popovers[id] = nil
            storeSubs[id] = nil
        }

        for store in wanted where items[store.id] == nil {
            add(store)
        }
        for store in wanted { redraw(store) }
    }

    private func add(_ store: GlanceStore) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.identifier = NSUserInterfaceItemIdentifier(store.id)
        item.button?.toolTip = store.name
        items[store.id] = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: AnyView(
                GlancePopover(store: store)
                    .environment(\.glanceChrome, .popover)
            )
        )
        popovers[store.id] = popover

        // Redraw the glyph whenever this glance publishes anything.
        storeSubs[store.id] = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak store] _ in
                guard let store else { return }
                self?.redraw(store)
            }

        redraw(store)
    }

    private func redraw(_ store: GlanceStore) {
        items[store.id]?.button?.image = MenuBarIcon.image(
            headline: store.headline,
            symbol: store.symbol,
            showText: registry.showTextInMenuBar
        )
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue,
              let popover = popovers[id] else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // A transient popover on an accessory app needs the window pulled
            // forward or it can open behind whatever was frontmost.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// What drops down from a glance's menu bar item: its full readout.
struct GlancePopover: View {
    @ObservedObject var store: GlanceStore

    var body: some View {
        store.content(.full)
    }
}
