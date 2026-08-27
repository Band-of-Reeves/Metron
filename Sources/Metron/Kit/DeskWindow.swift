import SwiftUI
import AppKit

// MARK: - The panel

/// A borderless panel that drags from anywhere on its face, the way a real
/// desktop widget does.
///
/// `isMovableByWindowBackground` is not enough here: the whole face is an
/// `NSHostingView`, which claims mouse-down before AppKit's background-drag
/// path ever runs — which is why the window used to feel nailed to whichever
/// display it opened on. Intercepting `.leftMouseDragged` in `sendEvent` moves
/// it in global screen coordinates instead, so it crosses onto an extended
/// display like any other window. Clicks still reach SwiftUI: only the drag is
/// swallowed, and only once it passes a small threshold, so buttons keep working.
final class DeskPanel: NSPanel {
    private var dragOrigin: NSPoint?
    private var frameAtDragStart: NSRect?
    private var dragging = false

    /// Called after a user drag settles, so the controller can persist it.
    var onMoved: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragOrigin = NSEvent.mouseLocation
            frameAtDragStart = frame
            dragging = false

        case .leftMouseDragged:
            if let start = dragOrigin, let f = frameAtDragStart {
                let p = NSEvent.mouseLocation
                let dx = p.x - start.x, dy = p.y - start.y
                if dragging || abs(dx) + abs(dy) > 3 {
                    dragging = true
                    setFrameOrigin(NSPoint(x: f.origin.x + dx, y: f.origin.y + dy))
                    return  // swallow: SwiftUI must not also see this as a drag
                }
            }

        case .leftMouseUp:
            let wasDragging = dragging
            dragOrigin = nil
            frameAtDragStart = nil
            dragging = false
            if wasDragging {
                onMoved?()
                return  // the press was a drag, not a click on whatever is under it
            }

        default:
            break
        }
        super.sendEvent(event)
    }
}

// MARK: - Placement

/// Where a desk window sits in the window stack.
enum DeskPlacement: String, CaseIterable {
    case onTop, onDesktop

    var title: String {
        switch self {
        case .onTop:     return "On top of other windows"
        case .onDesktop: return "Behind other windows"
        }
    }

    var level: NSWindow.Level {
        switch self {
        case .onTop:     return .floating
        case .onDesktop: return NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }
}

extension NSScreen {
    /// Stable-enough key for remembering which display a window was parked on.
    /// Display IDs get reassigned when displays are re-attached; the name does not.
    var placementKey: String { localizedName }
}

// MARK: - One window per glance

/// Owns a single glance's desk window: its size class, its position, and the
/// display it belongs to.
@MainActor
final class DeskWindowController: NSObject, NSWindowDelegate {
    private let store: GlanceStore
    private var panel: DeskPanel?
    private var sizeObserver: NSObjectProtocol?

    init(store: GlanceStore) {
        self.store = store
        super.init()
    }

    // MARK: Stored settings

    private func key(_ suffix: String) -> String { "\(store.id).desk.\(suffix)" }

    var isVisible: Bool { panel?.isVisible ?? false }

    var size: GlanceSize {
        get {
            GlanceSize(rawValue: UserDefaults.standard.string(forKey: key("size")) ?? "")
                ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key("size"))
            rebuild()
        }
    }

