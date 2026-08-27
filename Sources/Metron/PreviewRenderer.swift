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
