import SwiftUI
import AppKit

/// The chrome around a glance on the desktop.
///
/// At `.small`/`.medium`/`.large` this is a widget: a rounded, translucent
/// card with no title bar and no visible controls until you point at it —
/// the same restraint the system's own desktop widgets show. At `.full` the
/// glance draws its own chrome and this gets out of the way.
struct DeskCard: View {
    @ObservedObject var store: GlanceStore
    let size: GlanceSize
    let controller: DeskWindowController

    @State private var hovering = false

    var body: some View {
        Group {
            if size == .full {
                store.content(.full)
                    .background(
                        RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                    .fixedSize()
            } else {
                widgetCard
            }
        }
        .environment(\.glanceChrome, .desk)
        .onHover { hovering = $0 }
    }

    private var widgetCard: some View {
        ZStack(alignment: .topTrailing) {
            store.content(size)
                .padding(size.padding)
                .frame(width: size.dimensions?.width, height: size.dimensions?.height)

            if hovering {
                hoverControls
                    .padding(7)
                    .transition(.opacity)
            }
        }
        .frame(width: size.dimensions?.width, height: size.dimensions?.height)
        .background(
            RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.14), value: hovering)
    }

    private var hoverControls: some View {
        HStack(spacing: 3) {
            Menu {
                GlanceMenu(store: store, controller: controller, showsDeskToggle: false)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 20, height: 18)

            Button {
                controller.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Hide this widget")
        }
        .foregroundStyle(Theme.subtle)
        .padding(.horizontal, 2)
        .background(
            Capsule().fill(.thinMaterial)
        )
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

/// Where a glance's content is being drawn, for the few places it matters.
enum GlanceChrome {
    case popover, desk, render
}

private struct GlanceChromeKey: EnvironmentKey {
    static let defaultValue = GlanceChrome.popover
}

extension EnvironmentValues {
    var glanceChrome: GlanceChrome {
        get { self[GlanceChromeKey.self] }
        set { self[GlanceChromeKey.self] = newValue }
    }
}

/// The settings menu, shared by the menu bar popover and the desk widget.
struct GlanceMenu: View {
    @ObservedObject var store: GlanceStore
    let controller: DeskWindowController
    var showsDeskToggle = true

    var body: some View {
        store.menuExtras()

        Picker("Refresh every", selection: Binding(
            get: { store.refreshSeconds },
            set: { store.refreshSeconds = $0 }
        )) {
            ForEach(type(of: store).refreshChoices, id: \.self) { s in
                Text(intervalLabel(s)).tag(s)
            }
        }

        Divider()

        if showsDeskToggle {
            Button(controller.isVisible ? "Hide desktop widget" : "Show desktop widget") {
                controller.toggle()
            }
        }

        Picker("Widget size", selection: Binding(
            get: { controller.size },
            set: { controller.size = $0 }
        )) {
            ForEach(GlanceSize.allCases) { s in Text(s.title).tag(s) }
        }

        Picker("Widget sits", selection: Binding(
            get: { controller.placement },
            set: { controller.placement = $0 }
        )) {
            ForEach(DeskPlacement.allCases, id: \.self) { p in Text(p.title).tag(p) }
        }

        if NSScreen.screens.count > 1 {
            Menu("Move widget to") {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                    Button(screen.localizedName) {
                        if !controller.isVisible { controller.show() }
                        controller.move(to: screen)
                    }
                }
            }
        }
    }

    private func intervalLabel(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "\(seconds) seconds"
        case 60:    return "1 minute"
        case ..<3600: return "\(seconds / 60) minutes"
        default:    return "\(seconds / 3600) hours"
        }
    }
}

/// The app-wide items every glance's menu ends with.
struct AppMenuItems: View {
    @ObservedObject var registry: GlanceRegistry
    @Binding var loginItemError: String?

    var body: some View {
        Menu("Glances") {
            ForEach(registry.all, id: \.id) { glance in
                Toggle(glance.name, isOn: Binding(
                    get: { registry.isEnabled(glance.id) },
                    set: { registry.setEnabled(glance.id, $0) }
                ))
            }
        }
        Toggle("Show reading in menu bar", isOn: Binding(
            get: { registry.showTextInMenuBar },
            set: { registry.showTextInMenuBar = $0 }
        ))
        Toggle("Launch at login", isOn: Binding(
            get: { LoginItem.isEnabled },
            set: { loginItemError = LoginItem.set($0) }
        ))
        Divider()
        Button("Quit Metron") { NSApplication.shared.terminate(nil) }
    }
}
