# Ledger — specification

A Metron glance that answers one question honestly: **what would this month of
Claude Code have cost on the Anthropic API, and what did it produce?**

Two panes, deliberately. A cost figure alone is a brag or a scare. The Ledger
puts equivalent API spend next to evidence of output — commits authored, files
changed, lines written — so the number means something.

Status: specification. Nothing is implemented yet. The reference implementation
in `cost_model.py` is real, runs against the real data, and its verbatim output
is in `OUTPUT.txt`.

---

## 1. `~/.claude/stats-cache.json` — complete schema

This file backs the Claude Code CLI's `/stats` screen (the one with the
All-time / 30-day / 7-day toggle and the by-model tab). Everything below was
verified two ways: against the live file, and against the CLI's own bundled
JavaScript in `~/.local/share/claude/versions/2.1.251` (a Bun single-file
executable; `strings -n 200` recovers the minified source of the stats module
intact).

File: `~/.claude/stats-cache.json`, mode `0600`, ~12 KB, pretty-printed with
2-space indent (`JSON.stringify(cache, null, 2)`), written atomically.

### 1.1 Top level

| Key | Type | Units / semantics |
|---|---|---|
| `version` | int | Cache format version. Currently **5**. On load, a file with `version` in `[1, 5]` is migrated in place; anything outside that range is discarded and the cache is rebuilt from scratch. |
| `lastComputedDate` | string \| null | `YYYY-MM-DD` **watermark**. Everything up to and including this date has been folded into the aggregates. Always **yesterday or earlier** — see §2. If null/unparseable the CLI logs `Stats cache has no usable date` and does a full rescan. |
| `dailyActivity` | array | One entry per day that had activity. Sorted by date ascending. Sparse — days with no Claude Code use on this machine are simply absent. |
| `dailyActivity[].date` | string | `YYYY-MM-DD`, **UTC** (the CLI derives it as `new Date(ts).toISOString().split("T")[0]`). |
| `dailyActivity[].messageCount` | int | Count of transcript entries that day, main transcripts only. Sidechain entries and `subagents/agent-*.jsonl` files are excluded. |
| `dailyActivity[].sessionCount` | int | Sessions whose **first** message fell on that day. Subagent transcripts excluded. |
| `dailyActivity[].toolCallCount` | int | Count of `tool_use` content blocks in assistant messages. Subagent transcripts excluded. |
| `dailyModelTokens` | array | Per-day, per-model token totals. Sorted by date ascending. |
| `dailyModelTokens[].date` | string | `YYYY-MM-DD`, UTC. |
| `dailyModelTokens[].tokensByModel` | object | `model id -> int`. **The int is the SUM of all four token classes** — see §1.3. Includes subagent traffic (unlike `dailyActivity`). |
| `dailyModelTokensVersion` | int | Sub-schema version for `dailyModelTokens`. Currently **5**. If it is below the current constant, that array alone is rebuilt from transcripts and re-saved before anything else happens. |
| `modelUsage` | object | `model id -> usage record`. All-time, cumulative, never reset. |
| `totalSessions` | int | All-time session count. Equals `sum(dailyActivity[].sessionCount)`. Verified: 6,049 = 6,049. |
| `totalMessages` | int | All-time message count. Equals `sum(dailyActivity[].messageCount)`. Verified: 104,169 = 104,169. |
| `longestSession` | object \| null | The single longest session ever seen. |
| `longestSession.sessionId` | string | Transcript basename (a UUID). |
| `longestSession.timestamp` | string | ISO-8601 of the session's **first** message. |
| `longestSession.duration` | int | **Milliseconds.** `last.timestamp - first.timestamp`. The live value 495,332,330 is 137.6 hours — plausible for a long-lived resumed session, absurd (15 years) if read as seconds. Confirmed in source: `let Le = Mo.getTime() - Ut.getTime()`. |
| `longestSession.messageCount` | int | Messages in that session. |
| `firstSessionDate` | string \| null | ISO-8601 timestamp (not a bare date) of the earliest session ever seen. |
| `hourCounts` | object | `"0".."23" -> int`. Count of **sessions started** in that hour, in **local time** (`Date.getHours()`). Sums to `totalSessions`. Verified: 6,049. Note the asymmetry — day buckets are UTC, hour buckets are local. |
| `shotDistribution` | object \| undefined | `"N" -> int`. Optional; **absent** from the live file. Present in the schema and round-tripped when present. Not used by the Ledger. |

