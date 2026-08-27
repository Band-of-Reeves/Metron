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
    private var hosts: [String: PopoverHost] = [:]
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
            hosts[id] = nil
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
        let host = PopoverHost(
            rootView: AnyView(
                GlancePopover(store: store)
                    .environment(\.glanceChrome, .popover)
            )
        )
        host.popover = popover
        popover.contentViewController = host
        popovers[store.id] = popover
        hosts[store.id] = host

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

    /// How tall a popover may get on the display it will open over.
    private static func maxPopoverHeight(near button: NSStatusBarButton?) -> CGFloat {
        let screen = button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        return (screen?.visibleFrame.height ?? 900) - 24
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue,
              let popover = popovers[id] else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // The menu bar can be on a different display than last time, and
            // the panel may have grown since it was built. Re-measure first.
            hosts[id]?.maxHeight = Self.maxPopoverHeight(near: sender)
            hosts[id]?.syncSize()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // A transient popover on an accessory app needs the window pulled
            // forward or it can open behind whatever was frontmost.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// Keeps the popover the same size as the panel inside it.
///
/// `NSPopover` takes its content size once and does not follow the hosting
/// controller afterwards. Metron's panels are short at launch and grow as data
/// lands — and because `NSView` puts its origin at the bottom left, content
/// taller than the popover frame overflows off the **top**, which is why the
/// header and the rings were the parts that disappeared.
final class PopoverHost: NSHostingController<AnyView> {
    weak var popover: NSPopover?
    /// Ceiling for the display this popover opens over.
    var maxHeight: CGFloat = 900

    override func viewDidLayout() {
        super.viewDidLayout()
        syncSize()
    }

    func syncSize() {
        guard let popover else { return }
        let ideal = sizeThatFits(in: CGSize(width: Panel.width,
                                            height: .greatestFiniteMagnitude))
        let size = NSSize(width: Panel.width,
                          height: min(max(ideal.height, 1), maxHeight))
        if popover.contentSize != size { popover.contentSize = size }
    }
}

/// What drops down from a glance's menu bar item: its full readout.
struct GlancePopover: View {
    @ObservedObject var store: GlanceStore

    var body: some View {
        // No `.frame(maxHeight:)` here: a max-height frame is a *flexible*
        // frame, so it grows to whatever is proposed and the panel would
        // report the ceiling as its size. The ceiling belongs in PopoverHost,
        // which clamps the popover frame instead of the content.
        store.content(.full)
    }
}
