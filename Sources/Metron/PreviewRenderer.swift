import SwiftUI
import AppKit

/// `Metron --render <path.png> [--scale N]` renders the panel with live data
/// and exits. Used for design review and for the README shot — the panel is a
/// menu bar popover, which screen capture can't reliably reach.
@MainActor
enum PreviewRenderer {

    static func run(arguments: [String]) -> Never {
        let path = argument(after: "--render", in: arguments) ?? "metron-panel.png"
        let scale = argument(after: "--scale", in: arguments).flatMap(Double.init) ?? 2.0
        let appearanceName: NSAppearance.Name =
            arguments.contains("--light") ? .aqua : .darkAqua
        NSApplication.shared.appearance = NSAppearance(named: appearanceName)

        let store = UsageStore()
        // Bridge the async refresh into this synchronous entry point.
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await store.refresh()
            done.signal()
        }
        while done.wait(timeout: .now() + 0.02) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let floating = arguments.contains("--floating")
        let view = Group {
            if floating {
                FloatingPanelView(store: store)
                    .environment(\.floatingPanelChrome, true)
                    .padding(22)
            } else {
                PanelView(store: store)
            }
        }
            .environment(\.colorScheme, appearanceName == .darkAqua ? .dark : .light)
            .background(appearanceName == .darkAqua
                        ? Color(red: 0.12, green: 0.12, blue: 0.13)
                        : Color(red: 0.96, green: 0.96, blue: 0.97))

        let png: Data
        let renderedSize: CGSize

        if arguments.contains("--window") {
            // Render through real AppKit so controls that ImageRenderer can't
            // handle (Menu, materials) are exercised the way they actually ship.
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.backgroundColor = .clear
            window.isOpaque = false
            window.orderFrontRegardless()
            // Give layout and material rendering a few passes to settle.
            for _ in 0..<8 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                FileHandle.standardError.write(Data("window render failed\n".utf8))
                exit(1)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("png encode failed\n".utf8))
                exit(1)
            }
            png = data
            renderedSize = hosting.bounds.size
            window.orderOut(nil)
        } else {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("render failed\n".utf8))
                exit(1)
            }
            png = data
            renderedSize = image.size
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(Int(renderedSize.width))x\(Int(renderedSize.height)) pt)")
            if let err = store.usage.error {
                print("note: \(err)")
            }
            print("windows: \(store.usage.windows.map { "\($0.label)=\(Int($0.percent))%" }.joined(separator: " "))")
            print("history days with data: \(store.history.days.count), peak \(store.history.peakDayTotal)")
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    private static func argument(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        return v.hasPrefix("--") ? nil : v
    }
}
