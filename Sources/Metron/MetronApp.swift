import SwiftUI
import AppKit

/// Metron is a menu bar app with no windows of its own, so it runs on a plain
/// `NSApplication` with an accessory activation policy rather than a SwiftUI
/// `App` scene: the number of menu bar items changes at runtime, and SwiftUI's
/// `MenuBarExtra` scenes are fixed at compile time.
@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--render") {
            MainActor.assumeIsolated { PreviewRenderer.run(arguments: args) }
        }
        if args.contains("--measure") {
            MainActor.assumeIsolated { PreviewRenderer.measure() }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            GlanceRegistry.shared.activate()
            MenuBarController.shared.start()
        }
    }
}
