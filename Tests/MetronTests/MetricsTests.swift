import Foundation
import Testing
@testable import Metron

// Pure logic only: no ~/.claude.json, no ssh, no window server, no network.
// Anything that needs a live source belongs in verify.sh, where it can look at
// real data and say so.

@Suite("Formatters")
struct FormatterTests {

    @Test(
        "A duration drops to the two units that matter and never goes negative",
        arguments: [
            (0.0, "under a minute"),
            (-500.0, "under a minute"),
            (59.0, "under a minute"),
            (60.0, "1m"),
            (3_600.0, "1h"),
            (3_660.0, "1h 1m"),
            (86_400.0, "1d"),
            (90_000.0, "1d 1h"),
        ] as [(TimeInterval, String)]
    )
    func durations(interval: TimeInterval, expected: String) {
        #expect(compactDuration(interval) == expected)
    }

    @Test(
        "Token counts thin out as they grow, so a heatmap tooltip stays short",
        arguments: [
            (0, "0"),
            (999, "999"),
            (1_000, "1k"),
            (10_800_000, "10.8M"),
        ] as [(Int, String)]
    )
    func tokens(n: Int, expected: String) {
        #expect(compactTokens(n) == expected)
    }

    @Test("Storage uses decimal units, the way macOS reports a disk")
    func decimalBytes() {
        #expect(compactBytes(1e12) == "1.00 TB")
        #expect(compactBytes(1.26e12) == "1.26 TB")
        #expect(compactBytes(343_500_000) == "343.5 MB")
        #expect(compactBytes(0) == "0 B")
    }

    @Test("Memory uses binary units, so a 128 GiB machine reads as 128 GB")
    func binaryRAM() {
        #expect(compactRAM(128 * 1024 * 1024 * 1024) == "128.00 GB")
        #expect(compactRAM(0) == "0 B")
    }

    @Test("A quiet link reads as idle rather than as a misleading 0k/s")
    func rates() {
        #expect(compactRate(0) == "idle")
        #expect(compactRate(6_000) == "6k/s")
        #expect(compactRate(1.5e6) == "1.5M/s")
    }
}

@Suite("Model naming")
struct ModelStyleTests {

    @Test(
        "Known Claude ids get the name people use for them",
        arguments: [
            ("claude-opus-5-20260514", "Opus 5"),
            ("claude-fable-5-20260514", "Fable 5"),
            ("claude-sonnet-5-20260101", "Sonnet 5"),
            ("claude-haiku-4-5-20250101", "Haiku 4.5"),
            ("<synthetic>", "Synthetic"),
        ] as [(String, String)]
    )
    func labels(id: String, expected: String) {
        #expect(ModelStyle.label(for: id) == expected)
    }

    @Test("A third-party id is trimmed rather than blanked or spelled out in full")
    func foreignModel() {
        let label = ModelStyle.label(for: "qwen3-coder-30b-a3b-instruct-mlx-4bit")
        #expect(!label.isEmpty)
        #expect(label.count <= 18)
    }

    @Test("The legend order is stable, so it doesn't reshuffle between refreshes")
    func ranking() {
        let ids = ["claude-haiku-4-5", "claude-opus-5-x", "some-local-model", "claude-sonnet-5-x"]
        let sorted = ids.sorted { ModelStyle.rank(for: $0) < ModelStyle.rank(for: $1) }
        #expect(sorted.first == "claude-opus-5-x")
        #expect(sorted.last == "some-local-model")
    }
}

@Suite("Usage aggregation")
struct UsageAggregationTests {

    private func window(_ label: String, _ percent: Double) -> LimitWindow {
        LimitWindow(label: label, title: "Current \(label)", percent: percent,
                    resetsAt: nil, resetsRaw: nil)
    }

    @Test("The menu bar shows whichever window is closest to its ceiling")
    func mostConstrained() {
        var snap = UsageSnapshot()
        snap.windows = [window("session", 21), window("week", 83), window("fable", 15)]
        #expect(snap.mostConstrained?.label == "week")
    }

    @Test("With no windows there is nothing to constrain")
    func mostConstrainedEmpty() {
        #expect(UsageSnapshot().mostConstrained == nil)
    }

