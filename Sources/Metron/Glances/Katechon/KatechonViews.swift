import SwiftUI

/// One cell: its name, its state, and how much of its quota it has spent.
struct CellRow: View {
    let cell: KatechonState.Cell

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Circle()
                    .fill(cell.isRunning ? Theme.ok : Theme.subtle.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text(cell.name)
                    .font(Theme.rounded(10.5, .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(cell.quota.map { "\(cell.used ?? "?") / \($0)" } ?? (cell.used ?? "—"))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
            if let f = cell.fraction {
                MeterBar(fraction: f, color: Theme.color(Severity.forFraction(f)), height: 4)
            }
        }
        .help("\(cell.name) — \(cell.state ?? "unknown"), \(cell.grants ?? 0) grants")
    }
}

/// Service dots: green when up, amber when not.
struct ServiceDots: View {
    let services: [KatechonState.Service]

    var body: some View {
        FlowRow(spacing: 5) {
            ForEach(services) { s in
                HStack(spacing: 4) {
                    Circle()
                        .fill(s.isAcceptable ? Theme.ok : Theme.warn)
                        .frame(width: 5, height: 5)
                    Text(s.shortName)
                        .font(Theme.rounded(9.5))
                        .foregroundStyle(Theme.subtle)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .help("\(s.unit) — \(s.state ?? "unknown")")
            }
        }
    }
}

struct KatechonUnreachable: View {
    let message: String
    var compact = false

    var body: some View {
        UnavailableMark(text: compact ? "NAS offline" : message,
                        symbol: "externaldrive.badge.xmark")
    }
}

struct KatechonSmall: View {
    @ObservedObject var store: KatechonStore

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(symbol: "externaldrive.fill", title: "Katechon",
                         tint: store.reachable ? Theme.ok : Theme.subtle)
            Spacer(minLength: 4)
            if let s = store.state, let pool = s.pool, store.reachable {
                PercentRing(
                    fraction: pool.fraction,
                    label: pool.name ?? "pool",
                    caption: "\(pool.free ?? "?") free",
                    color: pool.isHealthy
                        ? Theme.color(Severity.forFraction(pool.fraction))
                        : Theme.crit,
                    size: 76,
                    lineWidth: 6.5
                )
            } else {
                KatechonUnreachable(message: store.error ?? "Not reachable", compact: true)
            }
            Spacer(minLength: 2)
        }
    }
}

struct KatechonMedium: View {
    @ObservedObject var store: KatechonStore

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(symbol: "externaldrive.fill", title: "KatechonOS",
                         tint: store.reachable ? Theme.ok : Theme.subtle,
                         trailing: store.state?.hostname)
            Spacer(minLength: 6)
            if let s = store.state, store.reachable {
                HStack(alignment: .center, spacing: 14) {
                    if let pool = s.pool {
                        PercentRing(
                            fraction: pool.fraction,
                            label: pool.health?.lowercased() ?? "pool",
                            caption: "\(pool.free ?? "?") free",
                            color: pool.isHealthy
                                ? Theme.color(Severity.forFraction(pool.fraction))
                                : Theme.crit,
                            size: 66,
                            lineWidth: 6
                        )
                        .frame(width: 84)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(s.allCells.prefix(3)) { CellRow(cell: $0) }
                        if s.allCells.isEmpty {
                            Text("No cells yet")
                                .font(Theme.rounded(10))
                                .foregroundStyle(Theme.subtle)
                        }
                    }
                }
            } else {
                KatechonUnreachable(message: store.error ?? "Not reachable")
            }
            Spacer(minLength: 0)
        }
    }
}

