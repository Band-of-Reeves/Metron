# Changelog

Notable changes to Metron. Dates are the date of the commit.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- A test target (`swift test`) covering the pure logic: limit-window naming and
  plan labels, the severity ramp, widget geometry, snapshot round-tripping, and
  ZFS size parsing.
- Continuous integration on macOS: build, test, the build-only portion of
  `verify.sh`, and a universal app bundle uploaded as an artifact. Tagging `v*`
  publishes a release.
- `build.sh` can produce a universal binary (`METRON_UNIVERSAL=1`) and sign with
  a real identity (`METRON_SIGN_ID=...`).
- `verify.sh` takes `METRON_VERIFY_CI=1`, which runs the checks that do not need
  live local data and reports the rest as skipped rather than passing them.
- `CONTRIBUTING.md`, issue templates, and this changelog.

### Changed
- `build.sh` stamps the version from the git tag, and no longer swallows
  codesign failures — an unsigned bundle used to fail to launch much later with
  no explanation. Dropped the deprecated `--deep`, which the bundle never needed
  since it contains no nested code.

### Fixed
- Xcode's per-user state (`xcuserdata`) is no longer tracked. It carried the
  checkout owner's username in its path.

## [1.0] — 2026-08-28

The first working version: a menu bar app with four independent glances.

### Added
- **Claude usage** glance — limit rings for every window the account reports,
  a menu bar glyph tracking whichever window is closest to its ceiling, an
  18-week activity heatmap built from local transcripts, a model split, and the
  usage drivers. (`89b6683`)
- **System**, **oMLX** and **KatechonOS** glances, each with its own menu bar
  slot, refresh cadence and desktop widget in four sizes. Only Claude usage is
  on by default. (`59f61c3`)
- Documentation and an MIT licence. (`2e4a77f`)
- `verify.sh` — one command that answers "is this actually working?", asserting
  on each glance's headline rather than on the render succeeding, because a
  glance that renders with nothing to show is the failure that looks like
  success. (`c492c0e`)

### Changed
- The limit rings read `cachedUsageUtilization` from `~/.claude.json` — Claude
  Code's own cache — instead of shelling out to `claude -p "/usage"`. It is
  instant rather than a twenty-second subprocess, needs no credential, and does
  not depend on a slash command choosing to print anything, which is exactly
  what stopped happening. The tradeoff: the cache only moves when Claude Code
  runs, and the panel says so rather than pretending. (`875561a`)
- The usage panel is titled "Claude usage" rather than "Metron", now that it is
  one glance among several. (`c77568a`)

### Fixed
- Popovers were clipping the top of every panel: the panel grew after the
  popover had been sized. `Metron --measure` now checks each popover against
  its panel so a headless run can catch the regression. (`827a73c`)
- A source that went quiet would blank the panel. A stale reading beats no
  reading, so the last good snapshot is kept and labelled. (`40d923e`)

[Unreleased]: https://github.com/Band-of-Reeves/Metron/compare/v1.0...HEAD
[1.0]: https://github.com/Band-of-Reeves/Metron/releases/tag/v1.0