### 1.2 `modelUsage[model]`

| Key | Type | Semantics |
|---|---|---|
| `inputTokens` | int | Sum of `usage.input_tokens` — uncached input only. |
| `outputTokens` | int | Sum of `usage.output_tokens`. Includes thinking tokens. |
| `cacheReadInputTokens` | int | Sum of `usage.cache_read_input_tokens`. |
| `cacheCreationInputTokens` | int | Sum of `usage.cache_creation_input_tokens`. **No TTL breakdown** — 5-minute and 1-hour writes are fused, and they are priced differently (1.25x vs 2x base input). This is the single largest source of error in the cheap path. |
| `webSearchRequests` | int | Always **0** in practice. The scanner initialises the field but never writes to it — it only reads the four token fields. |
| `costUSD` | float | Always **0.0**. Same reason. Do not read this expecting a cost; the Ledger must compute its own. |
| `contextWindow` | int | Always **0**. Merged with `Math.max` but never assigned. |
| `maxOutputTokens` | int | Always **0**. Same. |

Model ids appear exactly as the transcript recorded them: bare (`claude-opus-5`,
`claude-sonnet-5`, `claude-fable-5`, `claude-opus-4-8`, `claude-opus-4-6`) or
date-suffixed (`claude-haiku-4-5-20251001`). Non-Anthropic models routed through
Claude Code appear verbatim too — this machine has two oMLX-served local models,
`Qwen3.6-27B-Jormungandr-oQ8-Tess-mtp` and `Qwen3.8-27B-Brainwaves-Tess-oQ4-mtp`.
The literal id `<synthetic>` is skipped by the CLI and must be skipped by us.

### 1.3 `tokensByModel` is the four-way sum — verified

The CLI source is unambiguous:

```js
let On = In + Go + Ko + zo;              // input + output + cacheRead + cacheCreation
if (On > 0) { Ln[jt] = (Ln[jt] || 0) + On; }
```

Cross-checked numerically against `modelUsage`, summing `dailyModelTokens` over
every day:

| model | Σ dailyModelTokens | modelUsage all four | ratio |
|---|---:|---:|---:|
| claude-opus-5 | 11,682,326,152 | 11,682,326,152 | 1.0000 |
| claude-fable-5 | 3,715,624,350 | 3,715,624,350 | 1.0000 |
| claude-opus-4-8 | 2,040,088,436 | 2,040,088,436 | 1.0000 |
| claude-sonnet-5 | 217,911,306 | 217,911,306 | 1.0000 |
| claude-haiku-4-5-20251001 | 117,283,634 | 117,283,634 | 1.0000 |
| claude-opus-4-6 | 19,876,428 | 19,876,428 | 1.0000 |
| Qwen3.6-27B-Jormungandr-oQ8-Tess-mtp | 8,460,004 | 8,460,004 | 1.0000 |
| Qwen3.8-27B-Brainwaves-Tess-oQ4-mtp | 326,269 | 326,269 | 1.0000 |
| **total** | **17,801,896,579** | **17,801,896,579** | **1.0000** |

Exact to the token, for every model. The daily array is a lossy projection of
the same data the all-time record holds losslessly.

---

## 2. How the file is written and refreshed

**Which process.** The `claude` CLI itself, in-process, on the path that renders
the `/stats` screen. There is no daemon or background writer for this file. It
is written only when a human opens `/stats` (or another surface that calls the
same aggregator). If you never open `/stats`, the file never advances.

**The refresh algorithm**, from the recovered source:

1. Enumerate every `~/.claude/projects/*/*.jsonl` plus
   `~/.claude/projects/*/*/subagents/agent-*.jsonl`, capturing each file's
   `mtimeMs`.
2. Load the cache. If `version != 5`, migrate or discard.
3. **Future-clock guard.** If `lastComputedDate` is in the future but within 7
   days of today, log `Stats watermark X is ahead of Y; skipping the
   dailyModelTokens rebuild until the clock catches up` and skip step 4.
4. If `dailyModelTokensVersion < 5`, rebuild just `dailyModelTokens` from
   transcripts through the watermark and save.
