import SwiftUI

/// GitHub-style contribution grid: one column per week, one row per weekday.
/// Intensity is that day's output tokens relative to the busiest day on record.
struct HeatmapView: View {
    let history: LocalHistory
    var weeks: Int = 18
    var cell: CGFloat = 12
    var gap: CGFloat = 3
    var showsLegend = true

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Columns of 7 days, oldest week first, ending on today's week.
    private var grid: [[Date]] {
        let c = cal
        let today = c.startOfDay(for: Date())
        // Walk back to the start of this week, then back `weeks - 1` more.
        let weekdayOffset = c.component(.weekday, from: today) - c.firstWeekday
        let normalized = (weekdayOffset + 7) % 7
        guard let thisWeekStart = c.date(byAdding: .day, value: -normalized, to: today),
              let first = c.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeekStart)
        else { return [] }

        return (0..<weeks).compactMap { w in
            guard let ws = c.date(byAdding: .day, value: 7 * w, to: first) else { return nil }
            return (0..<7).compactMap { d in c.date(byAdding: .day, value: d, to: ws) }
        }
    }

    private var peak: Int { max(history.peakDayTotal, 1) }

    private var monthLabels: [(index: Int, name: String)] {
        let c = cal
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "MMM"
        var out: [(Int, String)] = []
        var lastMonth = -1
        // A three-letter month needs about 26pt; at widget cell sizes that is
        // several columns, and without this two labels overprint each other.
        let minGap = max(1, Int((26 / (cell + gap)).rounded(.up)))
        var lastIndex = -minGap
        for (i, week) in grid.enumerated() {
            guard let first = week.first else { continue }
            let m = c.component(.month, from: first)
            if m != lastMonth {
                // Only label when most of the month's column is still ahead.
                if (i == 0 || c.component(.day, from: first) <= 7), i - lastIndex >= minGap {
                    out.append((i, df.string(from: first)))
                    lastIndex = i
                }
                lastMonth = m
            }
        }
        return out.map { (index: $0.0, name: $0.1) }
    }

    var body: some View {
        let columns = grid
        let today = cal.startOfDay(for: Date())

        VStack(alignment: .leading, spacing: 5) {
            // Month ruler
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 11)
                ForEach(monthLabels, id: \.index) { label in
                    Text(label.name)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.subtle)
                        .offset(x: CGFloat(label.index) * (cell + gap))
                }
            }
            .frame(width: CGFloat(columns.count) * (cell + gap) - gap, alignment: .leading)
            .clipped()
            .padding(.leading, gutterWidth + 5)

            HStack(alignment: .top, spacing: showsLegend ? 5 : 0) {
                if showsLegend { weekdayGutter }
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                cellView(day: day, today: today)
                            }
                        }
                    }
                }
            }

            if showsLegend {
                legend
                    .padding(.top, 3)
                    .padding(.leading, gutterWidth + 5)
            }
        }
    }

    private var gutterWidth: CGFloat { showsLegend ? 21 : 0 }

    /// Mon / Wed / Fri markers, matching the grid's row rhythm.
    private var weekdayGutter: some View {
        let c = cal
        let symbols = c.shortWeekdaySymbols
        // Row n holds the weekday that is n slots after the calendar's first day.
        return VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                let weekdayIndex = (c.firstWeekday - 1 + row) % 7
                Group {
                    if row % 2 == 1 {
                        Text(symbols[weekdayIndex].prefix(3))
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(Theme.subtle)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: gutterWidth, height: cell, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func cellView(day: Date, today: Date) -> some View {
        let future = day > today
        let activity = history.days[day]
        let total = activity?.total ?? 0
        let intensity = Double(total) / Double(peak)

        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(future ? Color.clear : Theme.heat(intensity))
            .frame(width: cell, height: cell)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(
                        day == today ? Theme.accent.opacity(0.9) : Color.clear,
                        lineWidth: 1.2
                    )
            )
            .help(tooltip(day: day, total: total, requests: activity?.requests ?? 0, future: future))
    }

    private func tooltip(day: Date, total: Int, requests: Int, future: Bool) -> String {
        if future { return "" }
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "EEE, MMM d"
        let head = df.string(from: day)
        if total == 0 { return "\(head) — no activity" }
        return "\(head) — \(compactTokens(total)) output tokens · \(requests) requests"
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(Theme.subtle)
            ForEach([0.0, 0.15, 0.4, 0.7, 1.0], id: \.self) { t in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.heat(t))
                    .frame(width: 9, height: 9)
            }
            Text("More")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(Theme.subtle)
            Spacer()
            if history.peakDayTotal > 0 {
                Text("peak \(compactTokens(history.peakDayTotal))/day")
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(Theme.subtle)
            }
        }
    }
}
