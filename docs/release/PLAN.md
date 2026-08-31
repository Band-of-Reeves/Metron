# Metron release plan

Written 2026-08-31, for the move from a personal repo to the first public repo
under the **Band-of-Reeves** organisation.

Everything below is decided rather than surveyed. Where a decision has a real
cost, the cost is stated.

---

## 1. Build system: stay on SPM. Add a test target.

**Decision: keep the single SPM executable target and the hand-rolled
`build.sh`. Do not generate an Xcode project. Add a test target — done, in this
change.**

### Why not Xcode

A multi-target Xcode project buys four things in principle. Here is what each
one is actually worth to Metron:

| Candidate reason | Verdict |
|---|---|
| A **WidgetKit extension** | The only genuine forcing function — and the README argues against it on the merits. A timeline reload is budgeted at roughly tens of refreshes a day; that is fine for a forecast and useless for a CPU meter or a limit that moves while you work. This was already tried on the abandoned `widgetkit-desktop-widgets` branch. Not a reason. |
| A **shared framework target** | Only needed if two targets must share code. There is one target. Not a reason. |
| A **test target** | **SPM does this natively.** Verified: `.testTarget(dependencies: ["Metron"])` with `@testable import Metron` links and runs against the `@main` executable target — 17 tests pass. Not a reason. |
| **Launch at login** (`SMAppService`) | Already working, in `Kit/LoginItem.swift`, using `SMAppService.mainApp` — the app registers *itself*. A separate `SMAppService.loginItem` helper target would only be needed for a background daemon that outlives the app, which Metron is not. Not a reason. |
| **Notarised release** | `codesign`, `xcrun notarytool` and `xcrun stapler` are command-line tools. They operate on the `.app` bundle and do not care whether Xcode produced it. Not a reason. |

That is the whole list, and none of it survives contact. The previous Xcode
multi-target attempt went badly and was abandoned; nothing has changed since to
make it worth a second attempt.

### The honest cost of staying

Three real things are given up, and all three are cheap to live with:

1. **No `xcodebuild archive` / Organizer flow.** Releases are assembled by
   `build.sh` and shipped by CI. This is fine — it is arguably clearer.
2. **No automatic universal binary.** Addressed: `METRON_UNIVERSAL=1 ./build.sh`
   now builds `--arch arm64 --arch x86_64` (13 seconds, measured). The old
   script produced an **arm64-thin** binary, so anything handed to an Intel Mac
   simply would not run.
3. **Debugging in Xcode is via the generated scheme**, not a checked-in project.
   `open Package.swift` works and is what the `.swiftpm` directory is already
   for.

### The migration cost of the alternative

For the record, if it were ever wanted: a multi-target Xcode project means a
checked-in `.xcodeproj` (or a `project.yml` plus XcodeGen as a build
dependency), splitting ~5,150 lines out of one executable target into a library
target with explicit access control on every shared symbol, a second signing
configuration, and a team ID baked into the project file — in a repo that is
about to be public. Days of work and a permanently noisier diff, to buy nothing
on the list above.

### What was actually added

