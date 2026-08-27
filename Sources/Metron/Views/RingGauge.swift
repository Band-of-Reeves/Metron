import SwiftUI

/// A single limit window drawn as a ring with its label and reset countdown.
struct RingGauge: View {
    let window: LimitWindow
    /// Re-rendered on a timer so the countdown ticks.
    let now: Date

    private var color: Color { Theme.severity(window.percent) }

    private var countdown: String? {
        if let at = window.resetsAt {
            let left = at.timeIntervalSince(now)
            return left > 0 ? compactDuration(left) : "resetting"
        }
        return window.resetsRaw
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Theme.track, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: window.fraction)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: window.fraction)
                    .shadow(color: color.opacity(0.35), radius: 4)

                Text("\(Int(window.percent))")
                    .font(Theme.mono(19, .semibold))
                    .foregroundStyle(.primary)
                + Text("%")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(Theme.subtle)
            }
            .frame(width: 66, height: 66)

            Text(window.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let c = countdown {
                Text(c)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
        .help("\(window.title) — \(Int(window.percent))% used"
              + (window.resetsRaw.map { ", resets \($0)" } ?? ""))
    }
}
