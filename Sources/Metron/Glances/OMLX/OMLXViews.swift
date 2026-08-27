import SwiftUI

/// One resident model with its state and size.
struct OMLXModelRow: View {
    let model: OMLXActivity.Model

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.busy ? Theme.ok : Theme.subtle.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(model.id)
                .font(Theme.rounded(10.5, .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(model.state)
                .font(Theme.rounded(9.5))
                .foregroundStyle(model.busy ? Theme.ok : Theme.subtle)
                .lineLimit(1)
            Text(compactBytes(model.size))
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.subtle)
        }
        .help(model.pinned == true ? "\(model.id) — pinned" : model.id)
    }
}

/// Shared "the server isn't there" body.
struct OMLXOffline: View {
    let message: String
    var compact = false

    var body: some View {
        UnavailableMark(text: compact ? "oMLX off" : message, symbol: "bolt.slash")
    }
}

struct OMLXSmall: View {
    @ObservedObject var store: OMLXStore

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(symbol: "sparkles", title: "oMLX",
                         tint: store.reachable ? Theme.ok : Theme.subtle)
            Spacer(minLength: 4)
            if let s = store.status, store.reachable {
                PercentRing(
                    fraction: s.memoryFraction,
                    label: s.isBusy ? "generating" : "weights",
                    caption: "\(s.models_loaded ?? 0) of \(s.models_discovered ?? 0) loaded",
                    color: s.isBusy ? Theme.ok : Theme.accent,
                    size: 76,
                    lineWidth: 6.5,
                    value: s.isBusy
                        ? "\(Int((s.avg_generation_tps ?? 0).rounded()))"
                        : nil
                )
            } else {
                OMLXOffline(message: store.error ?? "Not running", compact: true)
            }
            Spacer(minLength: 2)
        }
    }
}

struct OMLXMedium: View {
    @ObservedObject var store: OMLXStore

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(symbol: "sparkles", title: "oMLX",
                         tint: store.reachable ? Theme.ok : Theme.subtle,
                         trailing: store.status?.version.map { "v\($0)" })
            Spacer(minLength: 6)
            if let s = store.status, store.reachable {
                HStack(alignment: .center, spacing: 14) {
                    PercentRing(
                        fraction: s.memoryFraction,
                        label: "weights",
                        caption: compactBytes(s.model_memory_used ?? 0),
                        color: s.isBusy ? Theme.ok : Theme.accent,
                        size: 66,
                        lineWidth: 6
                    )
                    .frame(width: 82)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 12) {
                            StatTile(label: "Loaded",
                                     value: "\(s.models_loaded ?? 0)",
                                     caption: "of \(s.models_discovered ?? 0)",
                                     valueSize: 17)
                            StatTile(label: "In flight",
                                     value: "\(s.active_requests ?? 0)",
                                     caption: "\(s.waiting_requests ?? 0) waiting",
                                     color: s.isBusy ? Theme.ok : .primary,
                                     valueSize: 17)
                            StatTile(label: "Gen",
                                     value: String(format: "%.0f", s.avg_generation_tps ?? 0),
                                     caption: "tok/s",
                                     valueSize: 17)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(store.residentModels.prefix(2)) { m in
                                OMLXModelRow(model: m)
                            }
                        }
                    }
                }
            } else {
                OMLXOffline(message: store.error ?? "Not running")
            }
            Spacer(minLength: 0)
        }
    }
}