- `Tests/MetronTests/` — 17 tests over the pure logic: limit-window naming and
  plan labels (`five_hour` → "Session", `default_claude_max_20x` → "Max 20x
  plan"), the severity ramp against the thresholds the README promises, widget
  geometry, `UsageSnapshot` Codable round-tripping, and ZFS size parsing.
- These need no live data, so they run in CI. `UsageCache.read()` is
  deliberately *not* among them: it reads a fixed path in the real home
  directory, and the check that the key still exists belongs in `verify.sh`
  where it can look at actual data.

---

## 2. `build.sh`: what it did, and where it was fragile

The original was 18 lines: `swift build -c release`, copy the binary and
`Info.plist` into a hand-assembled `dist/Metron.app`, ad-hoc sign, done.

Five fragilities, in the order they would bite:

1. **arm64-thin output.** Confirmed by `lipo`. Any Intel user gets a bundle that
   cannot launch, and nothing said so. → `METRON_UNIVERSAL=1`.
2. **Silently swallowed signing failures.** `codesign ... 2>/dev/null || true`
   discarded both the error and the exit status. An unsigned bundle does not
   fail at build time; it fails to launch days later with no explanation. →
   the `|| true` is gone, and the script prints the resulting signature.
3. **`--deep` is deprecated** by Apple and was never needed — the bundle has no
   nested code, just one executable. → removed.
4. **No version stamping.** `CFBundleShortVersionString` is hardcoded to `1.0`,
   so every build past, present and future claims to be 1.0 and no downloaded
   build can be told from a local one. → stamped from the git tag, *guarded* to
   a plain dotted number, because the existing tag is `v1.0-working` and
   `1.0-working` is not a legal `CFBundleShortVersionString` — Launch Services
   quietly rejects the whole bundle.
5. **No way to pass a real identity.** → `METRON_SIGN_ID="..."`, defaulting to
   `-` (ad-hoc).

One thing that *looks* like a bug and is not: `[ -f Resources/AppIcon.icns ] &&
cp ...` under `set -e`, with no such file present. Bash exempts non-final
operands of an `&&` list from `errexit`, so it does not abort. Verified by
running it. (It is now a plain `if` anyway, which does not require the reader to
know that.)

Also worth noting: **there is no `AppIcon.icns`.** Metron ships with the generic
application icon. Not a blocker, but the first thing a stranger will notice.

---

## 3. Signing and distribution

### What this machine actually has

```
$ security find-identity -v -p codesigning
  1) <hash> "Apple Development: <redacted> (<team id>)"
  2) <hash> "Apple Development: <redacted> (<team id>)"
     2 valid identities found

$ xcrun notarytool history
Error: Must provide credentials.
```

**There is no Developer ID Application certificate on this machine, and no
notarytool credentials.** The two identities present are *Apple Development*
certificates — those sign builds for your own devices during development. They
cannot sign software for distribution, and Apple will not notarise anything
signed with one.

Getting a Developer ID requires a paid Apple Developer Program membership
($99/year) and is done from the account holder's own login. **That is the
owner's to do, not something to automate.**

### Therefore: ship an ad-hoc-signed zip, and be straight about it

This is the path the CI workflow implements.

```bash
METRON_UNIVERSAL=1 ./build.sh
ditto -c -k --keepParent dist/Metron.app Metron.zip
shasum -a 256 Metron.zip > Metron.zip.sha256
```

Every release page carries the Gatekeeper instructions, because the alternative
is people meeting this as *"Metron is damaged and can't be opened"*, which is
macOS's spectacularly misleading way of saying "unsigned and quarantined":

```bash
unzip Metron.zip
xattr -dr com.apple.quarantine Metron.app
cp -R Metron.app /Applications/
open -a Metron
```

Use `ditto`, not `zip`. The `zip` command does not preserve the bundle's
symlinks and extended attributes, and the signature does not survive the round
trip.

Building from source (`./build.sh`) sidesteps quarantine entirely, since the
bundle was never downloaded. For a developer-facing menu bar app, that is a
perfectly respectable primary install path — and it is what the README already
documents.

### If and when a Developer ID exists

Nothing below has been run. These are the exact commands, for later.

```bash
# 1. Confirm the identity is present. Look for "Developer ID Application",
#    not "Apple Development".
security find-identity -v -p codesigning

# 2. Sign, with hardened runtime — notarisation requires it.
METRON_UNIVERSAL=1 \
METRON_SIGN_ID="Developer ID Application: <redacted> (TEAMID)" \
  ./build.sh

# 3. Verify the signature is accepted for distribution.
codesign --verify --deep --strict --verbose=2 dist/Metron.app
spctl -a -vvv -t exec dist/Metron.app

# 4. Store notarisation credentials once, in the keychain.
#    Use an app-specific password from appleid.apple.com — NOT the Apple ID
#    password. Better still, an App Store Connect API key (--key/--key-id/--issuer),
#    which is what CI would need.
xcrun notarytool store-credentials "metron-notary" \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"

# 5. Notarise the zip and wait for the verdict.
ditto -c -k --keepParent dist/Metron.app Metron.zip
xcrun notarytool submit Metron.zip --keychain-profile "metron-notary" --wait

# 6. Staple the ticket to the .app, then re-zip. A zip cannot be stapled;
#    the ticket goes on the bundle and the bundle is re-archived.
xcrun stapler staple dist/Metron.app
xcrun stapler validate dist/Metron.app
rm Metron.zip && ditto -c -k --keepParent dist/Metron.app Metron.zip
```

A DMG is not worth it here. It buys a drag-to-Applications background image and
costs an extra `create-dmg` dependency and a second thing to notarise. A zip of
a menu bar app is fine — and `/Applications` matters for this app (Launch at
login needs it), which is better said in words on the release page than implied
by a picture.

**To notarise from CI later**, four repository secrets would be needed:
`DEVELOPER_ID_P12` (base64), `P12_PASSWORD`, `NOTARY_KEY` / `NOTARY_KEY_ID` /
`NOTARY_ISSUER`. The current workflow deliberately requires **none** of them —
it uses only the automatically-issued `GITHUB_TOKEN` — so it will not fail on a
fresh clone or a fresh org.

---

## 4. CI

`.github/workflows/ci.yml`, on `macos-15`.

**build** (every push, PR, and tag): `swift build` → `swift test` →
`METRON_VERIFY_CI=1 ./verify.sh` → `METRON_UNIVERSAL=1 ./build.sh` → render a
glance from the assembled bundle to prove it launches → upload the zip.

**release** (tags matching `v*` only): rebuild with full history so the version
stamps, package, and `gh release create` with the Gatekeeper instructions in the
notes.

### Splitting `verify.sh`

`verify.sh` is mostly assertions about **live local data** — this machine's
`~/.claude.json`, an oMLX server on localhost, a NAS over ssh — and that is the
point of it. None of that exists on a runner. Rather than weaken it, it now
takes `METRON_VERIFY_CI=1`:

| Check | In CI | Why |
|---|---|---|
| Release build | **runs** | No data needed. |
| Popover geometry (`--measure`) | **runs**, non-fatal | Needs a window server, not data. If the runner has no usable one, it reports `skip` — a fact about the runner, not the code. |
| Per-glance headline assertions | **skipped** | usage/oMLX/KatechonOS have no source on a runner. |
| `~/.claude.json` has `utilization.limits` | **skipped** | CI has never run Claude Code. |

Skipped checks print `skip`, not `ok`. A check that quietly passes because its
subject is absent is worse than no check, and this file exists precisely because
its author already believes that.

---

## 5. What a stranger cloning this gets

The good news, established by reading `GlanceRegistry`: **the default is a
single glance, `usage`.** oMLX and KatechonOS are off unless deliberately turned
on. Metron already degrades gracefully. Every item below is a documentation or
polish issue, not a crash.

| Where | What is hardcoded | What a stranger experiences |
|---|---|---|
| `Glances/Katechon/KatechonModels.swift:124` | ssh host defaults to `katechon` | Glance is **off by default**. If enabled: "could not resolve host", after a bounded 12s timeout. Override: `defaults write com.watchman.metron katechon.host -string "…"` |
| `Glances/Katechon/KatechonModels.swift:169` | runs `katechon state` on the remote | If enabled against some other host: "`<host>` has no `katechon` on the path" — already a good message |
| `Glances/OMLX/OMLXModels.swift:105` | `http://127.0.0.1:8000` | Glance is **off by default**. If enabled: connection refused. Override: `omlx.baseURL` |
| `Glances/Usage/UsageCache.swift:18` | `~/.claude.json` | Empty until Claude Code has run once — and `UsageFetcher.swift:84` already says exactly that: *"No limits in ~/.claude.json yet — run Claude Code once."* |
| `Resources/Info.plist:7` | bundle id `com.watchman.metron` | Harmless, but it is the `defaults` domain, so **every command in the README and CONTRIBUTING must keep using it verbatim.** Renaming it would strand existing installs' settings. Leave it. |
| `verify.sh` | asserts on all four glances | Reports `FAIL` for sources a stranger doesn't have. CONTRIBUTING now says this is expected. |
| **No `/Users/watchman` path anywhere** | — | Checked. Clean. |

So a stranger who clones, builds and runs gets **Claude usage** (populated if
they use Claude Code, with a clear message if not) and can turn on **System**,
which reads the kernel directly and always works. That is a genuinely useful app
on its own. Nothing hangs and nothing crashes.

**One real leak, now fixed:** `.swiftpm/xcode/**/xcuserdata/` was tracked — two
files with `watchman.xcuserdatad` in their paths, carrying the owner's username
and local Xcode UI state. Removed from the index and added to `.gitignore`.
(They remain in the eight commits of history. Not worth rewriting history over —
the username is already the GitHub account name — but worth knowing.)

---

## 6. Going public: the checklist

Ordered. Everything unchecked is the owner's to do.

- [x] `LICENSE` — MIT, "Copyright (c) 2026 Watchman Reeves". Valid and complete.
- [x] `.gitignore` — reviewed; `xcuserdata`, `.DS_Store` added
- [x] Personal Xcode state untracked
- [x] `CONTRIBUTING.md`
- [x] `CHANGELOG.md`, seeded from the eight commits
- [x] `.github/ISSUE_TEMPLATE/` — bug report, feature request, config
- [x] `.github/workflows/ci.yml`, requiring no secrets
- [x] Test target
- [x] No `/Users/watchman` paths in tracked source
- [ ] **Decide the abandoned branch.** `widgetkit-desktop-widgets` exists on
      `origin` and is a dead end the README argues against. Either delete it, or
      keep it deliberately — it is genuinely useful evidence for *why* Metron
      doesn't use WidgetKit, and CONTRIBUTING now points at it as such. Keeping
      it is the recommendation; if so, say so in its final commit or leave it be.
- [ ] **Retag.** The only tag is `v1.0-working`, which is not a version and will
      not stamp a bundle. `git tag v1.0 c492c0e && git push origin v1.0`, and
      delete `v1.0-working` if it has no sentimental value.
- [ ] **An app icon.** There is no `AppIcon.icns`; the app shows the generic
      icon in `/Applications` and in Login Items.
- [ ] **Update README URLs** from `WatchmanReeves/Metron` to
      `Band-of-Reeves/Metron` after the transfer (see below).
- [ ] Enable Discussions, if the issue-template `config.yml` link is to work.

### Description and topics

> **Description:** A macOS menu bar app for the numbers you'd otherwise go and
> look up — Claude usage limits, this machine, a local model server, the NAS.
> Each one is its own menu bar item and its own desktop widget.

> **Topics:** `macos`, `menubar`, `swift`, `swiftui`, `appkit`, `widgets`,
> `claude`, `claude-code`, `system-monitor`, `spm`, `menubar-app`, `dashboard`

---

## 7. Moving the repo to the organisation

`gh auth status` shows the account `WatchmanReeves` with scopes including
`repo`, `read:org`, `delete_repo` and `workflow`. `gh api user/orgs` returns
exactly one organisation: **`Band-of-Reeves`** (id 323190521).

**None of the following has been run.** Transferring a repo is the owner's
call, and the redirect is not something to trigger by accident.

```bash
# 0. Land this branch first — transferring mid-flight only adds confusion.
git checkout main
git merge claude/metron-repo-setup-7c15b6
git push origin main
```

The `repo` scope alone is not enough to transfer into an organisation. Check,
and top up if needed — this opens a browser and is the one step that needs the
owner present:

```bash
gh auth status                          # look for admin:org in the scope list
gh auth refresh -h github.com -s admin:org
```

Transfer. GitHub moves the issues, stars, watchers, wiki and — importantly —
leaves an HTTP redirect from the old URL, so existing clones keep working:

```bash
gh api -X POST repos/WatchmanReeves/Metron/transfer \
  -f new_owner='Band-of-Reeves'
```

Re-point this checkout. The redirect means the old remote would still work,
but leaving it pointing at a redirect is how a repo ends up half-moved:

```bash
git remote set-url origin https://github.com/Band-of-Reeves/Metron.git
git remote -v
git fetch origin && git status
```

Also update the worktrees, which have their own idea of the remote:

```bash
git worktree list
```

Set the description and topics, and make it public. **`--visibility public` is
the irreversible-feeling step; do it last, once the checklist above is clean:**

```bash
gh repo edit Band-of-Reeves/Metron \
  --description "A macOS menu bar app for the numbers you'd otherwise go and look up — Claude usage limits, this machine, a local model server, the NAS." \
  --add-topic macos,menubar,swift,swiftui,appkit,widgets,claude,claude-code,system-monitor,spm \
  --enable-issues --enable-discussions

gh repo edit Band-of-Reeves/Metron --visibility public --accept-visibility-change-consequences
```

Then tag, which is what actually fires the release job:

```bash
git tag -a v1.0 -m "Metron 1.0" && git push origin v1.0
gh run watch
gh release view v1.0
```

### Two things to check after the transfer

1. **Actions may be disabled on transfer.** GitHub sometimes disables workflows
   on a repo that changes owner. `gh workflow list` — if `ci.yml` is missing or
   disabled, `gh workflow enable ci.yml`.
2. **The org needs Actions permitted for macOS runners.** A brand-new free org
   gets the standard runner minutes allowance, and macOS runners bill at 10× the
   Linux rate against it. This workflow is short (a build plus 17 fast tests),
   but it is the one line item worth watching on a first org.
