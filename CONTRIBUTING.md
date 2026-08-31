# Contributing to Metron

Thanks for looking. Metron is a small, opinionated menu bar app, and the bar for
a change is mostly "does it make a glance tell you something truer, faster?"

## Getting it running

```bash
git clone https://github.com/Band-of-Reeves/Metron.git
cd Metron
./build.sh
cp -R dist/Metron.app /Applications/
open -a Metron
```

You need macOS 14 or later and a Swift 6 toolchain (Xcode 16 or newer). There
are no dependencies to fetch — the package has none.

`/Applications` matters: **Launch at login** uses `SMAppService`, and macOS
refuses to register a bundle Launch Services can't resolve.

## What you'll see on a fresh clone

Only the **Claude usage** glance is on by default, and that is deliberate — the
other three describe hardware that probably isn't yours:

| Glance | What it needs | Without it |
|---|---|---|
| Claude usage | Claude Code installed and run at least once | Says so, and stays empty |
| System | Nothing — reads the kernel directly | Always works |
| oMLX | An [oMLX](https://omlx.app) server on `127.0.0.1:8000` | Reports unreachable |
| KatechonOS | ssh access to a host running `katechon` | Reports unreachable |

Turn glances on and off from the ••• menu under **Glances**. oMLX and
KatechonOS point somewhere else via user defaults:

```bash
defaults write com.watchman.metron omlx.baseURL   -string "http://127.0.0.1:8000"
defaults write com.watchman.metron katechon.host  -string "your-nas.local"
```

An unreachable source is a supported state, not a bug — it should say what went
wrong on the widget face. If one ever blanks a panel or hangs the app instead,
that *is* a bug and we'd like to hear about it.

## Before you open a pull request

```bash
swift test    # pure logic; runs anywhere
./verify.sh   # the real check; needs your live data
```

`verify.sh` builds, checks every popover against its panel, renders every glance
and **asserts on the headline rather than on the render succeeding**, and
confirms the limit cache still has the key the rings read. A glance that renders
but has nothing to show is the failure that looks like success; that is the one
it exists to catch.

It will report `FAIL` for glances whose sources you don't have. That is expected
on someone else's machine — read the failures that relate to your change. CI
runs `METRON_VERIFY_CI=1 ./verify.sh`, which skips the live-data checks
honestly instead of pretending they passed.

## Adding a glance

Subclass `GlanceStore`, override `load()`, `headline` and `content(_:)`, and add
it to the list in `GlanceRegistry`. The menu bar slot, refresh timer, desk
window and its four sizes, the settings menu and the `--render` path all come
with it.

The layering is worth keeping: `Kit/` holds nothing domain-specific, and the
glances under `Glances/` hold nothing shared. If you find yourself wanting to
reach from one glance into another, that's a sign the thing belongs in `Kit/`.

Design the small, medium and large sizes as real layouts rather than a scaled
full panel — they mirror the proportions macOS gives its own desktop widgets, so
a glance laid out for `.medium` should look at home next to Weather.

```bash
# Look at what you built without wrestling a borderless window into a screenshot.
Metron --render out.png --glance system --size large
Metron --render out.png --glance usage  --size full --window
```

## Things that are settled

Please don't open a PR for these without discussing it first:

- **These are not WidgetKit widgets, on purpose.** A WidgetKit timeline reload is
  budgeted by the system at roughly tens of refreshes a day. That is fine for a
  forecast and useless for a CPU meter. Metron's widgets are ordinary windows so
  they update on the cadence you choose. There is an abandoned
  `widgetkit-desktop-widgets` branch if you want to see how that went.
- **No glance holds a credential.** oMLX doesn't ask for one on localhost;
  KatechonOS uses the ssh key you already have. Metron deliberately never reads
  oMLX's `/admin/api/stats`, which returns the server's API key in cleartext. A
  widget has no business holding one.
- **The heatmap and model split are a local view** and deliberately do not match
  the limit rings. They can't see claude.ai or your other machines, and they
  count output tokens rather than the server's cost weighting.

## Style

Match what's there. In particular: comments explain *why*, especially where the
obvious approach was tried and didn't work — most of the comments in this
codebase are load-bearing history, not description. Commit messages are a
sentence saying what changed and why, in the imperative or the plain past.

## Reporting a bug

Use the issue templates. For anything visual, `Metron --render` gives a clean
screenshot. Include your macOS version and whether you're on Apple silicon or
Intel.
