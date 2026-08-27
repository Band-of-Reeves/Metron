import SwiftUI

// MARK: - Pieces

/// One bar per logical core. On an Apple silicon machine the efficiency cores
/// sit at the left, so the shape of this strip tells you what kind of work is
/// running, not just how much.
struct CoreStrip: View {
    let cores: [Double]
    var height: CGFloat = 22

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, load in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.track)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.color(Severity.forFraction(load)).opacity(0.35 + 0.65 * load))
                        .frame(height: max(1.5, height * CGFloat(min(max(load, 0), 1))))
                        .animation(.easeOut(duration: 0.25), value: load)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// Down and up on one pair of axes, sharing a scale so the two are comparable.
struct NetworkChart: View {
    let down: SampleWindow
    let up: SampleWindow
    /// nil lets the chart take whatever height its container offers.
    var height: CGFloat? = 40

    private var ceiling: Double {
        // Headroom above the peak so the line never touches the top, and a
        // floor low enough that background chatter is still visible as a shape.
        max(max(down.peak, up.peak) * 1.2, 16_000)
    }

    var body: some View {
        ZStack {
            Sparkline(samples: down.values, color: Theme.cool, ceiling: ceiling)
            Sparkline(samples: up.values, color: Theme.accent, ceiling: ceiling, fill: false)
        }
        .frame(height: height)
        .frame(minHeight: height == nil ? 30 : nil)
    }
}

/// "↓ 12.4M/s  ↑ 840k/s"
struct NetworkRates: View {
    let down: Double
    let up: Double
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 10) {
            Label(compactRate(down), systemImage: "arrow.down")
                .foregroundStyle(Theme.cool)
            Label(compactRate(up), systemImage: "arrow.up")
                .foregroundStyle(Theme.accent)
        }
        .font(Theme.mono(size, .medium))
        .labelStyle(.titleAndIcon)
        .imageScale(.small)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// A labelled meter with its reading on the right.
