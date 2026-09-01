import Foundation
import Testing
@testable import Metron

@Suite("Ledger pricing")
struct PricingTests {

    @Test("A published model gets its published rate")
    func exactRates() {
        let (opus, c) = Pricing.rate(for: "claude-opus-5")
        #expect(opus.input == 5 && opus.output == 25)
        #expect(c == .exact)

        // Fable is the expensive one, and getting this wrong understates the
        // total by a third — it is 21% of tokens and 36% of cost here.
        let (fable, _) = Pricing.rate(for: "claude-fable-5")
        #expect(fable.input == 10 && fable.output == 50)
    }

    @Test("A dated snapshot resolves to its base model")
    func snapshotDates() {
        #expect(Pricing.stripSnapshotDate("claude-haiku-4-5-20251001") == "claude-haiku-4-5")
        let (rate, c) = Pricing.rate(for: "claude-haiku-4-5-20251001")
        #expect(rate.input == 1 && rate.output == 5)
        #expect(c == .exact)
        // Not every trailing number is a date.
        #expect(Pricing.stripSnapshotDate("claude-opus-4-8") == "claude-opus-4-8")
    }

    @Test("An unreleased model matches on tier rather than being dropped")
    func tierFallback() {
        let (rate, c) = Pricing.rate(for: "claude-sonnet-9")
        #expect(rate.input == 2)
        #expect(c == .tier)
    }

    @Test("Something unrecognisable is priced high and flagged, never dropped")
    func assumedFallback() {
        let (rate, c) = Pricing.rate(for: "claude-something-entirely-new")
        // Guessing low would flatter the number, which is the one thing this
        // glance must not do. A missing row would be worse: it reads as free.
        #expect(rate.input == 5)
        #expect(c == .assumed)
    }

    @Test("A local model is free and says so")
    func localModels() {
        let (rate, c) = Pricing.rate(for: "Qwen3.8-27B-Brainwaves-Tess-oQ4-mtp")
        #expect(rate.input == 0 && rate.output == 0)
        #expect(c == .local)
        #expect(Pricing.isLocal("Qwen3.8-27B"))
        #expect(!Pricing.isLocal("claude-opus-5"))
    }

    @Test("Cache writes are priced by TTL, and the 1-hour rate is 1.6x the 5-minute one")
    func cacheTTLPricing() {
        var fiveMin = TokenSplit(); fiveMin.cacheWrite5m = 1_000_000
        var oneHour = TokenSplit(); oneHour.cacheWrite1h = 1_000_000

        let a = Pricing.cost(of: fiveMin, model: "claude-opus-5")
        let b = Pricing.cost(of: oneHour, model: "claude-opus-5")
        #expect(abs(a - 6.25) < 0.001)   // 5.00 * 1.25
        #expect(abs(b - 10.00) < 0.001)  // 5.00 * 2.00
        #expect(abs(b / a - 1.6) < 0.001)
    }

    @Test("A cache read is a tenth of input, which is why the totals are cache-shaped")
    func cacheReadPricing() {
        var split = TokenSplit(); split.cacheRead = 1_000_000
        #expect(abs(Pricing.cost(of: split, model: "claude-opus-5") - 0.50) < 0.001)
    }

    @Test("Web searches are billed per request on top of tokens")
    func webSearchPricing() {
        var split = TokenSplit(); split.webSearches = 1_000
        #expect(abs(Pricing.cost(of: split, model: "claude-opus-5") - 10.0) < 0.001)
    }
}

@Suite("Ledger arithmetic")
struct LedgerMathTests {

