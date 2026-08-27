import SwiftUI

/// The local oMLX server: what is resident, what is generating, how much of
/// the weight budget is committed.
@MainActor
final class OMLXStore: GlanceStore {
    @Published private(set) var status: OMLXStatus?
    @Published private(set) var activity = OMLXActivity()
    @Published private(set) var device: OMLXDevice?
    @Published private(set) var tpsHistory = SampleWindow(capacity: 60)
    @Published private(set) var reachable = false

    init() {
        super.init(id: "omlx", name: "oMLX", symbol: "sparkles")
    }

    override class var defaultRefreshSeconds: Int { 5 }
    override class var refreshChoices: [Int] { [2, 5, 15, 60, 300] }

    override func load() async {
        do {
            let s = try await OMLXFetcher.fetch("api/status", as: OMLXStatus.self)
            status = s
            reachable = true
            error = nil
            tpsHistory.append(s.avg_generation_tps ?? 0)

            // These two are nice-to-have; a failure here should not blank the
            // panel that already has a good /api/status reading.
            activity = (try? await OMLXFetcher.fetch("admin/api/activity", as: OMLXActivity.self))
                ?? OMLXActivity()
            if device == nil {
                device = try? await OMLXFetcher.fetch("admin/api/device-info", as: OMLXDevice.self)
            }
        } catch {
            reachable = false
            status = nil
            activity = OMLXActivity()
            self.error = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "oMLX isn't answering on \(OMLXFetcher.base().absoluteString)"
            case .timedOut:
                return "oMLX timed out"
            default: break
            }
        }
        return error.localizedDescription
    }

    override var headline: Headline? {
        guard reachable, let s = status else {
            return Headline(fraction: nil, text: "off", severity: .idle)
        }
        // While work is in flight the useful number is throughput; the rest of
        // the time it is how much of the weight budget is spoken for.
        if s.isBusy {
            let tps = s.avg_generation_tps ?? 0
            return Headline(fraction: s.memoryFraction,
                            text: tps > 0 ? "\(Int(tps.rounded())) t/s" : "busy",
                            severity: .ok)
        }
        return Headline(fraction: s.memoryFraction,
                        text: "\(Int((s.memoryFraction * 100).rounded()))%")
    }

    override var subtitle: String {
        guard reachable, let s = status else { return "Not running" }
        var parts: [String] = []
        if let v = s.version { parts.append("v\(v)") }
        if let d = device?.label, !d.isEmpty { parts.append(d) }
        else if let up = s.uptime_seconds { parts.append("up \(compactDuration(up))") }
        return parts.joined(separator: " · ")
    }

    /// Resident models, busiest first.
    var residentModels: [OMLXActivity.Model] {
        activity.models.sorted {
            if $0.busy != $1.busy { return $0.busy }
            return $0.size > $1.size
        }
    }

    override func content(_ size: GlanceSize) -> AnyView {
        switch size {
        case .full:   return AnyView(OMLXPanel(store: self))
        case .small:  return AnyView(OMLXSmall(store: self))
        case .medium: return AnyView(OMLXMedium(store: self))
        case .large:  return AnyView(OMLXLarge(store: self))
        }
    }
}
