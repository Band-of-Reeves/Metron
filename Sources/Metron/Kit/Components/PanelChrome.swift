import SwiftUI
import AppKit

/// The `.full` panel look, factored out of Metron's original usage panel so
/// every glance gets the same header, rules, section headings and footer
/// without re-deriving them.
enum Panel {
    static let width: CGFloat = 344
}

struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

struct PanelHeader: View {
    @ObservedObject var store: GlanceStore
    /// Shown instead of the glance name when a glance wants its own title.
    var title: String?
    var subtitle: String?

    @Environment(\.glanceChrome) private var chrome

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title ?? store.name)
                    .font(Theme.rounded(14, .semibold))
                Text(subtitle ?? store.subtitle)
                    .font(Theme.rounded(10))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
            Spacer()
            RefreshButton(store: store)

            if chrome == .desk {
                Button {
                    DeskWindowManager.shared.controller(for: store).hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.subtle)
                }
                .buttonStyle(.plain)
                .help("Close the desktop window")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }
}

struct RefreshButton: View {
    @ObservedObject var store: GlanceStore

    var body: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.isRefreshing ? Theme.subtle : .primary)
                .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                .animation(
                    store.isRefreshing
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .default,
                    value: store.isRefreshing
                )
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing)
        .help("Refresh now")
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, trailing: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.rounded(11, .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Theme.rounded(9.5))
                        .foregroundStyle(Theme.subtle)
                }
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// "Updated 2m ago" on the left, the settings menu on the right.
struct GlanceFooter: View {
    @ObservedObject var store: GlanceStore
    @ObservedObject var registry: GlanceRegistry = .shared

    var body: some View {
        HStack(spacing: 10) {
            Text(registry.loginItemError ?? store.updatedLine)
                .font(Theme.rounded(9.5))
                .foregroundStyle(registry.loginItemError == nil ? Theme.subtle : Theme.warn)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Menu {
                GlanceMenu(store: store,
                           controller: DeskWindowManager.shared.controller(for: store))
                Divider()
                AppMenuItems(registry: registry, loginItemError: $registry.loginItemError)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

/// A one-line problem report in the body of a panel.
struct PanelError: View {
    let message: String
    var symbol = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.warn)
                .font(.system(size: 12))
            Text(message)
                .font(Theme.rounded(11))
                .foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

/// Header row for the small widget sizes: symbol, name, and nothing else.
struct WidgetHeader: View {
    let symbol: String
    let title: String
    var tint: Color = Theme.subtle
    var trailing: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.rounded(10.5, .semibold))
                .foregroundStyle(Theme.subtle)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
        }
    }
}
