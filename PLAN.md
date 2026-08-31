# Metron: first public release under the new org

<!-- dropo:order version=1 unit=Watchman -->

A shared plan several agents read and amend. Change it with `dropo amend`, not by hand — the
anchors below are how a section keeps its name while its text changes, and how an unlogged
edit becomes detectable.

## Goal
<!-- dropo:goal last=FRAGORD-20260831-1529-WATCHMAN h=acf57eb0 -->
Publish Metron — a macOS menu bar app of independent glances — as the first public repo of the new GitHub organization, with its Claude-usage glance extended into a full Ledger built on the CLI's own stats cache (all-time / 30d / 7d, per model, and the equivalent-API-cost conversion), so that the release is both a working tool and the evidence base for the cost-vs-output argument.

## Ownership
<!-- dropo:owners last=FRAGORD-20260831-1540-WATCHMAN h=7fee652c -->
One owner per path. Anyone not listed owns nothing and may only read. This single table is
what stops two agents from overwriting each other. You are already in it: whoever ran `init`
is the one person here who is certainly authorised, and a plan whose first command locks out
its own author teaches the wrong lesson about failing closed. A blank *may write* means
unrestricted — narrow it before a second unit arrives.

| Who | May write | Must not touch |
|---|---|---|
| Watchman | | |
| LEDGER | `docs/ledger/**`, `Sources/Metron/Glances/Usage/**` |  |
| AUDIT | `docs/audit/**`, `Tests/**` |  |
| RELEASE | `docs/release/**`, `.github/**`, `CONTRIBUTING.md`, `CHANGELOG.md`, `build.sh`, `verify.sh`, `Package.swift`, `.gitignore`, `README.md` |  |

## Status
<!-- dropo:board last=FRAGORD-20260831-1706-WATCHMAN h=93c4a085 -->
Every row names the command that proves it. `dropo verify` runs them. A row that names no
command is not failing — it is somebody's word, and it will say so.

*States: anything starting **green/ok/pass/good/healthy/up/live/done/complete** claims good,
anything starting **red/fail/down/broken/blocked/amber/degraded** claims bad, and anything else —
`not yet proven` — claims nothing. A claim that contradicts its own probe fails the board in
either direction. `RED (expected)` is the one exemption, and it expires the moment it passes.
A probe that needs longer than 15s declares a budget after the command: `bash slow.sh` ~30s.
Full vocabulary: `dropo help board`.*

| Component | State | Evidence | As of |
|---|---|---|---|
| this-plan-exists | GREEN | `test -f PLAN.md` | 2026-08-31 |
| builds | GREEN | `swift build -c release` | 2026-08-31 |
| tests-exist | GREEN | `swift test` | 2026-08-31 |
| live-data-holds | not yet proven | `./verify.sh` ~10m | 2026-08-31 |
| ledger-spec | GREEN | `test -f docs/ledger/SPEC.md` | 2026-08-31 |
| health-audit | GREEN | `test -f docs/audit/HEALTH.md` | 2026-08-31 |
| release-plan | GREEN | `test -f docs/release/PLAN.md` | 2026-08-31 |
| no-private-paths | GREEN | `bash docs/audit/no-private-paths.sh` | 2026-08-31 |
| ci-workflow | GREEN | `test -f .github/workflows/ci.yml` | 2026-08-31 |
| release-builds-universal | GREEN | `bash docs/release/check-universal.sh` ~3m | 2026-08-31 |
| ledger-sources-agree | GREEN | `bash docs/ledger/reconcile.sh` ~2m | 2026-08-31 |
| popover-sizing | GREEN | `.build/release/Metron --measure` ~2m | 2026-08-31 |
| signed-build | GREEN | `bash docs/release/check-signature.sh` | 2026-08-31 |

## Change log
<!-- dropo:changelog -->
Append-only, newest last. Written by `dropo amend` — ids come from the clock and the author,
so two agents changing this at once cannot collide.
- **FRAGORD-20260831-1529-WATCHMAN** — changes ¶goal: state the operation — all else in effect.
- **FRAGORD-20260831-1529-WATCHMAN.b** — changes ¶owners: adds LEDGER — owns docs/ledger/**, Sources/Metron/Glances/Usage/** — all else in effect.
- **FRAGORD-20260831-1529-WATCHMAN.c** — changes ¶owners: adds AUDIT — owns docs/audit/**, Tests/** — all else in effect.
- **FRAGORD-20260831-1529-WATCHMAN.d** — changes ¶owners: adds RELEASE — owns docs/release/**, .github/**, CONTRIBUTING.md, CHANGELOG.md — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN** — changes ¶board: adds builds — GREEN, proved by `swift build -c release` — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.b** — changes ¶board: adds tests-exist — RED (expected), proved by `swift test` — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.c** — changes ¶board: adds live-data-holds — not yet proven, proved by `./verify.sh` — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.d** — changes ¶board: adds ledger-spec — not yet proven, proved by `test -f docs/ledger/SPEC.md` — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.e** — changes ¶board: adds health-audit — not yet proven, proved by `test -f docs/audit/HEALTH.md` — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.f** — changes ¶board: adds release-plan — not yet proven, proved by `test -f docs/release/PLAN.md` — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.g** — changes ¶board: adds no-private-paths — not yet proven, proved by `bash docs/audit/no-private-paths.sh` — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.h** — changes ¶board: live-data-holds evidence now `./verify.sh` ~10m — all else in effect.
- **FRAGORD-20260831-1530-WATCHMAN.i** — changes ¶board: drop the placeholder row — all else in effect.
- **FRAGORD-20260831-1539-WATCHMAN** — changes ¶board: tests-exist RED (expected) → GREEN — all else in effect.
- **FRAGORD-20260831-1539-WATCHMAN.b** — changes ¶board: release-plan not yet proven → GREEN — all else in effect.
- **FRAGORD-20260831-1539-WATCHMAN.c** — changes ¶board: adds ci-workflow — GREEN, proved by `test -f .github/workflows/ci.yml` — all else in effect.
- **FRAGORD-20260831-1539-WATCHMAN.d** — changes ¶board: adds release-builds-universal — GREEN, proved by `bash docs/release/check-universal.sh` ~3m — all else in effect.
- **FRAGORD-20260831-1540-WATCHMAN** — changes ¶owners: RELEASE — owns +build.sh +verify.sh +Package.swift +.gitignore +README.md — all else in effect.
- **FRAGORD-20260831-1544-WATCHMAN** — changes ¶board: no-private-paths not yet proven → GREEN — all else in effect.
- **FRAGORD-20260831-1545-WATCHMAN** — changes ¶board: ledger-spec not yet proven → GREEN — all else in effect.
- **FRAGORD-20260831-1545-WATCHMAN.b** — changes ¶board: health-audit not yet proven → GREEN — all else in effect.
- **FRAGORD-20260831-1610-WATCHMAN** — changes ¶board: adds ledger-sources-agree — GREEN, proved by `bash docs/ledger/reconcile.sh` ~2m — all else in effect.
- **FRAGORD-20260831-1657-WATCHMAN** — changes ¶board: adds popover-sizing — GREEN, proved by `.build/release/Metron --measure` ~2m — all else in effect.
- **FRAGORD-20260831-1706-WATCHMAN** — changes ¶board: adds signed-build — GREEN, proved by `bash docs/release/check-signature.sh` — all else in effect.
