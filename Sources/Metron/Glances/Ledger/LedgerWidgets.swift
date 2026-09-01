import SwiftUI

// MARK: - Small — the number

/// One figure and one comparison. There is no room for an honest chart at this
/// size, so there isn't a dishonest one either.
struct LedgerSmall: View {
    @ObservedObject var store: LedgerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "scalemass", title: "Ledger",
                         tint: Theme.accent, trailing: store.window.rawValue)
            Spacer(minLength: 0)
            if store.reading.days.isEmpty {
                UnreadMark()
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(compactMoney(store.reading.cost(in: store.window)))
                        .font(Theme.mono(30, .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("equivalent API cost")
                        .font(Theme.rounded(9.5))
                        .foregroundStyle(Theme.subtle)
                }
                Spacer(minLength: 6)
                MultipleLine(reading: store.reading, window: store.window)
            }
        }
    }
}

// MARK: - Medium — cost against output

/// The money on the left, what came of it on the right. The hairline between
/// them carries the whole argument: a cost figure alone is a flex.
struct LedgerMedium: View {
    @ObservedObject var store: LedgerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "scalemass", title: "Ledger",
                         tint: Theme.accent, trailing: store.window.rawValue)
            Spacer(minLength: 6)
            if store.reading.days.isEmpty {
                UnreadMark()
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(money(store.reading.cost(in: store.window)))
                            .font(Theme.mono(26, .semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("equivalent API cost")
                            .font(Theme.rounded(9.5))
                            .foregroundStyle(Theme.subtle)
                        Spacer(minLength: 6)
                        MultipleLine(reading: store.reading, window: store.window)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1)

                    OutputColumn(output: store.reading.output,
                                 cost: store.reading.cost(in: store.window))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Large — add the series

struct LedgerLarge: View {
    @ObservedObject var store: LedgerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "scalemass", title: "Ledger",
                         tint: Theme.accent, trailing: windowLabel)
            Spacer(minLength: 8)
            if store.reading.days.isEmpty {
                UnreadMark()
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(money(store.reading.cost(in: store.window)))
                            .font(Theme.mono(24, .semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        MultipleLine(reading: store.reading, window: store.window)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    OutputColumn(output: store.reading.output,
                                 cost: store.reading.cost(in: store.window), compact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 10)
                CostAgainstWork(reading: store.reading, window: store.window)
                    .frame(height: 92)

                Spacer(minLength: 10)
                ModelCostBar(models: Array(store.reading.models(in: store.window).prefix(5)),
                             total: store.reading.cost(in: store.window))
            }
        }
    }

    // Deliberately just the window. An "N active" here counted days with
    // token activity while the column beside it counts days with commits —
    // two different numbers wearing the same word.
    private var windowLabel: String {
        store.window == .allTime ? "all time" : "last \(store.window.rawValue)"
    }
}

// MARK: - Shared pieces

/// "43x a $200 month" — the comparison the whole glance exists to make.
private struct MultipleLine: View {
    let reading: LedgerReading
    let window: LedgerReading.Window

    var body: some View {
        if let multiple = reading.multiple(in: window) {
            HStack(spacing: 4) {
                Text(multiple >= 10 ? "\(Int(multiple.rounded()))x" : String(format: "%.1fx", multiple))
                    .font(Theme.mono(15, .semibold))
                    .foregroundStyle(.primary)
                Text("a $200 month")
                    .font(Theme.rounded(9.5))
                    .foregroundStyle(Theme.subtle)
            }
        }
    }
}

/// The counterweight: commits and files, never lines as a headline.
private struct OutputColumn: View {
    let output: OutputStats?
    let cost: Double
    var compact = false

    var body: some View {
        if let o = output {
            VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                Row(value: "\(o.commits)", label: "commits")
                Row(value: compactCount(o.filesChanged), label: "files")
                if !compact { Row(value: "\(o.repos)", label: "repos") }
                Row(value: "\(o.activeDays)", label: "days with commits")
                if o.commits > 0 {
                    Spacer(minLength: 4)
                    Text("\(money(cost / Double(o.commits))) per commit")
                        .font(Theme.rounded(9.5))
                        .foregroundStyle(Theme.subtle)
                        .lineLimit(1)
                }
            }
        } else {
            // No repositories to count. Half a panel beats no panel — the cost
            // side still stands on its own.
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subtle)
                Text("No repositories found")
                    .font(Theme.rounded(9.5))
                    .foregroundStyle(Theme.subtle)
                Text("defaults write com.watchman.metron ledger.repoRoot ~/Code")
                    .font(Theme.mono(7.5))
                    .foregroundStyle(Theme.subtle.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private struct Row: View {
        let value: String
        let label: String
        var body: some View {
            HStack(spacing: 5) {
                Text(value)
                    .font(Theme.mono(13, .semibold))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(Theme.rounded(9.5))
                    .foregroundStyle(Theme.subtle)
            }
            .lineLimit(1)
        }
    }
}

/// Cost above the line, commits below it, sharing an x-axis.
///
/// The divergence is the point: the days that cost the most are not always the
/// days that shipped the most. Drawing both lets the reader see that rather
/// than being told it.
struct CostAgainstWork: View {
    let reading: LedgerReading
    let window: LedgerReading.Window

    var body: some View {
        let days = reading.days(in: window)
        let maxCost = max(days.map(\.cost).max() ?? 1, 0.01)
        let commits = days.map { reading.output?.commitsByDay[$0.day] ?? 0 }
        let maxCommits = max(commits.max() ?? 1, 1)

        GeometryReader { geo in
            let n = max(days.count, 1)
            let slot = geo.size.width / CGFloat(n)
            let barW = max(1.5, slot * 0.62)
            let half = geo.size.height / 2

            ZStack(alignment: .center) {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.day) { i, day in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Theme.accent)
                                .frame(width: barW,
                                       height: max(1, half * 0.88 * (day.cost / maxCost)))
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Theme.cool)
                                .frame(width: barW,
                                       height: max(1, half * 0.88
                                                   * (Double(commits[i]) / Double(maxCommits))))
                            Spacer(minLength: 0)
                        }
                        .frame(width: slot)
                    }
                }
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
            }
            .overlay(alignment: .topLeading) {
                Text("cost").font(Theme.rounded(8)).foregroundStyle(Theme.accent)
            }
            .overlay(alignment: .bottomLeading) {
                Text("commits").font(Theme.rounded(8)).foregroundStyle(Theme.cool)
            }
        }
    }
}