    var placement: DeskPlacement {
        get {
            DeskPlacement(rawValue: UserDefaults.standard.string(forKey: key("placement")) ?? "")
                ?? .onTop
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key("placement"))
            panel?.level = newValue.level
        }
    }

    // MARK: Show / hide

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { build() }
        panel?.level = placement.level
        restorePosition()
        panel?.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: key("visible"))
    }

    func hide() {
        panel?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: key("visible"))
    }

    /// Re-show on launch if it was open when the app last quit.
    func restoreIfNeeded() {
        if UserDefaults.standard.bool(forKey: key("visible")) { show() }
    }

    private func rebuild() {
        let wasVisible = isVisible
        savePosition()
        if let observer = sizeObserver { NotificationCenter.default.removeObserver(observer) }
        sizeObserver = nil
        panel?.orderOut(nil)
        panel = nil
        if wasVisible { show() }
    }

    // MARK: Building

    private func build() {
        let size = self.size
        let root = DeskCard(store: store, size: size, controller: self)
        let hosting = NSHostingView(rootView: AnyView(root))

        let initial = size.dimensions ?? hosting.fittingSize
        let p = DeskPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.delegate = self
        p.contentView = hosting
        p.onMoved = { [weak self] in self?.savePosition() }

        if let d = size.dimensions {
            hosting.frame = NSRect(origin: .zero, size: d)
            p.setContentSize(d)
        } else {
            // Let the hosting view's intrinsic size drive the window, so a
            // `.full` panel that grows when data lands takes the window with it.
            hosting.translatesAutoresizingMaskIntoConstraints = false
            p.setContentSize(hosting.fittingSize)
            // A `.full` panel grows once data lands; keep its top-left put
            // rather than letting the window grow upward off the screen.
            hosting.postsFrameChangedNotifications = true
            sizeObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: hosting,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel else { return }
                    let top = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
                    panel.setFrameTopLeftPoint(self.savedTopLeft ?? top)
                    self.clampOnScreen()
                }
            }
        }
        panel = p
        restorePosition()
    }

    // MARK: Position

    private var savedTopLeft: NSPoint? {
        UserDefaults.standard.string(forKey: key("topLeft")).map(NSPointFromString)
    }

    private func savePosition() {
        guard let p = panel else { return }
        let topLeft = NSPoint(x: p.frame.minX, y: p.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: key("topLeft"))
        if let screen = hostScreen(for: p.frame) {
            UserDefaults.standard.set(screen.placementKey, forKey: key("display"))
        }
    }

    private func restorePosition() {
        guard let p = panel else { return }
        let wantedDisplay = UserDefaults.standard.string(forKey: key("display"))
        let displayAttached = wantedDisplay == nil
            || NSScreen.screens.contains { $0.placementKey == wantedDisplay }

        if let topLeft = savedTopLeft, displayAttached {
            p.setFrameTopLeftPoint(topLeft)
        } else {
            p.setFrameTopLeftPoint(defaultTopLeft(for: p.frame.size))
        }
        clampOnScreen()
    }

    /// The screen holding most of `frame`, or nil when it holds none.
    private func hostScreen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens
            .filter { $0.frame.intersects(frame) }
            .max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
    }

    private func defaultTopLeft(for size: NSSize) -> NSPoint {
        // Prefer the screen carrying the menu bar — for a menu-bar-only app,
        // NSScreen.main at launch is whichever display happened to be active,
        // which lands the window unpredictably.
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return NSPoint(x: 60, y: 400) }
        // Stagger multiple widgets so they don't stack exactly on each other.
        let n = CGFloat(DeskWindowManager.shared.openIndex(of: store.id))
        return NSPoint(x: f.maxX - size.width - 24 - n * 18,
                       y: f.maxY - 24 - n * 18)
    }

    /// Keeps the window reachable when the display it was parked on goes away.
    func clampOnScreen() {
        guard let p = panel else { return }
        let frame = p.frame
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            p.setFrameTopLeftPoint(defaultTopLeft(for: frame.size))
            UserDefaults.standard.removeObject(forKey: key("topLeft"))
            UserDefaults.standard.removeObject(forKey: key("display"))
            return
        }
        guard let vf = hostScreen(for: frame)?.visibleFrame else { return }
        var o = frame.origin
        o.x = min(max(o.x, vf.minX), vf.maxX - frame.width)
        o.y = min(max(o.y, vf.minY), vf.maxY - frame.height)
        if o != frame.origin { p.setFrameOrigin(o) }
    }

    /// Menu path for the case where dragging across displays is awkward —
    /// a mirrored arrangement, or a widget parked behind other windows.
    func move(to screen: NSScreen) {
        guard let p = panel else { return }
        let vf = screen.visibleFrame
        let size = p.frame.size
        p.setFrameTopLeftPoint(NSPoint(x: vf.maxX - size.width - 24, y: vf.maxY - 24))
        clampOnScreen()
        savePosition()
    }

    func windowDidMove(_ notification: Notification) { savePosition() }
}

private extension NSRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

// MARK: - Manager

/// Holds one controller per glance, and answers "which desk windows are open".
@MainActor
final class DeskWindowManager {
    static let shared = DeskWindowManager()
    private var controllers: [String: DeskWindowController] = [:]

    func controller(for store: GlanceStore) -> DeskWindowController {
        if let existing = controllers[store.id] { return existing }
        let c = DeskWindowController(store: store)
        controllers[store.id] = c
        return c
    }

    /// Position in the stagger order, so two widgets opened at once don't land
    /// exactly on top of each other.
    func openIndex(of id: String) -> Int {
        controllers.keys.sorted().firstIndex(of: id) ?? 0
    }

    func clampAll() { controllers.values.forEach { $0.clampOnScreen() } }
}
