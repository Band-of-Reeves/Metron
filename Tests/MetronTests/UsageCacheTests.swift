import Foundation
import Testing
@testable import Metron

/// The naming that turns Claude Code's cache keys into ring labels.
///
/// These are pure functions over strings, so they run anywhere — no
/// `~/.claude.json`, no network, no window server. `UsageCache.read()` itself
/// is deliberately not tested here: it reads a fixed path in the real home
/// directory, and the check that the key still exists lives in `verify.sh`,
/// where it can look at actual data.
@Suite("Usage cache naming")
struct UsageCacheTests {

    @Test("The two always-present windows keep their short labels")
    func knownLabels() {
        #expect(UsageCache.label(for: "five_hour") == "Session")
        #expect(UsageCache.label(for: "seven_day") == "Week")
    }

    @Test("A per-model week is labelled by the model, not the window")
    func scopedLabel() {
        #expect(UsageCache.label(for: "seven_day_opus") == "Opus")
        #expect(UsageCache.title(for: "seven_day_opus") == "Current week (Opus)")
    }

    @Test("Titles spell out which window a ring is")
    func titles() {
        #expect(UsageCache.title(for: "five_hour") == "Current session")
        #expect(UsageCache.title(for: "seven_day") == "Current week (all models)")
    }

    @Test("An unknown key degrades to something readable rather than raw")
    func unknownKey() {
        #expect(UsageCache.label(for: "thirty_day_beta") == "Thirty Day Beta")
        #expect(!UsageCache.label(for: "thirty_day_beta").contains("_"))
    }

    @Test("Product names keep the casing people write them with")
    func productCasing() {
        #expect(UsageCache.label(for: "mcp_calls") == "MCP Calls")
    }

    @Test(
        "Rate-limit tiers map to the plan name shown under the rings",
        arguments: [
            ("default_claude_max_20x", "Max 20x plan"),
            ("default_claude_max_5x", "Max 5x plan"),
            ("default_claude_pro", "Pro plan"),
            ("default_claude_team", "Team plan"),
            ("default_claude_enterprise", "Enterprise plan"),
        ]
    )
    func planLabels(tier: String, expected: String) {
        #expect(UsageCache.planLabel(tier) == expected)
    }

    @Test("An unrecognised tier still reads as a plan, not as a raw key")
    func unknownPlan() {
        let label = UsageCache.planLabel("default_claude_something_new")
        #expect(label.hasSuffix(" plan"))
        #expect(!label.contains("default_"))
    }
}