5. Then one of:
   - watermark null → `Stats cache empty, processing all historical data`, scan
     everything through **yesterday**, save.
   - watermark < yesterday → `Stats cache stale (X), processing X+1 to
     yesterday`, scan that range only, **merge** into the cache, save.
   - watermark == yesterday → nothing to do.
6. Separately scan **today only** and merge the result into the in-memory view
   for display. **This is never written to disk.**

**Consequences that matter to the Ledger:**

- The on-disk file **always stops at yesterday**. `lastComputedDate` was
  `2026-08-29` while the file's mtime was `2026-08-30 11:54`. Today's numbers
  are simply not in the file. A Ledger reading only this file is always at
  least one day behind, and shows a partial final day if it reads
  `lastComputedDate` naively.
- The merge (`_l` in the source) is **additive and monotonic** for every field:
  `dailyActivity` counters are summed per date, `tokensByModel` values are
  summed per date+model, `modelUsage` fields are summed, `hourCounts` are
  summed, `longestSession` takes the max by duration, `firstSessionDate` takes
  the min. **Nothing is ever removed or aged out.**
- **The file is not truncated or rolling.** The 34 days present are simply the
  34 days with activity; `firstSessionDate` 2026-06-20 is present as the very
  first `dailyActivity` entry. The gaps (2026-06-24 → 2026-07-20, and scattered
  days after) are days with no Claude Code use on this machine. There is no
  retention window in the stats module. Transcripts *are* pruned by a separate
  cleanup, but the aggregate they were folded into survives that pruning.
- **The incremental scan skips files by mtime.** A file whose mtime predates
  `fromDate` is not opened. That is a correctness hazard if a transcript is
  ever back-dated, and it also means the cache can lag mid-day activity.
- **The cache lags the transcripts.** Reconciling the transcript scan against
  `modelUsage` (clipped to the same watermark) gives ratio 1.000 for five
  models but 1.091 / 1.040 / 1.023 for opus-5 / fable-5 / opus-4-8 — sessions
  active on 2026-08-29 after `/stats` was last opened are on disk in the
  transcripts but not yet folded into the cache.

**Recommended Ledger read strategy:** treat `stats-cache.json` as a cheap
warm-start and a cross-check, not as the source of truth. See §4.

---

## 3. Can the four-way split be recovered per day, per model, from transcripts?

**Yes — and better than four-way.** The transcripts carry a full five-way split,
because they break cache writes down by TTL, which `stats-cache.json` cannot.

Each assistant turn is one JSONL line in
`~/.claude/projects/<project-key>/<sessionId>.jsonl`
(or `.../subagents/agent-*.jsonl`). The fields the Ledger needs:

| JSONL path | Type | Use |
|---|---|---|
| `type` | string | Must equal `"assistant"`. |
| `isSidechain` | bool | In a **main** transcript, skip when true (the CLI does). In a `subagents/agent-*.jsonl` file, keep everything. |
| `timestamp` | string | ISO-8601 with fractional seconds. Day bucket. |
| `sessionId` | string | Session identity. |
| `message.model` | string | Model id. Skip `"<synthetic>"`. |
| `message.usage.input_tokens` | int | Uncached input. |
| `message.usage.output_tokens` | int | Output, thinking included. |
| `message.usage.cache_read_input_tokens` | int | Cache hits. |
| `message.usage.cache_creation_input_tokens` | int | Total cache write (fused). |
| `message.usage.cache_creation.ephemeral_5m_input_tokens` | int | **Cache write at the 1.25x rate.** |
| `message.usage.cache_creation.ephemeral_1h_input_tokens` | int | **Cache write at the 2.0x rate.** |
| `message.usage.server_tool_use.web_search_requests` | int | $10 / 1,000 searches. |
| `message.usage.service_tier` | string | `"standard"` — guard against `"batch"`/priority repricing. |
| `message.usage.speed` | string | `"standard"` or `"fast"`. Fast mode on Opus 5 / 4.8 is priced at $10/$50, double standard. |
| `message.usage.iterations[]` | array | Per-iteration repeat of the same counters. **Do not add these to the top-level counters — they are the same tokens.** |

A real record from this machine:

```json
"usage": {
  "input_tokens": 2,
  "cache_creation_input_tokens": 31444,
  "cache_read_input_tokens": 37801,
  "output_tokens": 630,
  "output_tokens_details": { "thinking_tokens": 291 },
  "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
  "service_tier": "standard",
  "cache_creation": {
    "ephemeral_1h_input_tokens": 31444,
    "ephemeral_5m_input_tokens": 0
  },
  "speed": "standard"
}
```

