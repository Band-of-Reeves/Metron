import SwiftUI
import AppKit

/// `Metron --render <path.png> [--glance id] [--size small|medium|large|full]`
/// renders a glance with live data and exits.
///
/// Menu bar popovers and borderless desk widgets are both awkward to screen
/// capture, so design review goes through here instead.
@MainActor
enum PreviewRenderer {

    static func run(arguments: [String]) -> Never {
        let path = argument(after: "--render", in: arguments) ?? "metron-panel.png"
        let scale = argument(after: "--scale", in: arguments).flatMap(Double.init) ?? 2.0
        let glanceID = argument(after: "--glance", in: arguments) ?? "usage"
        let size = GlanceSize(rawValue: argument(after: "--size", in: arguments) ?? "full") ?? .full
        let appearanceName: NSAppearance.Name = arguments.contains("--light") ? .aqua : .darkAqua
        NSApplication.shared.appearance = NSAppearance(named: appearanceName)

        let registry = GlanceRegistry.shared
        guard let store = registry.store(glanceID) else {
            FileHandle.standardError.write(Data(
                "unknown glance '\(glanceID)' — try: \(registry.all.map(\.id).joined(separator: ", "))\n".utf8))
            exit(2)
        }

        // Bridge the async refresh into this synchronous entry point. Rate
        // metrics need two samples to mean anything, so take a second reading.
        settle(store: store, extraSamples: store is SystemStore ? 2 : 0)

        let body = Group {
            if size == .full {
                store.content(.full)
                    .environment(\.glanceChrome, .render)
            } else {
                DeskCard(store: store, size: size,
                         controller: DeskWindowManager.shared.controller(for: store))
                    .padding(22)
            }
        }
            .environment(\.colorScheme, appearanceName == .darkAqua ? .dark : .light)
            .background(appearanceName == .darkAqua
                        ? Color(red: 0.12, green: 0.12, blue: 0.13)
                        : Color(red: 0.96, green: 0.96, blue: 0.97))

        let (png, renderedSize) = render(body, scale: scale,
                                         throughAppKit: arguments.contains("--window"))

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) — \(store.id)/\(size.rawValue) "
                  + "\(Int(renderedSize.width))x\(Int(renderedSize.height)) pt")
            if let err = store.error { print("note: \(err)") }
            if let h = store.headline {
                print("headline: \(h.text ?? "—") "
                      + (h.fraction.map { "(\(Int($0 * 100))%)" } ?? "(no ring)"))
            }
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    /// `Metron --measure` checks that a popover ends up the same size as the
    /// panel inside it, before and after data lands. A menu bar popover cannot
    /// be screenshotted from a headless run, so this is how that regression
    /// gets caught.
    static func measure() -> Never {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        var worst = 0.0

        for store in GlanceRegistry.shared.all {
            let popover = NSPopover()
            let host = PopoverHost(
                rootView: AnyView(
                    GlancePopover(store: store).environment(\.glanceChrome, .popover)
                )
            )
            host.popover = popover
            popover.contentViewController = host
            host.view.layoutSubtreeIfNeeded()
            host.syncSize()
            let empty = popover.contentSize.height

            // Katechon's ssh probe is slow and offline here; the point of the
            // check is the growth, which every glance shows.
            if store.id != "katechon" {
                settle(store: store, extraSamples: store is SystemStore ? 1 : 0)
            }
            host.view.layoutSubtreeIfNeeded()
            host.syncSize()

            let ideal = host.sizeThatFits(in: CGSize(width: Panel.width,
                                                     height: .greatestFiniteMagnitude))
            let bare = NSHostingView(rootView: AnyView(store.content(.full))).fittingSize

            // Actually open it, against an offscreen anchor, and read back the
            // height the hosting view really got. Comparing that with the
            // panel's own height is the whole test: they differ exactly when
            // the popover clips.
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 120, height: 40),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
            window.contentView?.addSubview(anchor)
            window.orderFrontRegardless()
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            for _ in 0..<10 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            let shown = host.view.frame.height
            popover.performClose(nil)
            window.orderOut(nil)

            let drift2 = max(abs(bare.height - popover.contentSize.height),
                             abs(bare.height - shown))
            let drift = max(abs(ideal.height - popover.contentSize.height), drift2)
            worst = max(worst, drift)
            print(String(format: "%-9@  empty %4.0f -> loaded %4.0f   panel %4.0f   shown %4.0f   drift %.1f",
                         store.id as NSString, empty,
                         popover.contentSize.height, bare.height, shown, drift))
        }

        print(worst < 1 ? "ok: every popover matches its panel"
                        : "FAIL: popover is \(Int(worst))pt off its panel")
        exit(worst < 1 ? 0 : 1)
    }

    /// Runs the run loop until the store has data, plus any extra samples a
    /// rate-based glance needs before its numbers are meaningful.
    private static func settle(store: GlanceStore, extraSamples: Int) {
        for i in 0...extraSamples {
            let done = DispatchSemaphore(value: 0)
            Task { @MainActor in
                await store.refresh()
                done.signal()
            }
            let deadline = Date().addingTimeInterval(20)
            while done.wait(timeout: .now() + 0.02) == .timedOut, Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            if i < extraSamples {
                let pause = Date().addingTimeInterval(0.6)
                while Date() < pause {
                    RunLoop.current.run(mode: .default, before: pause)
                }
            }
        }
    }

    private static func render<V: View>(_ view: V, scale: Double,
                                        throughAppKit: Bool) -> (Data, CGSize) {
        if throughAppKit {
            // Render through real AppKit so controls ImageRenderer can't handle
            // (Menu, materials) are exercised the way they actually ship.
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = hosting
            window.backgroundColor = .clear
            window.isOpaque = false
            window.orderFrontRegardless()
            for _ in 0..<8 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                fail("window render failed")
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                fail("png encode failed")
            }
            window.orderOut(nil)
            return (data, hosting.bounds.size)
        }

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            fail("render failed")
        }
        return (data, image.size)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }

    private static func argument(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        return v.hasPrefix("--") ? nil : v
    }
}
