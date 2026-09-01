import SwiftUI

/// The full Ledger readout.
///
/// The figures here are large enough that the panel's job is to be *checkable*,
/// not impressive. Every section names what it was computed from, and the
/// footer carries the pricing source and its fetch date. That footer is not
/// decoration — it is the reason a number this size is allowed on screen.
struct LedgerPanel: View {
    @ObservedObject var store: LedgerStore

    private var reading: LedgerReading { store.reading }
    private var window: LedgerReading.Window { store.window }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(store: store)

            if let err = store.error, reading.days.isEmpty {
                PanelError(message: err)
            } else {
                windowPicker
                tiles
                PanelDivider()
                PanelSection("Cost against work", trailing: chartCaption) {
                    CostAgainstWork(reading: reading, window: window)
                        .frame(height: 96)
                }
                PanelDivider()
                PanelSection("Models", trailing: "by cost") {
                    ModelTable(models: reading.models(in: window),
                               total: reading.cost(in: window))
                }
                if let output = reading.output, !output.byRepo.isEmpty {
                    PanelDivider()
                    PanelSection("Output", trailing: "lines filtered") {
                        RepoTable(repos: Array(output.byRepo.prefix(8)), output: output)
                    }
                }
                if let life = reading.lifetime {
                    PanelDivider()
                    PanelSection("Lifetime", trailing: "from stats-cache.json") {
                        LifetimeStrip(stats: life)
                    }
                }
                PanelDivider()
                provenance
            }

            PanelDivider()
            GlanceFooter(store: store)
        }
        .frame(width: Panel.width)
    }

    // MARK: -

    /// Mirrors the CLI's own stats screen, which is where this data lives.
    private var windowPicker: some View {
        Picker("", selection: Binding(get: { store.window },
                                      set: { store.window = $0 })) {
            ForEach(LedgerReading.Window.allCases) { w in
                Text(w == .allTime ? "All time" : "Last \(w.rawValue)").tag(w)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // AppKit sizes a segmented control to a fractional height, which left
        // the panel a point taller than the popover measured it — the exact
        // drift --measure exists to catch, and it caught this.
        .frame(height: 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: 10) {
            StatTile(label: "Equivalent API",
                     value: money(reading.cost(in: window)),
                     caption: "at published rates",
                     color: Theme.accent, valueSize: 22)
            StatTile(label: "Subscription",
                     value: money(reading.subscriptionPaid(in: window)),
                     caption: "actually paid",
                     valueSize: 22)
            StatTile(label: "Multiple",
                     value: reading.multiple(in: window).map {
                         $0 >= 10 ? "\(Int($0.rounded()))x" : String(format: "%.1fx", $0)
                     } ?? "—",
                     caption: "cost ÷ paid",
                     color: Theme.ok, valueSize: 22)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var chartCaption: String {
        let days = reading.days(in: window)
        guard let peak = days.max(by: { $0.cost < $1.cost }) else { return "no days" }
        return "peak \(money(peak.cost)) on \(dayLabel(peak.day))"
    }

    /// Where every number above came from, and how far to trust it.
    private var provenance: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(reading.isExact
                  ? "Exact: read from transcripts, with the cache-write TTL split."
                  : "Approximate: the stats roll-up fuses token classes.",
                  systemImage: reading.isExact ? "checkmark.seal" : "exclamationmark.triangle")
                .font(Theme.rounded(9.5))
                .foregroundStyle(reading.isExact ? Theme.ok : Theme.warn)
            Text("Rates from \(Pricing.source), read \(Pricing.fetched). "
                 + "Subscription compared against elapsed calendar time, not active days. "
                 + "Line counts exclude generated and vendored paths and are never a denominator.")
                .font(Theme.rounded(9))
                .foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Wrapped text at this width lands on a fractional height, and the
        // popover rounds it up while sizeThatFits rounds it down — a 1pt drift
        // that --measure fails on. The width here is fixed, so the wrap is
        // deterministic and a pinned height is honest rather than a fudge.
        .frame(height: 62, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Tables

private struct ModelTable: View {
    let models: [ModelCost]
    let total: Double

    var body: some View {
        VStack(spacing: 5) {
            ForEach(models) { m in
                HStack(spacing: 8) {
                    Text(m.shortName)
                        .font(Theme.rounded(10.5))
                        .frame(width: 68, alignment: .leading)
                        .lineLimit(1)
                    Text(compactTokens(m.tokens.total))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.subtle)
                        .frame(width: 52, alignment: .trailing)
                    GeometryReader { geo in
                        let frac = total > 0 ? m.cost / total : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Theme.track)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(m.isLocal ? Theme.ok.opacity(0.35) : Theme.accent)
                                .frame(width: max(2, geo.size.width * frac))
                        }
                    }
                    .frame(height: 7)
                    Text(m.isLocal ? "local" : money(m.cost))
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(m.isLocal ? Theme.ok : .primary)
                        .frame(width: 62, alignment: .trailing)
                    // An assumed price is flagged rather than quietly averaged in.
                    if m.confidence == .assumed || m.confidence == .tier {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.warn)
                            .help(m.confidence == .assumed
                                  ? "No published rate — priced at Opus rates"
                                  : "Matched by tier from the model name")
                    }
                }
            }
        }
    }
}

private struct RepoTable: View {
    let repos: [RepoOutput]
    let output: OutputStats

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("\(output.commits) commits")
                    .font(Theme.mono(11, .semibold))
                Text("· \(compactCount(output.filesChanged)) files · \(output.repos) repos "
                     + "· \(output.activeDays) days with commits")
                    .font(Theme.rounded(9.5))
                    .foregroundStyle(Theme.subtle)
                Spacer()
            }
            .padding(.bottom, 2)

            ForEach(repos) { r in
                HStack(spacing: 8) {
                    Text(r.name)
                        .font(Theme.rounded(10))
                        .frame(width: 110, alignment: .leading)
                        .lineLimit(1)
                    Text("\(r.commits)")
                        .font(Theme.mono(10, .medium))
                        .frame(width: 34, alignment: .trailing)
                    Text("+\(compactCount(r.insertions))")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ok)
                        .frame(width: 62, alignment: .trailing)
                    Text("−\(compactCount(r.deletions))")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.crit.opacity(0.8))
                        .frame(width: 54, alignment: .trailing)
                    Spacer()
                }
            }
        }
    }
}

private struct LifetimeStrip: View {
    let stats: LifetimeStats

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatTile(label: "Sessions", value: compactCount(stats.totalSessions),
                     valueSize: 15, alignment: .leading)
            StatTile(label: "Messages", value: compactCount(stats.totalMessages),
                     valueSize: 15, alignment: .leading)
            StatTile(label: "Longest",
                     value: compactDuration(stats.longestSessionSeconds),
                     caption: "\(compactCount(stats.longestSessionMessages)) msgs",
                     valueSize: 15, alignment: .leading)
            StatTile(label: "Peak hour",
                     value: stats.peakHour.map { String(format: "%02d:00", $0) } ?? "—",
                     valueSize: 15, alignment: .leading)
        }
    }
}

/// "25 Aug" — short enough for a caption.
func dayLabel(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f.string(from: date)
}
