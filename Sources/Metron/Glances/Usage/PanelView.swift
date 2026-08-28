import SwiftUI

/// The full Claude-usage readout: the menu bar popover, and the `.full` desk
/// window for anyone who wants everything at once.
///
/// The header used to read "Metron", from when the app was only this panel.
/// Metron is now the thing hosting four readouts, so its name belongs where
/// the app is identified — Quit, the login item, the bundle — and each panel
/// carries the name of the glance it actually is.
struct PanelView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(store: store)

            if let err = store.usage.error, store.usage.windows.isEmpty {
                PanelError(message: err)
            } else {
                ringRow
                if store.usage.isStale, let err = store.usage.error {
                    staleNote(err)
                }
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

    /// Shown under the rings when the numbers above are a kept reading.
    private func staleNote(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9.5))
            Text(message)
                .font(Theme.rounded(9.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.warn)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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