    private func reading(days: Int, costPerDay: Double) -> LedgerReading {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        var r = LedgerReading()
        // 1M output tokens on Opus 5 is $25, so scale from that.
        let outputTokens = Int(costPerDay / 25.0 * 1_000_000)
        for i in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            var entry = LedgerDay(day: day)
            var split = TokenSplit(); split.output = outputTokens
            entry.byModel["claude-opus-5"] = split
            r.days[day] = entry
        }
        return r
    }

    @Test("Token splits add class by class")
    func splitAddition() {
        var a = TokenSplit(); a.input = 1; a.output = 2; a.cacheRead = 3
        var b = TokenSplit(); b.input = 10; b.cacheWrite1h = 5
        let sum = a + b
        #expect(sum.input == 11 && sum.output == 2 && sum.cacheRead == 3 && sum.cacheWrite1h == 5)
        #expect(sum.total == 21)
    }

    @Test("A window selects the right number of days")
    func windowing() {
        let r = reading(days: 40, costPerDay: 100)
        #expect(r.days(in: .sevenDays).count == 7)
        #expect(r.days(in: .thirtyDays).count == 30)
        #expect(r.days(in: .allTime).count == 40)
        #expect(abs(r.cost(in: .sevenDays) - 700) < 0.01)
    }

    @Test("The subscription is compared against elapsed time, not days worked")
    func subscriptionIsCalendarTime() {
        let r = reading(days: 30, costPerDay: 100)
        // You pay for the month whether or not you open the laptop, so a
        // 30-day window costs a full $200 even if only three days were active.
        #expect(abs(r.subscriptionPaid(in: .thirtyDays) - 200) < 0.01)
        #expect(abs(r.subscriptionPaid(in: .sevenDays) - 200.0 / 30 * 7) < 0.01)
    }

    @Test("The multiple is cost over what was actually paid")
    func multiple() {
        let r = reading(days: 30, costPerDay: 100)   // $3,000 over 30 days
        let m = try! #require(r.multiple(in: .thirtyDays))
        #expect(abs(m - 15.0) < 0.01)                 // 3000 / 200
    }

    @Test("Models with no tokens are not rows")
    func emptyModelsDropped() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        var r = LedgerReading()
        var entry = LedgerDay(day: today)
        var real = TokenSplit(); real.output = 1000
        entry.byModel["claude-opus-5"] = real
        entry.byModel["<synthetic>"] = TokenSplit()
        r.days[today] = entry
        // "<synthetic>" carries zero tokens and would otherwise render as a
        // row costing $0 and labelled local — three wrong things in one line.
        #expect(r.models(in: .allTime).map(\.model) == ["claude-opus-5"])
    }

    @Test("Money reads at the scale it is shown at")
    func moneyFormatting() {
        #expect(compactMoney(20_350.95) == "$20.4k")
        #expect(compactMoney(1_280_000) == "$1.3M")
        #expect(compactMoney(82.15) == "$82.15")
        #expect(money(20_350.95) == "$20,351")
        #expect(money(82.15) == "$82.15")
    }

    @Test("Token counts stay readable into the billions")
    func tokenFormatting() {
        // 15,003,800,000 rendered as "15003.8M" before this was fixed.
        #expect(compactTokens(15_003_800_000) == "15.0B")
        #expect(compactTokens(3_472_500_000) == "3.5B")
        #expect(compactTokens(217_900_000) == "217.9M")
    }
}

@Suite("Stats cache")
struct StatsCacheTests {

    @Test("Lifetime counters parse, and duration is milliseconds")
    func parsesLifetime() throws {
        let json = """
        {"totalSessions": 6049, "totalMessages": 104169,
         "firstSessionDate": "2026-06-20T16:31:13.835Z",
         "longestSession": {"duration": 495332330, "messageCount": 3591},
         "hourCounts": {"3": 142, "20": 319, "21": 400}}
        """
        let obj = try #require(try JSONSerialization.jsonObject(
            with: Data(json.utf8)) as? [String: Any])
        let stats = StatsCacheReader.parse(obj)

        #expect(stats.totalSessions == 6049)
        #expect(stats.totalMessages == 104169)
        // 495,332,330 is 137.6 hours, not 15 years — the field is milliseconds.
        #expect(abs(stats.longestSessionSeconds - 495_332.33) < 1)
        #expect(stats.longestSessionMessages == 3591)
        #expect(stats.peakHour == 21)
        #expect(stats.firstSession != nil)
    }

    @Test("A file missing everything yields zeroes rather than crashing")
    func toleratesEmpty() {
        let stats = StatsCacheReader.parse([:])
        #expect(stats.totalSessions == 0)
        #expect(stats.peakHour == nil)
        #expect(stats.firstSession == nil)
    }
}
