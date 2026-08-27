import SwiftUI

/// One ring, big: whichever limit window is closest to its ceiling.
struct UsageSmall: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(symbol: store.symbol, title: "Claude", tint: Theme.accent)
            Spacer(minLength: 4)
            if let w = store.mostConstrained {
                PercentRing(
                    fraction: w.fraction,
                    label: w.label,
                    caption: countdown(w),
                    color: Theme.severity(w.percent),
                    size: 84,
                    lineWidth: 7
                )
            } else {
                UnavailableMark(text: store.usage.error == nil ? "Loading…" : "No reading")
            }
            Spacer(minLength: 2)
        }
    }

    private func countdown(_ w: LimitWindow) -> String? {
        guard let at = w.resetsAt else { return w.resetsRaw }
        let left = at.timeIntervalSince(store.now)
        return left > 0 ? "resets in \(compactDuration(left))" : "resetting"
    }
}

/// Every window the server reports, side by side.
struct UsageMedium: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(symbol: store.symbol, title: "Claude usage",
                         tint: Theme.accent, trailing: store.subtitle)
            Spacer(minLength: 6)
            if store.usage.windows.isEmpty {
                UnavailableMark(text: store.usage.error ?? "Loading…")
            } else {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(store.usage.windows) { w in
                        PercentRing(
                            fraction: w.fraction,
                            label: w.label,
                            caption: countdown(w),
                            color: Theme.severity(w.percent),
                            size: 62,
                            lineWidth: 5.5
                        )
                    }
                }
            }
            Spacer(minLength: 2)
        }
    }

    private func countdown(_ w: LimitWindow) -> String? {
        guard let at = w.resetsAt else { return w.resetsRaw }
        let left = at.timeIntervalSince(store.now)
        return left > 0 ? compactDuration(left) : "resetting"
    }
}

/// Rings, the activity heatmap and the model split — the whole week at once.
struct UsageLarge: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: store.symbol, title: "Claude usage",
                         tint: Theme.accent, trailing: store.subtitle)

            Spacer().frame(height: 10)

            if store.usage.windows.isEmpty {
                UnavailableMark(text: store.usage.error ?? "Loading…")
            } else {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(store.usage.windows) { w in
                        PercentRing(
                            fraction: w.fraction,
                            label: w.label,
                            caption: countdown(w),
                            color: Theme.severity(w.percent),
                            size: 58,
                            lineWidth: 5
                        )
                    }
                }
            }

            Spacer(minLength: 12)

            Text("ACTIVITY")
                .font(Theme.rounded(8.5, .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.subtle)
                .padding(.bottom, 6)
            HeatmapView(history: store.history, weeks: 18, cell: 9, gap: 3, showsLegend: false)

            if !store.history.modelTotalsThisWeek.isEmpty {
                Spacer(minLength: 12)
                Text("MODELS THIS WEEK")
                    .font(Theme.rounded(8.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.subtle)
                    .padding(.bottom, 6)
                ModelBreakdown(totals: store.history.modelTotalsThisWeek, compact: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func countdown(_ w: LimitWindow) -> String? {
        guard let at = w.resetsAt else { return w.resetsRaw }
        let left = at.timeIntervalSince(store.now)
        return left > 0 ? compactDuration(left) : "resetting"
    }
}

/// What a widget shows when there is nothing to show.
struct UnavailableMark: View {
    let text: String
    var symbol = "minus.circle"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.subtle)
            Text(text)
                .font(Theme.rounded(10))
                .foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
