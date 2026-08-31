# Metron health audit

What is actually broken before this repo goes public. Every finding below was
reproduced on this machine against live data; nothing here is inferred from
reading alone unless it says so.

- Commit audited: `26a01b0` (branch `claude/metron-repo-setup-7c15b6`)
- Toolchain: Swift 6, `swift-tools-version: 6.0`, language mode pinned to `.v5`
- Platform: macOS (Darwin 27.0.0), Apple silicon, 128 GB
- Live sources during the audit: oMLX **up** (HTTP 200), KatechonOS **reachable** over ssh

**Findings: 3 blocking, 8 real bugs, 10 cleanup.**

The single most serious one is A0: a personal email address, a real name and two
Apple Developer Team IDs are committed to this branch, in a document that would
ship with the public repo.

---

## (a) Blocks public release

### A0 — a personal email, a real name and Apple Team IDs are committed

`docs/release/PLAN.md:108-116`, committed in `366ef69`
`docs/ledger/OUTPUT.txt:4`, committed in `c321ffe`

`docs/release/PLAN.md` pastes the verbatim output of `security find-identity`:

```
  1) <hash> "Apple Development: <redacted> (<team id>)"
  2) <hash> "Apple Development: <redacted> (<team id>)"
```

That is a personal email address, a legal name, two Apple Developer Team IDs and
two partial certificate hashes, in a file that goes public with the repo. None of
it is needed to explain the signing decision the document is making — the same
paragraph reads fine as "two Apple Development identities, no Developer ID".

Separately, `docs/ledger/OUTPUT.txt:4` records `/Users/<you>/.claude/stats-cache.json`,
which is the absolute-home-path leak the release checklist two files away
declares already handled:

```
docs/release/PLAN.md:257: | **No `/Users/<you>` path anywhere** | — | Checked. Clean. |
docs/release/PLAN.md:284: - [x] No `/Users/<you>` paths in tracked source
```

Both files belong to the LEDGER and RELEASE lanes under `PLAN.md`'s ownership
table, so this audit reports them rather than editing them. Reproduce with:

```
$ bash docs/audit/no-private-paths.sh
```

which is the probe `PLAN.md` names as evidence for its `no-private-paths` row.
That row currently **fails**, and it should stay failing until these two files
are cleaned — it was passing as "not yet proven" only because the probe did not
exist until this audit wrote it.

### A1 — `--measure` skips the one glance most likely to clip, and still reports "ok"

`Sources/Metron/PreviewRenderer.swift:86-90`

```swift
// Katechon's ssh probe is slow and offline here; the point of the
// check is the growth, which every glance shows.
if store.id != "katechon" {
    settle(store: store, extraSamples: store is SystemStore ? 1 : 0)
}
```

The KatechonOS store is never loaded during `--measure`, so `empty`, `loaded`,
`panel` and `shown` are all the *empty* panel and the drift is trivially zero:

```
katechon  empty  117 -> loaded  117   panel  117   shown  117   drift 0.0
ok: every popover matches its panel
```

The real loaded panel is **418 pt**, not 117:

```
$ .build/release/Metron --render k.png --glance katechon --size full
wrote k.png — katechon/full 344x418 pt
```

So the check passes on a panel **301 pt shorter** than the one that ships, and
`verify.sh` prints `ok  every popover matches its panel` on the strength of it.
This is precisely the failure mode the README says the tool was built to catch:

> A glance that renders but has nothing to show is the failure that looks like
> success; that is the one this is built to catch.

The comment's premise is also false here — the host answered in about a second
on this machine. Whatever the fix (settle it like the others, or fail loudly
when it cannot), a green board that skips a quarter of its subject should not
be the thing a first public release is signed off against.

### A2 — `docs/panel.png` publishes private skill and project names

`docs/panel.png`, embedded at `README.md:7`

The Drivers block in the committed screenshot reads:

```
3,749 requests · 19 sessions
76% of your usage was at >150k context
/visual-verify 4%    /katechonos 2%    general-purpose 14%
```

`/visual-verify` and `/katechonos` are personal skill names, and `/katechonos`
names an unpublished project. Also visible: session counts and a context-window
working habit. `docs/widgets.png` was inspected too and is clean — it shows only
model split, CPU, memory, disk and oMLX figures, nothing identifying.

No credential, email, token or absolute home path appears in either image, and a
sweep of tracked text found none either:

```
$ git grep -nIi -E "api[_-]?key|secret|token=|password|Authorization" -- Sources/ README.md
Sources/.../KatechonModels.swift:166:  "-o", "BatchMode=yes",   // never sit at a password prompt
```

