import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--render") {
            MainActor.assumeIsolated { PreviewRenderer.run(arguments: args) }
        }
        MetronApp.main()
    }
}

struct MetronApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            Image(nsImage: MenuBarIcon.image(
                percent: store.headline?.percent,
                showPercent: store.showPercentInMenuBar,
                color: MenuBarIcon.nsColor(for: store.headline?.percent ?? 0)
            ))
        }
        .menuBarExtraStyle(.window)
    }
}