**How much this matters.** Across this machine's transcripts, clipped to the
cache watermark:

```
cache writes: 196,476,288 at 5m,  451,987,661 at 1h   (69.7% at the 2x rate)
```

Nearly 70% of all cache-write tokens were written at the doubled 1-hour rate.
`stats-cache.json` cannot see that at all. Assuming the 5-minute rate — the only
choice available from the cheap path — understates the true bill by roughly 18%
all-time on this data, and 22% on the peak day.

**Verdict: the transcripts are strictly better and the Ledger should use them.**
They give a true per-day, per-model, five-way split; they include today; and
they carry web-search counts, service tier and speed. Metron already walks these
files in `Sources/Metron/Glances/Usage/TranscriptScanner.swift` — the Ledger is
mostly a matter of widening what that scanner keeps.

**Cost of the scan.** The Python reference does the whole thing — 6,917 files,
covering 35 UTC days — in **1.5 seconds** cold. `TranscriptScanner` already
does a byte-level prefilter and caches per-file aggregates keyed on
(size, mtime), so in Swift it will be faster still and near-free on refresh.

**Two things the transcripts do NOT give you**, for which `stats-cache.json`
remains the only source:

1. History older than the transcript retention window. Claude Code prunes old
   `.jsonl` files; the cache's `modelUsage` / `dailyModelTokens` keep the
   aggregate forever. On this machine the two currently overlap, but they will
   diverge.
2. `totalSessions`, `totalMessages`, `firstSessionDate`, `longestSession`,
   `hourCounts` in their all-time form.

**So: read both.** Transcripts for everything inside the retention window;
`stats-cache.json` for the all-time floor and the lifetime counters.

### 3.1 One trap: day boundaries

The CLI buckets days by **UTC** date (`toISOString().split("T")[0]`).
`TranscriptScanner` currently buckets by **local** `startOfDay`. These disagree
by up to a day at the edges. The Ledger must pick one and say which. **Pick
local** — the user's day is what a "cost per day" chart means to a human — and
accept that Ledger daily figures will not tie exactly to `/stats` daily figures.
Note the difference in the UI's info text rather than silently diverging.

---

## 4. Pricing

Source: <https://platform.claude.com/docs/en/about-claude/pricing>, fetched
**2026-08-31**. USD per million tokens.

| Model | Input | 5m cache write | 1h cache write | Cache read | Output |
|---|---:|---:|---:|---:|---:|
| `claude-fable-5` | $10.00 | $12.50 | $20.00 | $1.00 | $50.00 |
| `claude-opus-5` | $5.00 | $6.25 | $10.00 | $0.50 | $25.00 |
| `claude-opus-4-8` | $5.00 | $6.25 | $10.00 | $0.50 | $25.00 |
| `claude-opus-4-7` | $5.00 | $6.25 | $10.00 | $0.50 | $25.00 |
| `claude-opus-4-6` | $5.00 | $6.25 | $10.00 | $0.50 | $25.00 |
| `claude-sonnet-5` | $2.00 | $2.50 | $4.00 | $0.20 | $10.00 |
| `claude-sonnet-4-6` | $3.00 | $3.75 | $6.00 | $0.30 | $15.00 |
| `claude-haiku-4-5` | $1.00 | $1.25 | $2.00 | $0.10 | $5.00 |

The cache columns are not independent prices; they are multipliers on base
input — **1.25x** for a 5-minute write, **2.0x** for a 1-hour write, **0.1x**
for a read. Encode them as multipliers so a base-price change stays consistent.

**Every Claude model in this data has a public API price.** The task brief
anticipated that Fable 5 and the 4.8 / 4.6 Opus revisions might be unpriced;
they are not. Fable 5 is $10/$50 — twice Opus-tier — and Opus 4.8 and 4.6 carry
the same $5/$25 as Opus 5. No fallback is needed for anything currently in the
file.

**Fallback policy for a model id with no entry** (a future release, or a
snapshot id whose bare form is unknown):

1. Strip a trailing 8-digit date (`claude-haiku-4-5-20251001` →
   `claude-haiku-4-5`) and retry. This resolves every dated snapshot Claude Code
   currently writes.