The only other personal strings are `com.watchman.metron` (the bundle id, which
is the author's own handle and fine) and the bare LAN hostname `katechon`, which
is a default the README documents how to change. Both are defensible in public;
the skill names in the screenshot are the item to decide on, because a published
image cannot be recalled.

---

## (b) Real bugs

### B1 — the heatmap draws 18 weeks but only 17 are ever populated

`Sources/Metron/Glances/Usage/HeatmapView.swift:7` — `var weeks: Int = 18`
`Sources/Metron/Glances/Usage/TranscriptScanner.swift:26` — `func scan(daysBack: Int = 119)`

The grid walks back `7 * (weeks - 1) = 119` days from the *start of this week*,
and this week's start is itself up to 6 days behind today. So the leftmost
column can reach 125 days back, while the scanner discards anything older than
119 days (`TranscriptScanner.swift:33`, `where day >= cutoff` at line 67).

```
heatmap spans back up to 119 + up to 6 (week alignment) = 125 days
scanner cutoff is 119 days
always-blank leading days: 6
```

Up to six leading cells are therefore blank no matter how much work they
contain. Visible in every `usage` render: the leftmost column is empty. The fix
is one number — scan `7 * weeks` days, or derive one bound from the other rather
than writing 18 and 119 in two files.

### B2 — four genuine strict-concurrency violations, currently masked by `.v5`

`Package.swift` pins `swiftSettings: [.swiftLanguageMode(.v5)]`. Rebuilding the
same tree under `.v6` produces four errors (verified, then reverted):

| File:line | Error |
|---|---|
| `Glances/Usage/UsageFetcher.swift:18` | static property `cachedBinary` is not concurrency-safe — nonisolated global shared mutable state |
| `Glances/Usage/UsageFetcher.swift:55` | static property `lastCLIAttempt` is not concurrency-safe — nonisolated global shared mutable state |
| `Glances/Usage/TranscriptScanner.swift:164` | static property `iso` is not concurrency-safe — `ISO8601DateFormatter` may have shared mutable state |
| `Glances/System/SystemMetrics.swift:132` | reference to var `vm_kernel_page_size` is not concurrency-safe |

None is currently exploitable — every one is reached only from the main actor or
from the single `TranscriptScanner` actor instance — so this is a latent
correctness item, not a live crash. But a package that declares tools version 6.0
and then opts out of its language mode should say why, and the four sites are
small enough to fix (an `actor`-isolated formatter, two `nonisolated(unsafe)` or
actor-held values, one `let` capture of the page size).

### B3 — a ZFS `0B` reading parses as "no value" rather than zero

`Sources/Metron/Glances/Katechon/KatechonModels.swift:93-101`

```swift
let multipliers: [(Character, Double)] = [
    ("K", 1024), ("M", 1024*1024), ("G", ...), ("T", ...), ("P", ...),
]
```

`B` is not in the table, so for OpenZFS's `"0B"` the suffix is never stripped and
`Double("0B")` returns nil. A cell using exactly zero of its quota therefore
reports *no reading* (`Cell.fraction == nil`, rendered as an unbounded cell)
instead of 0%. Locked as a characterisation test in
`Tests/MetronTests/MetricsTests.swift` (`zeroBytesSuffixIsNotParsed`).

Not visible today only because the NAS currently has zero cells — the live pool
reads `size 5.44T / allocated 36.0M`, which parses fine. The parser is also
case-sensitive (`"1.81t"` fails), which is harmless against real `zfs` output
but is the same latent shape.

### B4 — the ssh reader can deadlock until the 12-second killer fires

`Sources/Metron/Glances/Katechon/KatechonModels.swift:193-195`

```swift
let data = out.fileHandleForReading.readDataToEndOfFile()
let errData = err.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
```

stdout is drained to EOF *before* stderr is read at all. If the child ever
writes more than a pipe buffer (~64 KB) to stderr while stdout is still open, it
blocks on the stderr write while the parent blocks on the stdout read. The 12 s
deadline saves it from being permanent, but the glance then reports
`katechon didn't answer within 12s` for what was actually a chatty stderr.
Unlikely with `katechon state`; the standard fix is to read both concurrently.

### B5 — CPU tick loop trusts `cpuCount` without checking `infoCount`

`Sources/Metron/Glances/System/SystemMetrics.swift:79-83`

```swift
let states = Int(CPU_STATE_MAX)
var ticks = [UInt32](repeating: 0, count: Int(cpuCount) * states)
for i in 0..<(Int(cpuCount) * states) {
    ticks[i] = UInt32(bitPattern: info[i])
}
```

`info` is only guaranteed to hold `infoCount` elements. The loop derives its
bound from `cpuCount * CPU_STATE_MAX` instead and never compares the two. The
kernel does return `infoCount == cpuCount * CPU_STATE_MAX` in practice, so this
does not fire today — but it is an unguarded out-of-bounds read on a buffer
whose length the API hands back separately, and the guard is one line. Note the
`vm_deallocate` in the `defer` correctly uses `infoCount`, so the two disagree
about which number is authoritative.

Otherwise this file is careful: the tick wrap is handled (line 98), the first
sample is correctly dropped rather than spiking (line 86), and there are no
force-unwraps anywhere in it.

### B6 — the interface walk bounds-checks the smaller struct, then reads the larger

`Sources/Metron/Glances/System/SystemMetrics.swift:174-181`

```swift
while offset + MemoryLayout<if_msghdr>.size <= len {
    ...
    if hdr.ifm_type == RTM_IFINFO2 {
        let m2 = base.advanced(by: offset)
            .assumingMemoryBound(to: if_msghdr2.self).pointee
```

The loop condition validates room for an `if_msghdr`, but the body dereferences
an `if_msghdr2`, which is larger. There is also no `offset + msgLen <= len`
check before advancing. Kernel-supplied buffers are well-formed, so this is
defensive rather than live — but it is the second place in this file where the
bound and the read disagree.

### B7 — any throughput under 1 kB/s displays as "idle"

`Sources/Metron/Kit/Theme.swift:94-101`

```swift
case 1e3...: return String(format: "%.0fk/s", n / 1e3)
default:     return "idle"
```

999 B/s of real traffic reads as `idle`. On a link that is genuinely quiet this
is the right call; on a slow trickle it states something false. `compactBytes`
and `compactRAM` both handle their small cases explicitly, so this one is
inconsistent with its neighbours as well as inaccurate.

### B8 — `--render` silently accepts a bad `--size` and a negative `--scale`

`Sources/Metron/PreviewRenderer.swift:16` and `:14`

```swift
let size = GlanceSize(rawValue: argument(after: "--size", in: arguments) ?? "full") ?? .full
let scale = argument(after: "--scale", in: arguments).flatMap(Double.init) ?? 2.0
```

`--size enormous` renders `.full` and exits 0, so a typo in a script silently
audits the wrong thing — a real hazard given `verify.sh` drives this path.
An unknown `--glance` is rejected properly at line 21; `--size` should match.
`--scale -1` is likewise accepted and passed to `ImageRenderer`.

---

## (c) Cleanup

| # | Where | What |
|---|---|---|
| C1 | `Glances/Usage/UsageStore.swift:28` | The only two build warnings: `var (u, h) = await (limits, local)` — neither is mutated, should be `let`. |
| C2 | `Glances/OMLX/OMLXModels.swift:71` | `actual_size!` force-unwrap. Guarded by the preceding `(actual_size ?? 0) > 0`, so safe, but it is the only force-unwrap of an optional in the codebase and reads as an accident waiting to be refactored into one. |
| C3 | `Kit/DeskWindow.swift:213` and `:139` | `restorePosition()` runs twice on every `show()` — once at the end of `build()`, once in `show()` itself. |
| C4 | `Kit/DeskWindow.swift:86` | `placementKey` is `NSScreen.localizedName`, which is not unique — two identical displays both key as e.g. `SAMSUNG`. Only used as an "is it still attached" test and `clampOnScreen()` catches the fallout, so the impact is small. |
| C5 | `Kit/DeskWindow.swift:276` | When a window is wider than the target `visibleFrame`, `min(max(o.x, vf.minX), vf.maxX - frame.width)` yields a value left of `vf.minX` and pushes it off the left edge. The `y` axis degrades gracefully; `x` does not. |
| C6 | `Glances/System/SystemMetrics.swift:70,127` | `mach_host_self()` returns a send right that is never `mach_port_deallocate`d. Once per sample, so it accumulates over a long-running app. |
| C7 | `Glances/Usage/UsageFetcher.swift:37-48` | `runLoginShell` executes `/bin/zsh -lc` from a GUI app to find `claude`. Correct in intent (a GUI app inherits a minimal PATH), but it runs the user's full login config synchronously; a slow `.zshrc` stalls the fetch. It is a last resort after four fixed paths, so it rarely runs. |
| C8 | `Glances/Katechon/KatechonModels.swift:168` | `StrictHostKeyChecking=accept-new` trusts an unknown host key on first contact. Reasonable for a LAN NAS, worth a line in the README now that strangers will read it. |
| C9 | `Glances/OMLX/OMLXModels.swift:30` | `let max = model_memory_max` shadows the `max` function inside `memoryFraction`. |
| C10 | `Kit/Glance.swift:141` | `GlanceStore` has no `deinit` calling `stop()`. Harmless today because every store is owned for the process lifetime by `GlanceRegistry.shared`, but the timers would outlive a store that ever became transient. Both timer closures do correctly capture `[weak self]`, so there is no retain cycle. |

### Things specifically checked and found sound

- **Force-unwraps in the metrics code** — none in `SystemMetrics.swift`. The only one in the codebase is C2.
- **Timer / refresh lifecycle** — `Timer.scheduledTimer` closures use `[weak self]`; `stop()` invalidates both timers; `start()` is idempotent via `guard timer == nil`. No retain cycle.
- **Refresh coalescing** — `GlanceStore.refresh()` (`Kit/Glance.swift:156-172`) correctly makes concurrent callers await the in-flight task rather than returning stale, and clears `inFlight` after.
- **JSON decoding** — every field of `OMLXStatus`, `OMLXActivity`, `OMLXDevice` and `KatechonState` is optional, so an upstream rename degrades a line instead of blanking the panel. `{}` decodes cleanly for both; covered by tests.
- **oMLX secret handling** — `/admin/api/stats` (which returns the server API key in cleartext) is genuinely never requested; only `api/status`, `admin/api/activity` and `admin/api/device-info` are.
- **Child-process hygiene** — `UsageFetcher` strips `CLAUDE*` from the child environment and runs from `$HOME` so it cannot pick up project config or hooks.
- **Multi-display placement** — the drag interception in `DeskPanel.sendEvent` and the `clampOnScreen` fallback both behave as the README describes; a window on a detached display does return to an attached one.
- **The broken-symbol glyph in `--render` output** is not a bug. The footer's `ellipsis.circle` renders as a placeholder only on the `ImageRenderer` path; the `--window` path draws it correctly, which is the documented reason `--window` exists. All nine SF Symbols used were verified present on this OS.

---

## Appendix 1 — `./verify.sh`, full output

```
build
  ok   release build
popover sizing
  ok   every popover matches its panel
live data
  ok   usage — 21% (21%)
  ok   system — 8% (8%)
  ok   omlx — 0% (0%)
  ok   katechon — 0% (0%)
widget sizes
  ok   usage/small renders
  ok   usage/medium renders
  ok   usage/large renders
limit source
  ok   ~/.claude.json carries utilization.limits

all checks passed
```

Exit 0. Two things this does not tell you, both covered above: the popover-sizing
row never loads the KatechonOS panel (A1), and the `omlx`/`katechon` rows are
checked with `expect=any`, so a `0%` headline passes whether it means "empty" or
"genuinely empty". Both readings were confirmed genuine here — oMLX answered
HTTP 200 with one resident model, and the pool really is at 36 MB of 5.44 T.

`Metron --measure`:

```
usage     empty  496 -> loaded  606   panel  606   shown  606   drift 0.0
system    empty  619 -> loaded  619   panel  619   shown  619   drift 0.0
omlx      empty  119 -> loaded  462   panel  462   shown  462   drift 0.0
katechon  empty  117 -> loaded  117   panel  117   shown  117   drift 0.0
ok: every popover matches its panel
```

`usage` and `omlx` show the growth the check is for. `system` does not grow
because its empty and loaded layouts are the same height. `katechon` does not
grow because it was never loaded — see A1.

## Appendix 2 — render matrix

Every glance × every size × with and without `--window`. All 32 combinations
exited 0 and wrote a non-empty PNG; none rendered blank.

| glance | size | plain | `--window` | headline |
|---|---|---|---|---|
| usage | small | ok 60 kB | ok 33 kB | `21% (21%)` |
| usage | medium | ok 96 kB | ok 48 kB | `21% (21%)` |
| usage | large | ok 179 kB | ok 77 kB | `21% (21%)` |
| usage | full | ok 333 kB | ok 127 kB | `21% (21%)` |
| system | small | ok 56 kB | ok 30 kB | `6% (5%)` |
| system | medium | ok 87 kB | ok 47 kB | `6% (6%)` / `8% (7%)` |
| system | large | ok 161 kB | ok 76 kB | `5% (5%)` / `8% (7%)` |
| system | full | ok 308 kB | ok 124 kB | `7% (7%)` / `9% (9%)` |
| omlx | small | ok 50 kB | ok 25 kB | `0% (0%)` |
| omlx | medium | ok 87 kB | ok 43 kB | `0% (0%)` |
| omlx | large | ok 151 kB | ok 63 kB | `0% (0%)` |
| omlx | full | ok 223 kB | ok 85 kB | `0% (0%)` |
| katechon | small | ok 49 kB | ok 24 kB | `0% (0%)` |
| katechon | medium | ok 66 kB | ok 31 kB | `0% (0%)` |
| katechon | large | ok 161 kB | ok 70 kB | `0% (0%)` |
| katechon | full | ok 231 kB | ok 101 kB | `0% (0%)` |

A representative sample was opened and looked at rather than trusted by exit
code — `usage/full`, `usage/full --window`, `usage/small`, `usage/small --window`,
`omlx/full`, `katechon/full`, plus both `docs/*.png`. All carried real data:
the KatechonOS panel showed `tank` ONLINE with 5.44 T free and six services up;
the oMLX panel showed `Kokoro-82M-bf16` resident at 511.9 MB. The system
glance's headline varies between rows because CPU is a rate differenced across
two samples, which is expected.

The `0%` headlines for oMLX and KatechonOS are correct readings, not blanks —
oMLX is holding 343.5 MB of a 98.20 GB weight budget, and the pool is 36 MB into
5.44 T. Both round to zero.

## Appendix 3 — build

`swift build -c release` and `./build.sh` both succeed. Two warnings, both C1:

```
Sources/Metron/Glances/Usage/UsageStore.swift:28:14: warning: variable 'u' was never mutated; consider changing to 'let' constant
Sources/Metron/Glances/Usage/UsageStore.swift:28:17: warning: variable 'h' was never mutated; consider changing to 'let' constant
```

No errors. `./build.sh` produces `dist/Metron.app` and ad-hoc signs it.

## Appendix 4 — `docs/audit/no-private-paths.sh`

Written by this audit, because `PLAN.md` names it as the evidence for its
`no-private-paths` row and it did not exist. It checks tracked files only —
the working tree carries gitignored build output and scratch renders that are
never published. Current output:

```
absolute home paths
  FAIL absolute home paths in tracked files
       docs/ledger/OUTPUT.txt:4:source        /Users/<you>/.claude/stats-cache.json
       docs/release/PLAN.md:257:| **No `/Users/<you>` path anywhere** | — | Checked. Clean. |
       docs/release/PLAN.md:284:- [x] No `/Users/<you>` paths in tracked source
credentials
  ok   no credential literals
private network
  ok   no private IP addresses
personal email
  FAIL personal email address in tracked files
       docs/release/PLAN.md:112:  1) <hash> "Apple Development: <redacted> (<team id>)"
screenshots
  ok   screenshots reviewed by hand (HEALTH.md A2): docs/panel.png docs/widgets.png

SOMETHING PRIVATE IS TRACKED (see FAIL above)
```

Exit 1. See A0. The two hits at `PLAN.md:257` and `:284` are the checklist
asserting the very thing that is untrue four files away; they are harmless as
text and will stop matching once the real hit at `OUTPUT.txt:4` is fixed and the
lines are reworded. The probe deliberately allows `127.0.0.1` — oMLX really does
bind to loopback and the README documents it — and deliberately cannot read the
screenshots, so it requires that a human review is recorded instead.

## Appendix 5 — tests

`Tests/MetronTests` (swift-testing) is wired into `Package.swift`. `swift test`:

```
✔ Test run with 48 tests in 12 suites passed after 0.001 seconds.
```

`MetricsTests.swift` was added by this audit and covers what the existing
`ModelTests.swift` / `UsageCacheTests.swift` did not: the byte, rate, token and
duration formatters; `ModelStyle` naming and legend ordering; `UsageSnapshot`
and `LocalHistory` aggregation; `SystemSnapshot` fraction safety; the
KatechonOS model layer including decoding the JSON shape the NAS really prints
and tolerating `{}`; the oMLX status layer including `Model.state` precedence;
and `Headline` severity derivation. Every test is a pure function over values —
no `~/.claude.json`, no ssh, no network, no window server — so the suite runs
anywhere. Finding B3 is pinned by a characterisation test so it cannot be
"fixed" silently.

Still worth writing, and deliberately not attempted here because they need
fixtures rather than values: `TranscriptScanner.aggregate` over a synthetic
`.jsonl` (the line splitter, the `len > 40` prefilter, and the day bucketing are
the highest-traffic untested code in the app), `UsageCache.read` against a
fixture `~/.claude.json` for both the `limits` shape and the pre-`limits`
fallback, and `HeatmapView.grid` week alignment — which is where B1 lives and
where a test would have caught it.