    @Test("A day's total is the sum across every model that worked that day")
    func dayTotals() {
        var day = DayActivity(day: Date(timeIntervalSince1970: 0))
        day.byModel = ["claude-opus-5": 1_000, "claude-haiku-4-5": 250]
        #expect(day.total == 1_250)
    }

    @Test("Peak day drives heatmap intensity, and an empty history has no peak")
    func peakDay() {
        var history = LocalHistory()
        #expect(history.peakDayTotal == 0)

        let d0 = Date(timeIntervalSince1970: 0)
        let d1 = Date(timeIntervalSince1970: 86_400)
        history.days[d0] = DayActivity(day: d0, byModel: ["m": 400])
        history.days[d1] = DayActivity(day: d1, byModel: ["m": 900])
        #expect(history.peakDayTotal == 900)
    }
}

@Suite("System snapshot")
struct SystemSnapshotTests {

    @Test("Fractions are zero rather than NaN when a total hasn't been read yet")
    func noDivideByZero() {
        let empty = SystemSnapshot()
        #expect(empty.memoryFraction == 0)
        #expect(empty.diskUsedFraction == 0)
        #expect(empty.swapFraction == 0)
    }

    @Test("Disk is reported as used, not free — the ring fills as it fills up")
    func diskIsUsedNotFree() {
        var s = SystemSnapshot()
        s.diskTotal = 1_000
        s.diskFree = 250
        #expect(s.diskUsedFraction == 0.75)
    }

    @Test("Memory used is app + wired + compressed, leaving file cache out")
    func memoryFraction() {
        var s = SystemSnapshot()
        s.memoryTotal = 100
        s.memoryUsed = 40
        #expect(s.memoryFraction == 0.4)
    }
}

@Suite("KatechonOS state")
struct KatechonStateTests {

    @Test("A socket-activated unit is healthy even though it isn't active")
    func listeningIsAcceptable() {
        let socket = KatechonState.Service(unit: "cockpit.socket", state: "listening")
        let down = KatechonState.Service(unit: "smb.service", state: "failed")
        #expect(socket.isAcceptable)
        #expect(!down.isAcceptable)
        #expect(socket.shortName == "cockpit")
    }

    @Test("Down services are the ones the menu bar glyph has to surface")
    func downServices() {
        var state = KatechonState()
        state.services = [
            KatechonState.Service(unit: "sshd.service", state: "active"),
            KatechonState.Service(unit: "cockpit.socket", state: "listening"),
            KatechonState.Service(unit: "smb.service", state: "failed"),
        ]
        #expect(state.downServices.map(\.unit) == ["smb.service"])
    }

    @Test("Only ONLINE counts as a healthy pool")
    func poolHealth() {
        #expect(KatechonState.Pool(health: "ONLINE").isHealthy)
        #expect(!KatechonState.Pool(health: "DEGRADED").isHealthy)
        #expect(!KatechonState.Pool(health: nil).isHealthy)
    }

    @Test("Pool fullness is allocated over size, clamped and safe when unreadable")
    func poolFraction() {
        let half = KatechonState.Pool(size: "1T", allocated: "512G")
        #expect(abs(half.fraction - 0.5) < 0.001)
        // A real reading off this NAS: a nearly empty 5.44T pool.
        let empty = KatechonState.Pool(size: "5.44T", allocated: "36.0M")
        #expect(empty.fraction < 0.001)
        #expect(KatechonState.Pool(size: nil, allocated: nil).fraction == 0)
    }

    @Test("An unbounded cell has no fullness, rather than a misleading zero")
    func cellWithoutQuota() {
        let unbounded = KatechonState.Cell(name: "scratch", used: "10G", quota: "-")
        #expect(unbounded.fraction == nil)
        let bounded = KatechonState.Cell(name: "media", used: "50G", quota: "100G")
        #expect(abs((bounded.fraction ?? 0) - 0.5) < 0.001)
    }

    @Test("The fullest cell is the one worth putting on a widget")
    func fullestCell() {
        var state = KatechonState()
        state.cells = [
            KatechonState.Cell(name: "a", used: "10G", quota: "100G"),
            KatechonState.Cell(name: "b", used: "90G", quota: "100G"),
            KatechonState.Cell(name: "c", used: "5G", quota: nil),
        ]
        #expect(state.fullestCell?.name == "b")
    }