2. Failing that, match on tier by name — `fable`/`mythos` → Fable rates,
   `opus` → Opus rates, `sonnet` → Sonnet 5 rates, `haiku` → Haiku 4.5 rates.
3. Failing that, price the model at **Opus rates** and flag the row
   `estimated` in the UI. Opus is the modal tier here; guessing low would
   flatter the number, and the Ledger's whole point is not to flatter it.

Never silently drop an unpriced model from the total — a missing row reads as
"this was free".

**Non-Claude models are $0 and labelled `local`.** The two `Qwen3.*` entries are
oMLX-served models running on this machine. They consumed 8.8 M tokens and cost
nothing but electricity. Show them in the model list at $0.00 with a `local`
badge, both because it is true and because it makes the point that some of the
work moved off the meter.

**Modifiers not yet applied by the reference implementation**, worth wiring in
when the Swift version reads `usage` fully:

- Web search: **$10 per 1,000 requests** on top of tokens. Currently 0 here.
- Fast mode (`usage.speed == "fast"`, Opus 5 / 4.8 only): $10 input / $50
  output, with cache multipliers applied on top of *those*.
- `inference_geo: "us"`: a flat **1.1x** on every token class.
- Batch tier: 50% off. Not reachable from Claude Code.

---

## 5. Formulas

Let a bucket be (day, model) with counters `in, out, read, w5m, w1h, searches`.

```
cost(bucket) = ( in   * price.input
               + out  * price.output
               + read * price.input * 0.10
               + w5m  * price.input * 1.25
               + w1h  * price.input * 2.00 ) / 1e6
             + searches * 10.0 / 1000
```

Window totals are plain sums over the buckets in the window. Windows are
inclusive and anchored on the newest day with data, not on `Date()` — a machine
that was idle yesterday should not show a 7-day window with an empty last cell.

```
allTime  = Σ cost(b) for every b
last30d  = Σ cost(b) where anchor-29 <= day <= anchor
last7d   = Σ cost(b) where anchor-6  <= day <= anchor
peakDay  = max over days of Σ_model cost(day, model)

costPerCalendarDay = allTime / (anchor - firstDay + 1)
costPerActiveDay   = allTime / countOfDaysWithAnyCost
subscriptionPaid   = 200.0 * (spanDays / 30.4375)
multiple           = allTime / subscriptionPaid
monthMultiple      = last30d / 200.0
breakEvenDays      = 200.0 / (last30d / 30)
```

`30.4375` is 365.25/12 — the average month. Using 30 would overstate the
multiple by ~1.5%; not much, but the Ledger's credibility is the product.

**The cheap path** (stats-cache only), when a transcript scan is unavailable or
too slow, estimates a daily cost from the fused token count via each model's
all-time blended rate:

```
blended(model) = cost(modelUsage[model]) / totalTokens(modelUsage[model])
cost(day, model) ≈ tokensByModel[model] * blended(model)
```

This is an approximation and must be labelled as one wherever it is shown.

---

## 6. Accuracy — measured, not asserted

Both paths were run against the real file. Verbatim output in `OUTPUT.txt`.

| Window | stats-cache estimate | transcript exact | understatement |
|---|---:|---:|---:|
| all-time (through 2026-08-29) | $16,697.80 | **$20,268.38** | 17.6% |
| last 30 days | $15,865.30 | **$18,976.10** | 16.4% |
| last 7 days | $7,616.90 | **$8,879.58** | 14.2% |
| peak day | $2,324.63 (08-22) | **$2,998.18** (08-25) | 22.5% |

Two independent errors compound in the cheap path:

1. **The blended-ratio error.** `tokensByModel` fuses four classes whose prices
   span 500:1 (a cache read at $0.50/MTok against an output token at
   $25/MTok on Opus 5). Recovering a cost requires assuming the day had the
   model's all-time average mix. A day of long generations is understated; a
   day of long context re-reads is overstated. Note that the two paths do not
   even agree on **which day was the peak** — 08-22 by estimate, 08-25 by
   measurement. Any UI that highlights "your most expensive day" must use the
   exact path or it will point at the wrong day.

2. **The cache-TTL error, which is larger.** `modelUsage` fuses 5-minute and
   1-hour cache writes, so the cheap path must assume one; assuming the cheaper
   5-minute rate is the only defensible choice, and on this data 69.7% of write
   tokens were actually at the doubled 1-hour rate. This alone accounts for most
   of the gap.

