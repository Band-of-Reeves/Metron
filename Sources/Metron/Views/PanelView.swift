import SwiftUI

struct PanelView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.floatingPanelChrome) private var isFloating

    private let width: CGFloat = 344

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let err = store.usage.error, store.usage.windows.isEmpty {
                errorBlock(err)
            } else {
                ringRow
            }

            divider
            section("Activity", trailing: "last 18 weeks") {
                HeatmapView(history: store.history)
            }

            if !store.history.modelTotalsThisWeek.isEmpty {
                divider
                section("Models", trailing: "this week, by output") {
                    ModelBreakdown(totals: store.history.modelTotalsThisWeek)
                }
            }

            if store.usage.day.requests > 0 {
                divider
                section("Drivers", trailing: "last 24h") {
                    DriverChips(drivers: store.usage.day)
                }
            }

            divider
            footer
        }
        .frame(width: width)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Metron")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(planLine)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
            Spacer()
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

            if isFloating {
                Button {
                    FloatingPanelController.shared.hide()
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

    private var planLine: String {
        if store.usage.planNote.contains("subscription") { return "Subscription plan" }
        if !store.usage.planNote.isEmpty { return store.usage.planNote }
        return "Claude Code usage"
    }

    // MARK: - Rings

    private var ringRow: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(store.usage.windows) { w in
                RingGauge(window: w, now: store.now)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private func errorBlock(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warn)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Sections

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    private func section<Content: View>(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(Theme.subtle)
                }
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(store.loginItemError ?? updatedLine)
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(store.loginItemError == nil ? Theme.subtle : Theme.warn)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Menu {
                Picker("Refresh every", selection: $store.refreshSeconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                }
                Toggle("Show percentage in menu bar", isOn: $store.showPercentInMenuBar)
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { store.loginItemError = LoginItem.set($0) }
                ))
                Divider()
                Button(FloatingPanelController.shared.isVisible
                       ? "Hide desktop window" : "Show desktop window") {
                    FloatingPanelController.shared.toggle(store: store)
                }
                Picker("Desktop window sits", selection: $store.floatingPlacement) {
                    Text("On top of other windows").tag("onTop")
                    Text("Behind other windows").tag("onDesktop")
                }
                Divider()
                Button("Quit Metron") { NSApplication.shared.terminate(nil) }
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

    private var updatedLine: String {
        guard store.usage.fetchedAt != .distantPast else { return "Loading…" }
        let ago = store.now.timeIntervalSince(store.usage.fetchedAt)
        return ago < 60 ? "Updated just now" : "Updated \(compactDuration(ago)) ago"
    }
}
