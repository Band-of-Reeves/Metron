import SwiftUI

/// The full Claude-usage readout: the menu bar popover, and the `.full` desk
/// window for anyone who wants everything at once.
struct PanelView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(store: store, title: "Metron")

            if let err = store.usage.error, store.usage.windows.isEmpty {
                PanelError(message: err)
            } else {
                ringRow
            }

            PanelDivider()
            PanelSection("Activity", trailing: "last 18 weeks") {
                HeatmapView(history: store.history)
            }

            if !store.history.modelTotalsThisWeek.isEmpty {
                PanelDivider()
                PanelSection("Models", trailing: "this week, by output") {
                    ModelBreakdown(totals: store.history.modelTotalsThisWeek)
                }
            }

            if store.usage.day.requests > 0 {
                PanelDivider()
                PanelSection("Drivers", trailing: "last 24h") {
                    DriverChips(drivers: store.usage.day)
                }
            }

            PanelDivider()
            GlanceFooter(store: store)
        }
        .frame(width: Panel.width)
        .background(.ultraThinMaterial)
    }

    private var ringRow: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(store.usage.windows) { w in
                RingGauge(window: w, now: store.now)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }
}
