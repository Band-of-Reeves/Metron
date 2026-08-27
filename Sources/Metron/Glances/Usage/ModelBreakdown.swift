import SwiftUI

/// Stacked bar + legend showing which models did this week's work,
/// measured in output tokens from local transcripts.
struct ModelBreakdown: View {
    let totals: [String: Int]
    /// Widget sizes get the bar and one row of legend, not the full grid.
    var compact = false

    private static let palette: [Color] = [
        Color(red: 0.851, green: 0.467, blue: 0.341),  // coral
        Color(red: 0.576, green: 0.478, blue: 0.839),  // violet
        Color(red: 0.353, green: 0.612, blue: 0.847),  // blue
        Color(red: 0.373, green: 0.706, blue: 0.612),  // teal
        Color(red: 0.902, green: 0.678, blue: 0.302),  // amber
        Color(red: 0.549, green: 0.565, blue: 0.612),  // slate
    ]

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let tokens: Int
        let share: Double
        let color: Color
    }

    private var slices: [Slice] {
        let sum = totals.values.reduce(0, +)
        guard sum > 0 else { return [] }
        let ordered = totals.sorted {
            let r0 = ModelStyle.rank(for: $0.key), r1 = ModelStyle.rank(for: $1.key)
            return r0 == r1 ? $0.value > $1.value : r0 < r1
        }
        return ordered.enumerated().map { i, kv in
            Slice(
                id: kv.key,
                label: ModelStyle.label(for: kv.key),
                tokens: kv.value,
                share: Double(kv.value) / Double(sum),
                color: Self.palette[i % Self.palette.count]
            )
        }
        .filter { $0.share >= 0.005 }
    }

    var body: some View {
        let items = slices
        VStack(alignment: .leading, spacing: 8) {
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(items) { s in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(s.color)
                            .frame(width: max(2, geo.size.width * s.share - 1.5))
                    }
                }
            }
            .frame(height: 7)

            // Legend, two per row
            let legendItems = compact ? Array(items.prefix(2)) : items
            let rows = stride(from: 0, to: legendItems.count, by: 2).map {
                Array(legendItems[$0..<min($0 + 2, legendItems.count)])
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(row) { s in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(s.color)
                                    .frame(width: 6, height: 6)
                                Text(s.label)
                                    .font(.system(size: 10.5, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(Int((s.share * 100).rounded()))%")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.subtle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help("\(s.label) — \(compactTokens(s.tokens)) output tokens this week")
                        }
                        if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }
}

/// A compact row of "what's driving usage" chips.
struct DriverChips: View {
    let drivers: Drivers

    private var chips: [String] {
        var out: [String] = []
        out += drivers.skills.prefix(2).map { "\($0.name) \($0.pct)%" }
        out += drivers.agents.prefix(2).map { "\($0.name) \($0.pct)%" }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if drivers.requests > 0 {
                Text("\(drivers.requests) requests · \(drivers.sessions) sessions")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.subtle)
            }
            if let top = drivers.behaviors.first {
                Text(top)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !chips.isEmpty {
                FlowRow(spacing: 5) {
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.subtle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.06))
                            )
                    }
                }
            }
        }
    }
}

/// Minimal wrapping HStack — chips flow onto the next line when they don't fit.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