/// The model split, by cost rather than by tokens — they rank differently, and
/// cost is what this glance is about.
struct ModelCostBar: View {
    let models: [ModelCost]
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(models) { m in
                HStack(spacing: 6) {
                    Text(m.shortName)
                        .font(Theme.rounded(9.5))
                        .foregroundStyle(Theme.subtle)
                        .frame(width: 58, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        let frac = total > 0 ? m.cost / total : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Theme.track)
                            if m.isLocal {
                                // Outlined, not filled: it ran here and cost
                                // nothing, which is a point worth making.
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Theme.ok, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    .frame(width: max(3, geo.size.width * 0.12))
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.accent.opacity(0.35 + 0.65 * frac))
                                    .frame(width: max(2, geo.size.width * frac))
                            }
                        }
                    }
                    .frame(height: 8)
                    Text(m.isLocal ? "local" : money(m.cost))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(m.isLocal ? Theme.ok : .primary)
                        .frame(width: 54, alignment: .trailing)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Nothing read yet — distinct from "$0", which would read as "you used
/// nothing" rather than "nothing was scanned".
struct UnreadMark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.subtle)
            Text("No transcripts read")
                .font(Theme.rounded(10))
                .foregroundStyle(Theme.subtle)
        }
    }
}

/// "5,606" — thousands separators without the currency machinery.
func compactCount(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