struct OMLXLarge: View {
    @ObservedObject var store: OMLXStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "sparkles", title: "oMLX",
                         tint: store.reachable ? Theme.ok : Theme.subtle,
                         trailing: store.status.map { "\(compactBytes($0.model_memory_max ?? 0)) budget" })

            Spacer().frame(height: 10)

            if let s = store.status, store.reachable {
                HStack(alignment: .center, spacing: 16) {
                    PercentRing(
                        fraction: s.memoryFraction,
                        label: "weights",
                        caption: compactBytes(s.model_memory_used ?? 0),
                        color: s.isBusy ? Theme.ok : Theme.accent,
                        size: 72,
                        lineWidth: 6.5
                    )
                    .frame(width: 92)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            StatTile(label: "Loaded", value: "\(s.models_loaded ?? 0)",
                                     caption: "of \(s.models_discovered ?? 0)", valueSize: 18)
                            StatTile(label: "In flight", value: "\(s.active_requests ?? 0)",
                                     caption: "\(s.waiting_requests ?? 0) waiting",
                                     color: s.isBusy ? Theme.ok : .primary, valueSize: 18)
                        }
                        HStack(spacing: 10) {
                            StatTile(label: "Prefill",
                                     value: String(format: "%.0f", s.avg_prefill_tps ?? 0),
                                     caption: "tok/s", valueSize: 18)
                            StatTile(label: "Generate",
                                     value: String(format: "%.0f", s.avg_generation_tps ?? 0),
                                     caption: "tok/s", valueSize: 18)
                        }
                    }
                }

                Spacer().frame(height: 12)

                Text("RESIDENT")
                    .font(Theme.rounded(8.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.subtle)
                    .padding(.bottom, 5)

                if store.residentModels.isEmpty {
                    Text("Nothing loaded — the first request will pull a model in.")
                        .font(Theme.rounded(10))
                        .foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.residentModels.prefix(5)) { m in
                            OMLXModelRow(model: m)
                        }
                    }
                }

                Spacer(minLength: 10)

                if let cache = s.cache_efficiency, (s.total_requests ?? 0) > 0 {
                    LabeledMeter(
                        label: "Cache hits",
                        value: "\(Int((cache * 100).rounded()))%",
                        fraction: cache,
                        color: Theme.cool,
                        caption: "\(s.total_requests ?? 0) requests · "
                            + "\(compactTokens(s.total_completion_tokens ?? 0)) generated"
                    )
                } else {
                    Text("No requests since the server started.")
                        .font(Theme.rounded(10))
                        .foregroundStyle(Theme.subtle)
                }
            } else {
                OMLXOffline(message: store.error ?? "Not running")
            }

            Spacer(minLength: 0)
        }
    }
}

struct OMLXPanel: View {
    @ObservedObject var store: OMLXStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(store: store)

            if let s = store.status, store.reachable {
                HStack(alignment: .top, spacing: 4) {
                    PercentRing(
                        fraction: s.memoryFraction,
                        label: "Weights",
                        caption: compactBytes(s.model_memory_used ?? 0),
                        color: s.isBusy ? Theme.ok : Theme.accent
                    )
                    PercentRing(
                        fraction: min(Double(s.models_loaded ?? 0)
                                      / Double(max(s.models_discovered ?? 1, 1)), 1),
                        label: "Loaded",
                        caption: "\(s.models_loaded ?? 0) of \(s.models_discovered ?? 0)",
                        color: Theme.cool,
                        value: "\(s.models_loaded ?? 0)"
                    )
                    PercentRing(
                        fraction: s.cache_efficiency ?? 0,
                        label: "Cache",
                        caption: "\(s.total_requests ?? 0) requests",
                        color: Theme.ok
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)

                PanelDivider()
                PanelSection("Throughput", trailing: s.isBusy ? "working" : "idle") {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 12) {
                            StatTile(label: "Prefill",
                                     value: String(format: "%.0f", s.avg_prefill_tps ?? 0),
                                     caption: "tok/s")
                            StatTile(label: "Generate",
                                     value: String(format: "%.0f", s.avg_generation_tps ?? 0),
                                     caption: "tok/s")
                            StatTile(label: "In flight",
                                     value: "\(s.active_requests ?? 0)",
                                     caption: "\(s.waiting_requests ?? 0) waiting",
                                     color: s.isBusy ? Theme.ok : .primary)
                        }
                        Sparkline(samples: store.tpsHistory.values, color: Theme.ok, ceiling: nil)
                            .frame(height: 26)
                    }
                }

                PanelDivider()
                PanelSection("Resident", trailing: compactBytes(s.model_memory_max ?? 0) + " budget") {
                    if store.residentModels.isEmpty {
                        Text("Nothing loaded — the first request will pull a model in.")
                            .font(Theme.rounded(10.5))
                            .foregroundStyle(Theme.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(store.residentModels) { m in OMLXModelRow(model: m) }
                        }
                    }
                }

                PanelDivider()
                PanelSection("Served", trailing: "since start") {
                    Text("\(compactTokens(s.total_prompt_tokens ?? 0)) prompt · "
                         + "\(compactTokens(s.total_completion_tokens ?? 0)) generated · "
                         + "\(compactTokens(s.total_cached_tokens ?? 0)) cached")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                PanelError(message: store.error ?? "oMLX isn't running.",
                           symbol: "bolt.slash")
            }

            PanelDivider()
            GlanceFooter(store: store)
        }
        .frame(width: Panel.width)
        .background(.ultraThinMaterial)
    }
}
