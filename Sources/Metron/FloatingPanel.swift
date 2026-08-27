import SwiftUI
import AppKit

/// A borderless, draggable panel that keeps the same readout on the desktop,
/// for when the menu bar popover isn't where you want to look.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelController()

    private var panel: NSPanel?
    private var store: UsageStore?
    private var sizeObserver: NSObjectProtocol?

    /// `.floating` sits above ordinary windows; `.desktop` tucks it behind them
    /// so it reads as wallpaper furniture.
    enum Placement: String {
        case onTop, onDesktop

        var level: NSWindow.Level {
            switch self {
            case .onTop: return .floating
            case .onDesktop: return NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            }
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(store: UsageStore) {
        if isVisible { hide() } else { show(store: store) }
    }

    func show(store: UsageStore) {
        self.store = store
        if panel == nil { build(store: store) }
        applyPlacement()
        clampOnScreen()
        panel?.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "floatingVisible")
    }

    func hide() {
        panel?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: "floatingVisible")
    }

    func applyPlacement() {
        let raw = UserDefaults.standard.string(forKey: "floatingPlacement") ?? Placement.onTop.rawValue
        panel?.level = (Placement(rawValue: raw) ?? .onTop).level
    }

    /// Re-show on launch if it was open when the app last quit.
    func restoreIfNeeded(store: UsageStore) {
        if UserDefaults.standard.bool(forKey: "floatingVisible") {
            show(store: store)
        }
    }

    private func build(store: UsageStore) {
        let content = FloatingPanelView(store: store)
            .environment(\.floatingPanelChrome, true)

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 640),
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
        p.setContentSize(hosting.fittingSize)

        // Restore the last position, or park it near the top-right.
        let topLeft = UserDefaults.standard.string(forKey: "floatingTopLeft")
            .map(NSPointFromString)
            ?? Self.defaultTopLeft(for: p.frame.size)
        p.setFrameTopLeftPoint(topLeft)
        panel = p

        // The content grows once usage data lands; keep the top edge put.
        hosting.postsFrameChangedNotifications = true
        sizeObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let desired = UserDefaults.standard.string(forKey: "floatingTopLeft")
                    .map(NSPointFromString)
                    ?? NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
                panel.setFrameTopLeftPoint(desired)
                self.clampOnScreen()
            }
        }
        clampOnScreen()
    }

    /// Top-left corner of the default parking spot.
    private static func defaultTopLeft(for size: NSSize) -> NSPoint {
        // Prefer the screen carrying the menu bar (screens.first) — for a
        // menu-bar-only app, NSScreen.main at launch is whichever display
        // happened to be active, which lands the window unpredictably.
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return NSPoint(x: 60, y: 400) }
        return NSPoint(x: f.maxX - size.width - 24, y: f.maxY - 24)
    }

    /// Keeps the panel reachable when the display it was parked on goes away,
    /// or when a saved origin no longer lands on any attached screen.
    func clampOnScreen() {
        guard let p = panel else { return }
        let frame = p.frame
        let fitsSomewhere = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !fitsSomewhere {
            p.setFrameTopLeftPoint(Self.defaultTopLeft(for: frame.size))
            UserDefaults.standard.removeObject(forKey: "floatingTopLeft")
            return
        }
        // Nudge it fully inside whichever screen holds most of it.
        let host = NSScreen.screens.max {
            $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
        }
        guard let vf = host?.visibleFrame else { return }
        var o = frame.origin
        o.x = min(max(o.x, vf.minX), vf.maxX - frame.width)
        o.y = min(max(o.y, vf.minY), vf.maxY - frame.height)
        if o != frame.origin { p.setFrameOrigin(o) }
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel else { return }
        let topLeft = NSPoint(x: p.frame.minX, y: p.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: "floatingTopLeft")
    }
}

/// Marks the panel as the detached variant so it can draw its own background.
private struct FloatingPanelChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var floatingPanelChrome: Bool {
        get { self[FloatingPanelChromeKey.self] }
        set { self[FloatingPanelChromeKey.self] = newValue }
    }
}

/// The panel content with its own rounded, opaque-ish chrome — a detached
/// window doesn't get the popover's material backdrop for free.
struct FloatingPanelView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        PanelView(store: store)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fixedSize()
    }
}


private extension NSRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