struct LabeledMeter: View {
    let label: String
    let value: String
    let fraction: Double
    var color: Color?
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(Theme.rounded(8.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.subtle)
                Spacer()
                Text(value)
                    .font(Theme.mono(10.5, .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            MeterBar(fraction: fraction,
                     color: color ?? Theme.color(Severity.forFraction(fraction)))
            if let caption {
                Text(caption)
                    .font(Theme.rounded(9))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Widget sizes

struct SystemSmall: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        let s = store.snapshot
        VStack(spacing: 0) {
            WidgetHeader(symbol: "cpu", title: "System", tint: Theme.cool)
            Spacer(minLength: 4)
            PercentRing(
                fraction: s.cpuTotal,
                label: "CPU",
                caption: "load \(String(format: "%.2f", s.load1))",
                color: Theme.color(Severity.forFraction(s.cpuTotal)),
                size: 76,
                lineWidth: 6.5
            )
            Spacer(minLength: 6)
            LabeledMeter(
                label: "Memory",
                value: "\(Int((s.memoryFraction * 100).rounded()))%",
                fraction: s.memoryFraction
            )
        }
    }
}

struct SystemMedium: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        let s = store.snapshot
        VStack(spacing: 0) {
            WidgetHeader(symbol: "cpu", title: "System", tint: Theme.cool,
                         trailing: "\(s.coreCount) cores")
            Spacer(minLength: 6)
            HStack(alignment: .center, spacing: 14) {
                PercentRing(
                    fraction: s.cpuTotal,
                    label: "CPU",
                    caption: "load \(String(format: "%.2f", s.load1))",
                    color: Theme.color(Severity.forFraction(s.cpuTotal)),
                    size: 68,
                    lineWidth: 6
                )
                .frame(width: 84)

                VStack(alignment: .leading, spacing: 9) {
                    LabeledMeter(
                        label: "Memory",
                        value: "\(compactRAM(s.memoryUsed)) / \(compactRAM(s.memoryTotal))",
                        fraction: s.memoryFraction
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        NetworkRates(down: s.netDown, up: s.netUp, size: 10.5)
                        NetworkChart(down: store.downHistory, up: store.upHistory, height: 30)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct SystemLarge: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "cpu", title: "System", tint: Theme.cool,
                         trailing: "up \(compactDuration(s.uptime))")

            Spacer().frame(height: 10)

            HStack(alignment: .center, spacing: 16) {
                PercentRing(
                    fraction: s.cpuTotal,
                    label: "CPU",
                    caption: "load \(String(format: "%.2f", s.load1))",
                    color: Theme.color(Severity.forFraction(s.cpuTotal)),
                    size: 74,
                    lineWidth: 6.5
                )
                .frame(width: 90)

                VStack(alignment: .leading, spacing: 5) {
                    Text("CORES")
                        .font(Theme.rounded(8.5, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.subtle)
                    CoreStrip(cores: s.perCore, height: 34)
                    Sparkline(samples: store.cpuHistory.values,
                              color: Theme.color(Severity.forFraction(s.cpuTotal)),
                              ceiling: 1)
                        .frame(minHeight: 22)
                }
            }

            Spacer().frame(height: 14)

            LabeledMeter(
                label: "Memory",
                value: "\(compactRAM(s.memoryUsed)) / \(compactRAM(s.memoryTotal))",
                fraction: s.memoryFraction,
                caption: "app \(compactRAM(s.memoryApp)) · wired \(compactRAM(s.memoryWired))"
                    + (s.swapUsed > 0 ? " · swap \(compactRAM(s.swapUsed))" : "")
            )

            Spacer().frame(height: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("NETWORK")
                        .font(Theme.rounded(8.5, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.subtle)
                    Spacer()
                    NetworkRates(down: s.netDown, up: s.netUp, size: 10)
                }
                NetworkChart(down: store.downHistory, up: store.upHistory, height: nil)
            }
            .frame(maxHeight: .infinity)

            Spacer().frame(height: 12)

            LabeledMeter(
                label: "Disk",
                value: "\(compactBytes(s.diskFree)) free",
                fraction: s.diskUsedFraction
            )

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Full panel

struct SystemPanel: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(store: store)

            HStack(alignment: .top, spacing: 4) {
                PercentRing(
                    fraction: s.cpuTotal,
                    label: "CPU",
                    caption: "load \(String(format: "%.2f", s.load1))",
                    color: Theme.color(Severity.forFraction(s.cpuTotal))
                )
                PercentRing(
                    fraction: s.memoryFraction,
                    label: "Memory",
                    caption: compactRAM(s.memoryUsed),
                    color: Theme.color(Severity.forFraction(s.memoryFraction))
                )
                PercentRing(
                    fraction: s.diskUsedFraction,
                    label: "Disk",
                    caption: "\(compactBytes(s.diskFree)) free",
                    color: Theme.color(Severity.forFraction(s.diskUsedFraction))
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            PanelDivider()
            PanelSection("Processor", trailing: "\(s.coreCount) cores") {
                VStack(alignment: .leading, spacing: 7) {
                    CoreStrip(cores: s.perCore, height: 26)
                    Sparkline(samples: store.cpuHistory.values,
                              color: Theme.color(Severity.forFraction(s.cpuTotal)),
                              ceiling: 1)
                        .frame(height: 26)
                    Text("user \(pct(s.cpuUser)) · system \(pct(s.cpuSystem)) · idle \(pct(1 - s.cpuTotal))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.subtle)
                }
            }

            PanelDivider()
            PanelSection("Memory", trailing: compactRAM(s.memoryTotal)) {
                VStack(alignment: .leading, spacing: 7) {
                    MeterBar(fraction: s.memoryFraction,
                             color: Theme.color(Severity.forFraction(s.memoryFraction)),
                             height: 7)
                    Text("app \(compactRAM(s.memoryApp)) · wired \(compactRAM(s.memoryWired))"
                         + " · compressed \(compactRAM(s.memoryCompressed))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.subtle)
                    if s.swapTotal > 0 {
                        Text("swap \(compactRAM(s.swapUsed)) of \(compactRAM(s.swapTotal))")
                            .font(Theme.mono(10))
                            .foregroundStyle(s.swapUsed > 1e9 ? Theme.warn : Theme.subtle)
                    }
                }
            }

            PanelDivider()
            PanelSection("Network", trailing: "since boot") {
                VStack(alignment: .leading, spacing: 7) {
                    NetworkRates(down: s.netDown, up: s.netUp)
                    NetworkChart(down: store.downHistory, up: store.upHistory, height: 44)
                    Text("↓ \(compactBytes(s.netDownTotal)) · ↑ \(compactBytes(s.netUpTotal))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.subtle)
                }
            }

            PanelDivider()
            PanelSection("Storage", trailing: "boot volume") {
                VStack(alignment: .leading, spacing: 7) {
                    MeterBar(fraction: s.diskUsedFraction,
                             color: Theme.color(Severity.forFraction(s.diskUsedFraction)),
                             height: 7)
                    Text("\(compactBytes(s.diskFree)) free of \(compactBytes(s.diskTotal))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.subtle)
                }
            }

            PanelDivider()
            GlanceFooter(store: store)
        }
        .frame(width: Panel.width)
        .background(.ultraThinMaterial)
    }

    private func pct(_ f: Double) -> String { "\(Int((max(f, 0) * 100).rounded()))%" }
}