    @Test("A state snapshot decodes from the JSON `katechon state` actually prints")
    func decodesRealShape() throws {
        let json = """
        {"katechon_version":"0.1.7-dev","hostname":"nas","kernel":"6.19.14",
         "storage":{"pool_name":"tank",
           "pool":{"name":"tank","health":"ONLINE","size":"5.44T",
                   "allocated":"36.0M","free":"5.44T"}},
         "cells":[],
         "services":[{"unit":"sshd.service","state":"active"}],
         "bootc":{"readable":false}}
        """
        let state = try JSONDecoder().decode(KatechonState.self, from: Data(json.utf8))
        #expect(state.pool?.name == "tank")
        #expect(state.pool?.isHealthy == true)
        #expect(state.allCells.isEmpty)
        #expect(state.downServices.isEmpty)
    }

    @Test("An unexpected shape leaves the glance empty rather than throwing")
    func toleratesMissingKeys() throws {
        let state = try JSONDecoder().decode(KatechonState.self, from: Data("{}".utf8))
        #expect(state.pool == nil)
        #expect(state.allCells.isEmpty)
        #expect(state.allServices.isEmpty)
    }

    /// Characterisation test, not an endorsement. OpenZFS prints a zero-sized
    /// dataset as "0B", and the parser drops the trailing "B" from no unit, so
    /// `Double("0B")` fails and a genuinely empty cell reads as "no quota"
    /// instead of as zero. Recorded in docs/audit/HEALTH.md as finding B3.
    @Test("KNOWN DEFECT: a ZFS \"0B\" reading parses as nil, not as zero")
    func zeroBytesSuffixIsNotParsed() {
        #expect(zfsBytes("0B") == nil)
        #expect(zfsBytes("0") == 0)      // the same quantity, written without the unit
    }
}

@Suite("oMLX status")
struct OMLXStatusTests {

    @Test("The weight budget is used over max, and zero when max is unknown")
    func memoryFraction() {
        var s = OMLXStatus()
        s.model_memory_used = 50
        s.model_memory_max = 200
        #expect(s.memoryFraction == 0.25)
        #expect(OMLXStatus().memoryFraction == 0)
    }

    @Test("Busy means anything in flight or waiting, not just active work")
    func busy() {
        #expect(!OMLXStatus().isBusy)
        var waiting = OMLXStatus()
        waiting.waiting_requests = 3
        #expect(waiting.isBusy)
    }

    @Test("A model's size prefers the measured figure over the estimate")
    func modelSize() {
        var m = OMLXActivity.Model(id: "k")
        m.estimated_size = 100
        #expect(m.size == 100)
        m.actual_size = 512
        #expect(m.size == 512)
    }

    @Test("Model state names what it is doing, in the order that matters")
    func modelState() {
        var m = OMLXActivity.Model(id: "k")
        #expect(m.state == "resident")
        m.idle_seconds = 3_600
        #expect(m.state == "idle 1h")
        m.generating = ["req-1"]
        #expect(m.state == "generating")
        m.is_loading = true
        #expect(m.state == "loading")
    }

    @Test("A status body missing every optional key still decodes")
    func decodesEmpty() throws {
        let s = try JSONDecoder().decode(OMLXStatus.self, from: Data("{}".utf8))
        #expect(s.memoryFraction == 0)
        #expect(!s.isBusy)
    }
}

@Suite("Headline")
struct HeadlineTests {

    @Test("Severity is derived from the fraction unless it is stated outright")
    func derivedSeverity() {
        #expect(Headline(fraction: 0.5).severity == .ok)
        #expect(Headline(fraction: 0.95).severity == .crit)
        // A degraded pool is critical however empty it is.
        #expect(Headline(fraction: 0.01, severity: .crit).severity == .crit)
    }

    @Test("A glance with no natural ceiling has no ring")
    func noRing() {
        let h = Headline(text: "off", severity: .idle)
        #expect(h.fraction == nil)
        #expect(h.severity == .idle)
    }
}
