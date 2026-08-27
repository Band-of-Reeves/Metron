import SwiftUI

/// A single limit window drawn as a ring with its label and reset countdown.
struct RingGauge: View {
    let window: LimitWindow
    /// Re-rendered on a timer so the countdown ticks.
    let now: Date

    private var countdown: String? {
        if let at = window.resetsAt {
            let left = at.timeIntervalSince(now)
            return left > 0 ? compactDuration(left) : "resetting"
        }
        return window.resetsRaw
    }

    var body: some View {
        PercentRing(
            fraction: window.fraction,
            label: window.label,
            caption: countdown,
            color: Theme.severity(window.percent),
            size: 66
        )
        .help("\(window.title) — \(Int(window.percent))% used"
              + (window.resetsRaw.map { ", resets \($0)" } ?? ""))
    }
}
