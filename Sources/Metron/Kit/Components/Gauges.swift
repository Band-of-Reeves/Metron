import SwiftUI

/// A ring filled to `fraction`, with whatever you want in the middle.
///
/// The Usage glance's `RingGauge` is a thin wrapper over this; so is every
/// ring in the System and oMLX glances. Keeping one implementation is why they
/// all animate and shadow identically.
struct Ring<Center: View>: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 6
    var size: CGFloat = 66
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            // A round line cap on a zero-length trim draws a stray dot at
            // twelve o'clock, which reads as a reading rather than as nothing.
            if fraction > 0.004 {
                Circle()
                    .trim(from: 0, to: min(fraction, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: fraction)
                    .shadow(color: color.opacity(0.35), radius: lineWidth * 0.65)
            }
            center()
        }
        .frame(width: size, height: size)
    }
}

extension Ring where Center == EmptyView {
    init(fraction: Double, color: Color, lineWidth: CGFloat = 6, size: CGFloat = 66) {
        self.init(fraction: fraction, color: color, lineWidth: lineWidth, size: size) {
            EmptyView()
        }
    }
}

/// Ring + percentage + a label beneath: the shape the panel uses over and over.
struct PercentRing: View {
    var fraction: Double
    var label: String
    var caption: String?
    var color: Color
    var size: CGFloat = 66
    var lineWidth: CGFloat = 6
    /// Digits shown in the middle. Defaults to the rounded percentage.
    var value: String?

    var body: some View {
        VStack(spacing: 7) {
            Ring(fraction: fraction, color: color, lineWidth: lineWidth, size: size) {
                if let value {
                    Text(value)
                        .font(Theme.mono(size * 0.27, .semibold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, size * 0.12)
                } else {
                    Text("\(Int((fraction * 100).rounded()))")
                        .font(Theme.mono(size * 0.29, .semibold))
                        .foregroundStyle(.primary)
                    + Text("%")
                        .font(Theme.mono(size * 0.15, .medium))
                        .foregroundStyle(Theme.subtle)
                }
            }

            Text(label)
                .font(Theme.rounded(11, .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let caption {
                Text(caption)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A horizontal meter — the small-size stand-in for a ring, and what the
/// System glance uses for memory and disk where a bar reads faster.
struct MeterBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: height)
    }
}

/// Label above, big number below, optional caption — the workhorse tile.
struct StatTile: View {
    var label: String
    var value: String
    var caption: String?
    var color: Color = .primary
    var valueSize: CGFloat = 20
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.rounded(8.5, .semibold))
                .foregroundStyle(Theme.subtle)
                .tracking(0.6)
                .lineLimit(1)
            Text(value)
                .font(Theme.mono(valueSize, .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(Theme.rounded(9.5))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

/// A filled line chart over a rolling window of samples.
///
/// `ceiling` fixes the y-axis when there is a meaningful maximum (CPU at 100%);
/// pass nil to auto-scale to the tallest sample, which is what throughput wants.
struct Sparkline: View {
    var samples: [Double]
    var color: Color
    var ceiling: Double?
    var lineWidth: CGFloat = 1.6
    var fill = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let top = ceiling ?? max(samples.max() ?? 1, .ulpOfOne)
            let n = samples.count

            if n >= 2 {
                let step = w / CGFloat(n - 1)
                let pt: (Int) -> CGPoint = { i in
                    let y = h - CGFloat(min(max(samples[i] / top, 0), 1)) * h
                    return CGPoint(x: CGFloat(i) * step, y: y)
                }

                if fill {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        for i in 0..<n { p.addLine(to: pt(i)) }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.34), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }

                Path { p in
                    p.move(to: pt(0))
                    for i in 1..<n { p.addLine(to: pt(i)) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth,
                                                  lineCap: .round, lineJoin: .round))
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - 0.5))
                    p.addLine(to: CGPoint(x: w, y: h - 0.5))
                }
                .stroke(Theme.track, lineWidth: 1)
            }
        }
    }
}

/// A fixed-length ring buffer of samples for the sparklines.
struct SampleWindow: Equatable {
    private(set) var values: [Double] = []
    let capacity: Int

    init(capacity: Int = 60) { self.capacity = capacity }

    mutating func append(_ v: Double) {
        values.append(v)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    var latest: Double { values.last ?? 0 }
    var peak: Double { values.max() ?? 0 }
}