A third, smaller effect runs the other way: the cache lags the transcripts by
however long it has been since `/stats` was last opened (up to +9% on opus-5
here), so part of the "understatement" is really "staleness".

**Design consequence.** Ship the transcript path as the default. It costs 1.5
seconds in Python and less in Swift with the existing mtime cache. Use the
stats-cache path only for the very first paint before the scan lands, and mark
those figures `approx` until it does.

**Standing caveat for the UI**, verbatim, in the panel's footer:

> Equivalent API cost at published list prices. Not a bill. Subscription usage
> is not metered this way, and this figure includes cache reads that a
> pay-as-you-go workload would have been structured to avoid.

That last clause matters and should not be dropped. Roughly 96% of these tokens
are cache reads. An agentic harness leans on caching precisely *because* it is
cheap; the same work, driven through the API without Claude Code's caching
discipline, would cost differently again. The number is an honest upper-ish
bound on "what this pattern of work is worth at list price", not a
counterfactual invoice.

---

## 7. Headline numbers, on the real data (2026-08-31)

Span 2026-06-20 → 2026-08-29, 71 calendar days, 33 active. 6,049 sessions,
104,169 messages, 17.8 billion tokens.

| | |
|---|---:|
| **All-time equivalent API cost** | **$20,268.38** |
| **Last 30 days** | **$18,976.10** |
| **Last 7 days** | **$8,879.58** |
| **Peak single day** (2026-08-25) | **$2,998.18** |
| **Multiple vs $200/mo Max** (71 d, $466.53 paid) | **43.4x** |
| Last 30 days vs one $200 month | 94.9x |
| Peak day alone vs one $200 month | 15.0x |
| Break-even at the last-30-day rate | 0.32 days |

Per model, all-time (exact four-way split, 5-minute write rate — so these are
the *conservative* figures):

| model | tokens | cost | $/MTok blended |
|---|---:|---:|---:|
| claude-opus-5 | 11,682,326,152 | $8,840.20 | 0.757 |
| claude-fable-5 | 3,715,624,350 | $6,076.45 | 1.635 |
| claude-opus-4-8 | 2,040,088,436 | $1,654.32 | 0.811 |
| claude-sonnet-5 | 217,911,306 | $82.15 | 0.377 |
| claude-opus-4-6 | 19,876,428 | $22.72 | 1.143 |
| claude-haiku-4-5 | 117,283,634 | $21.97 | 0.187 |
| Qwen3.6-27B-… (local) | 8,460,004 | $0.00 | — |
| Qwen3.8-27B-… (local) | 326,269 | $0.00 | — |

Fable 5 is worth calling out in the UI: 21% of the tokens, 36% of the cost.
It is the only model here whose blended rate exceeds $1/MTok by a wide margin,
and it is the one lever that visibly moves the total.

---

## 8. The counterweight — evidence of output

A cost panel with no output panel is a guilt meter. The Ledger's second pane
answers "and what came out of it", from git, across the user's repositories.

### 8.1 What to show

| Metric | Why it earns its place |
|---|---|
| **Commits authored** | The least gameable unit of finished work. Primary. |
| **Files changed** | Breadth. Robust to a single generated blob. |
| **Lines added / removed** | Volume. Noisiest — needs the filter in §8.3. |
| **Repositories touched** | How many fronts were open. |
| **Active days** | Days with at least one commit, against days with cost. The ratio "days you paid for vs days you shipped" is the honest one. |
| **Sessions** (from stats-cache) | Effort denominator. |
| **Tool calls** (from stats-cache) | Machine effort per unit of human output. |

And the two derived figures that make it a ledger rather than two lists:

- **$ per commit** — `windowCost / commitsInWindow`
- **$ per file changed** — `windowCost / filesChangedInWindow`

Never phrase these as a verdict. Label them "at list price", show them next to
the raw counts, and let the user decide whether $23.87 a commit is a bargain.

### 8.2 How to source it

Root: `~/Projects` (configurable; default to the parent of the Metron checkout
so it works out of the box). One level deep, each entry containing a `.git`
directory. Skip worktree/archive directories by name pattern.

Per repository, one `git log` invocation, no working-tree touch, no network:

