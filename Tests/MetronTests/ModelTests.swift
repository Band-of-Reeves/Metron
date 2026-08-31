import Foundation
import Testing
@testable import Metron

@Suite("Limit windows")
struct LimitWindowTests {

    private func window(percent: Double) -> LimitWindow {
        LimitWindow(label: "Session", title: "Current session",
                    percent: percent, resetsAt: nil, resetsRaw: nil)
    }

    @Test("Identity comes from the title, so a ring animates across refreshes")
    func stableIdentity() {
        let before = window(percent: 41)
        let after = window(percent: 58)
        #expect(before.id == after.id)
        #expect(before != after)
    }

    @Test("A fraction never leaves 0...1, whatever the server reports")
    func fractionIsClamped() {
        #expect(window(percent: 0).fraction == 0)
        #expect(window(percent: 50).fraction == 0.5)
        #expect(window(percent: 100).fraction == 1)
        #expect(window(percent: 140).fraction == 1)
        #expect(window(percent: -10).fraction == 0)
    }

    @Test("A snapshot survives the round trip through disk")
    func snapshotRoundTrips() throws {
        var snapshot = UsageSnapshot()
        snapshot.windows = [window(percent: 83)]
        snapshot.planNote = "Max 20x plan"
        snapshot.fetchedAt = Date(timeIntervalSince1970: 1_770_000_000)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}

@Suite("Severity ramp")
struct SeverityTests {

    @Test("The ramp matches what the README promises: amber at 70, red at 90")
    func thresholds() {
        #expect(Severity.forFraction(0.00) == .ok)
        #expect(Severity.forFraction(0.699) == .ok)
        #expect(Severity.forFraction(0.70) == .warn)
        #expect(Severity.forFraction(0.899) == .warn)
        #expect(Severity.forFraction(0.90) == .crit)
        #expect(Severity.forFraction(1.00) == .crit)
    }
}

@Suite("Glance sizes")
struct GlanceSizeTests {

    @Test("The three widget sizes mirror the proportions macOS uses")
    func widgetProportions() throws {
        let small = try #require(GlanceSize.small.dimensions)
        let medium = try #require(GlanceSize.medium.dimensions)
        let large = try #require(GlanceSize.large.dimensions)

        #expect(small.width == small.height)          // square
        #expect(medium.width == large.width)          // same column width
        #expect(medium.height == small.height)        // same row height
        #expect(large.height == medium.height * 2 + 24)
    }

    @Test("Full sizes itself to its content, so it has no fixed dimensions")
    func fullIsUnconstrained() {
        #expect(GlanceSize.full.dimensions == nil)
    }

    @Test("Every size round-trips through the raw value stored in defaults")
    func rawValuesRoundTrip() {
        for size in GlanceSize.allCases {
            #expect(GlanceSize(rawValue: size.rawValue) == size)
        }
    }
}

@Suite("ZFS sizes")
struct ZFSBytesTests {

    private static let kilo = 1024.0
    private static let mega = kilo * 1024
    private static let giga = mega * 1024
    private static let tera = giga * 1024

    @Test(
        "A human ZFS size parses to bytes",
        arguments: [
            ("1.81T", 1.81 * tera),
            ("930G", 930 * giga),
            ("12.5M", 12.5 * mega),
            ("512K", 512 * kilo),
            ("4096", 4096.0),
        ] as [(String, Double)]
    )
    func parses(text: String, expected: Double) throws {
        let got = try #require(zfsBytes(text))
        #expect(abs(got - expected) < 1)
    }

    @Test(
        "The empty readings ZFS prints are nil, not zero",
        arguments: ["-", "none", "NONE", "", "   ", "not-a-size"]
    )
    func emptyReadings(text: String) {
        #expect(zfsBytes(text) == nil)
    }

    @Test("A missing value is nil")
    func missing() {
        #expect(zfsBytes(nil) == nil)
    }
}