struct KatechonLarge: View {
    @ObservedObject var store: KatechonStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "externaldrive.fill", title: "KatechonOS",
                         tint: store.reachable ? Theme.ok : Theme.subtle,
                         trailing: store.state?.katechon_version.map { "v\($0)" })

            Spacer().frame(height: 10)

            if let s = store.state, store.reachable {
                HStack(alignment: .center, spacing: 16) {
                    if let pool = s.pool {
                        PercentRing(
                            fraction: pool.fraction,
                            label: pool.name ?? "pool",
                            caption: "\(pool.allocated ?? "?") of \(pool.size ?? "?")",
                            color: pool.isHealthy
                                ? Theme.color(Severity.forFraction(pool.fraction))
                                : Theme.crit,
                            size: 72,
                            lineWidth: 6.5
                        )
                        .frame(width: 92)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            StatTile(label: "Health",
                                     value: s.pool?.health?.capitalized ?? "—",
                                     caption: s.pool?.free.map { "\($0) free" },
                                     color: (s.pool?.isHealthy ?? false) ? Theme.ok : Theme.crit,
                                     valueSize: 16)
                            StatTile(label: "Cells",
                                     value: "\(s.allCells.count)",
                                     caption: "\(s.allCells.filter(\.isRunning).count) running",
                                     valueSize: 16)
                        }
                        StatTile(label: "Services",
                                 value: "\(s.allServices.filter(\.isAcceptable).count)/\(s.allServices.count)",
                                 caption: s.downServices.isEmpty
                                    ? "all up"
                                    : s.downServices.map(\.shortName).joined(separator: ", "),
                                 color: s.downServices.isEmpty ? Theme.ok : Theme.warn,
                                 valueSize: 16)
                    }
                }

                Spacer().frame(height: 12)

                Text("CELLS")
                    .font(Theme.rounded(8.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.subtle)
                    .padding(.bottom, 5)

                if s.allCells.isEmpty {
                    Text("No cells yet — `katechon cell new` makes the first one.")
                        .font(Theme.rounded(10))
                        .foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(s.allCells.prefix(4)) { CellRow(cell: $0) }
                    }
                }

                Spacer(minLength: 10)
                ServiceDots(services: s.allServices)
            } else {
                KatechonUnreachable(message: store.error ?? "Not reachable")
            }

            Spacer(minLength: 0)
        }
    }
}

struct KatechonPanel: View {
    @ObservedObject var store: KatechonStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(store: store)

            if let s = store.state, store.reachable {
                HStack(alignment: .top, spacing: 4) {
                    if let pool = s.pool {
                        PercentRing(
                            fraction: pool.fraction,
                            label: pool.name ?? "Pool",
                            caption: "\(pool.free ?? "?") free",
                            color: pool.isHealthy
                                ? Theme.color(Severity.forFraction(pool.fraction))
                                : Theme.crit
                        )
                    }
                    PercentRing(
                        fraction: s.allCells.isEmpty ? 0
                            : Double(s.allCells.filter(\.isRunning).count) / Double(s.allCells.count),
                        label: "Cells",
                        caption: "\(s.allCells.filter(\.isRunning).count) running",
                        color: Theme.cool,
                        value: "\(s.allCells.count)"
                    )
                    PercentRing(
                        fraction: s.allServices.isEmpty ? 0
                            : Double(s.allServices.filter(\.isAcceptable).count) / Double(s.allServices.count),
                        label: "Services",
                        caption: s.downServices.isEmpty ? "all up" : "\(s.downServices.count) down",
                        color: s.downServices.isEmpty ? Theme.ok : Theme.warn,
                        value: "\(s.allServices.filter(\.isAcceptable).count)"
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)

                PanelDivider()
                PanelSection("Cells", trailing: "quota used") {
                    if s.allCells.isEmpty {
                        Text("No cells yet — `katechon cell new` makes the first one.")
                            .font(Theme.rounded(10.5))
                            .foregroundStyle(Theme.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(s.allCells) { CellRow(cell: $0) }
                        }
                    }
                }

                PanelDivider()
                PanelSection("Services") {
                    ServiceDots(services: s.allServices)
                }

                PanelDivider()
                PanelSection("Boot", trailing: s.kernel) {
                    VStack(alignment: .leading, spacing: 4) {
                        if s.bootc?.readable == true {
                            Text("booted \(short(s.bootc?.booted))")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.subtle)
                            Text("rollback \(short(s.bootc?.rollback))")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.subtle)
                        } else {
                            // "there is no rollback" and "I was not allowed to
                            // look" are different facts. Say which one this is.
                            Text("bootc status needs root — not read")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.subtle)
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            } else {
                PanelError(message: store.error ?? "Can't reach the NAS.",
                           symbol: "externaldrive.badge.xmark")
            }

            PanelDivider()
            GlanceFooter(store: store)
        }
        .frame(width: Panel.width)
        .background(.ultraThinMaterial)
    }

    private func short(_ image: String?) -> String {
        guard let image, !image.isEmpty else { return "none" }
        return image.split(separator: "/").last.map(String.init) ?? image
    }
}