```sh
git -C <repo> log \
    --since=<ISO date> \
    --author=<user email> \
    --numstat --format='%H%x09%ad' --date=short \
    -- . <exclusions>
```

Parse: a `%H\t%ad` line starts a commit; subsequent 3-field lines are
`added \t removed \t path`. A `-` in either numeric field means binary — count
the file, not the lines. Bucket by the `%ad` date so the output series aligns
with the cost series day for day.

Author filter: `git config user.email`, falling back to `--author=$(whoami)`.
Restricting to the user's own commits keeps vendored history and merged upstream
work out of the count.

Cache per repo on `.git/HEAD` mtime + `git rev-parse HEAD`; only re-run when
HEAD moved. Across 37 directories this is well under a second warm.

### 8.3 The line-count filter, and why it is mandatory

Unfiltered, the last 30 days across `~/Projects` reads:

```
TOTAL  795 commits  +1,297,066  -63,992  6,479 file-changes
```

That +1.3 M is a lie of composition: GeoDex alone contributes +889,397, almost
all of it checked-in geographic data. With generated and vendored paths excluded:

```
TOTAL  795 commits    +624,981  -54,075  5,606 file-changes   (27 active days)
```

Still GeoDex-heavy, but no longer absurd. The exclusion pathspec:

```
:(exclude)*.lock  :(exclude)*-lock.json  :(exclude)*.pbxproj
:(exclude)vendor/**  :(exclude)third_party/**  :(exclude)**/node_modules/**
:(exclude)Pods/**  :(exclude)*.min.js  :(exclude)*.svg
:(exclude)*.json  :(exclude)*.csv
```

Excluding `*.json` and `*.csv` wholesale is blunt and will undercount real
config work. That is the right direction to be wrong in: **the counterweight
must never be able to flatter itself.** A number that can be inflated by
committing a data file is not evidence.

Because of all this, **commits and files changed are the headline; lines are
secondary and shown with a "filtered" marker.** Line counts should never be the
denominator of a dollar figure.

Per-repo detail for the 30-day window (filtered) is in the run captured while
writing this spec: GeoDex 141 commits, Praus 125, Dropo 99, Katechon 92,
Vasa 81, Bots 67, Plethos 39, system-project 29, auto-git-discovery 26,
viscom 21, Loom 20, Atlas 18, Thyra 14, Metron 8, Maker 6, Aethelia 4, DMN 4,
live-otio 1.

---

## 9. UI

Fits the existing architecture: a `GlanceStore` subclass registered in
`GlanceRegistry.all`, returning a view per `GlanceSize`, exactly as `UsageStore`
does. Colours from `Theme` — `Theme.accent` for cost, `Theme.cool` for the
output series, `Theme.severity` untouched (cost has no ceiling, so no severity
ramp). Type from `Theme.mono` / `Theme.rounded`.

```
LedgerStore : GlanceStore
  id      "ledger"
  name    "Ledger"
  symbol  "scalemass"          // a balance — cost against output
  defaultRefreshSeconds  900   // 15 min; the underlying data moves slowly
  refreshChoices  [300, 900, 3600, 21600]
```

`load()` runs three things concurrently, mirroring `UsageStore.load()`:

```swift
async let ledger  = TokenLedgerScanner.shared.scan()   // transcripts, five-way
async let cache   = StatsCacheReader.read()            // all-time floor + lifetime counters
async let output  = GitOutputScanner.shared.scan()     // commits/files/lines
```

Seed from `LastGood` on init so the panel comes up populated, and keep the last
good reading on a failed refresh — the same discipline as `UsageStore`.

`headline`: no natural ceiling, so `fraction` is nil and the SF Symbol shows.
`text` is the 30-day figure, abbreviated — `"$19.0k"`. This is the one design
decision worth arguing about; a running dollar figure in the menu bar is either
useful or oppressive depending on the person. Ship it behind the existing
`showTextInMenuBar` toggle, which already exists and already defaults on.

`subtitle`: `"$18,976 / 30d · 95x subscription"`, or
`"Approx — scanning transcripts"` while the first scan is in flight.

### Small (176 x 176) — the number

`WidgetHeader(symbol:"scalemass", title:"Ledger", tint:.accent)`, then one
figure and one comparison. No chart; there is no room for an honest one.

```
┌──────────────────┐
│ ⚖  Ledger        │
│                  │
│      $19.0k      │   Theme.mono(30, .semibold), Theme.accent
│      last 30d    │   Theme.rounded(10), .secondary
│                  │
│      95x  $200/mo│   Theme.mono(13, .medium)
└──────────────────┘
```

### Medium (376 x 176) — cost against output

Split. Left: the money. Right: what came of it. A vertical hairline
(`Theme.hairline`) between them carries the whole argument.

```
┌───────────────────────┬───────────────────────┐
│ ⚖  Ledger        30d  │                       │
│                       │   795   commits       │
│    $18,976            │   5,606 files         │
│    equivalent API     │   18    repos         │
│                       │   27    active days   │
│    95x  a $200 month  │                       │
│                       │   $23.87 per commit   │
└───────────────────────┴───────────────────────┘
```

### Large (376 x 376) — add the series

Medium's two columns, then a 30-column daily bar chart with two series sharing
an x-axis: cost bars in `Theme.accent`, commit bars in `Theme.cool`, drawn as a
mirrored pair around a centre line. The shape of the divergence *is* the
insight — the days that cost the most are not always the days that shipped the
most, and the panel should let the user see that rather than assert it.

Below the chart, the model split as a stacked horizontal bar with a legend,
reusing the layout idea from `ModelBreakdown.swift`, sorted by cost. `local`
models render as an outlined segment rather than a filled one.

```
┌───────────────────────────────────────────────┐
│ ⚖  Ledger                     last 30 days    │
├───────────────────────┬───────────────────────┤
│  $18,976              │  795  commits         │
│  95x a $200 month     │  5,606 files · 18 repos│
├───────────────────────┴───────────────────────┤
│  cost   ▁▂▅█▃▂▇█▄▃▅█▂▁▃▅▇█▄▂▃▅▆█▃▂▁▄▆         │
│  ────────────────────────────────────────      │
│  work   ▂▃▁▄▅▂▃▆▅▂▄▃▁▂▅▄▃▇▅▃▂▄▅▃▂▄▃▅▂▁        │
├───────────────────────────────────────────────┤
│  opus-5   ████████████░░░░░░  $8,840   47%    │
│  fable-5  ████████░░░░░░░░░░  $6,076   32%    │
│  opus-4.8 ██░░░░░░░░░░░░░░░░  $1,654    9%    │
│  sonnet-5 ░░░░░░░░░░░░░░░░░░     $82    0.4%  │
│  qwen3.8  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  local           │
└───────────────────────────────────────────────┘
```

### Full — the panel

Everything, in `PanelChrome`, matching `PanelView.swift`'s structure:

1. **Header** — the 30-day figure large, the multiple beside it, the window
   selector (All-time / 30d / 7d) as a segmented control mirroring the CLI's own
   `/stats` toggle.
2. **Three stat tiles** — equivalent API cost, subscription paid, multiple.
3. **Daily chart**, full width, cost and commits mirrored, hover for a day's
   detail: exact cost, four-way token split, commits, repos touched.
4. **Model table** — model, tokens, input / output / cache-read / cache-write
   columns, cost, share. Local models at $0 with the badge.
5. **Output table** — per repository: commits, files, +/- lines (filtered),
   last commit date.
6. **Lifetime strip**, from `stats-cache.json` — total sessions, total messages,
   longest session (formatted from the millisecond duration), first session
   date, peak hour from `hourCounts`.
7. **Footer** — the standing caveat from §6, the pricing source URL and the
   fetch date, and whether the current figures are exact (transcript scan
   complete) or approximate (stats-cache fallback). This footer is not
   decoration; it is the reason the panel is allowed to show a number this
   large.

### Refresh and staleness

The transcript scan is the expensive part and is already incremental. On a
15-minute timer the marginal cost is a handful of changed files. Show
`updatedLine` from `GlanceStore` unchanged. If the git scan fails (no repos, no
`git`), the output pane shows `UnavailableMark` and the cost pane stands alone —
degrade to half a panel, never to no panel.

---

## 10. Files

- `docs/ledger/cost_model.py` — reference implementation. Runs against the real
  file with no arguments; `--transcripts` adds the exact scan and the delta
  table.
- `docs/ledger/OUTPUT.txt` — verbatim output of
  `python3 docs/ledger/cost_model.py --transcripts` on 2026-08-31.
- `docs/ledger/SPEC.md` — this document.

Nothing under `Sources/` has been touched.
