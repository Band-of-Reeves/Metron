# Metron

A macOS menu bar readout for your Claude usage limits — so you never have to
open Settings → Usage and hit refresh again.

![panel](docs/panel.png)

## What it shows

- **Limit rings** — every window the server reports (5-hour session, weekly
  all-models, weekly per-model such as Fable), each with a live countdown to
  its reset. The ring turns amber past 70% and red past 90%.
- **Menu bar glyph** — a filled ring plus the percentage of whichever window is
  closest to its ceiling, so a glance at the menu bar is usually enough.
- **Activity heatmap** — a GitHub-style contribution grid of the last 18 weeks,
  built from your local Claude Code transcripts.
- **Model split** — which models did this week's work, by output tokens.
- **Drivers** — the same "what's contributing to your limits" attribution the
  `/usage` dialog shows: behaviours, top skills, subagents and MCP servers.

## Where the numbers come from

Two independent sources:

| Panel section | Source | Covers |
|---|---|---|
| Limit rings, Drivers | `claude -p "/usage"` | Your account — all devices and claude.ai |
| Heatmap, Model split | `~/.claude/projects/**/*.jsonl` | Claude Code on **this machine** only |

`/usage` is a local slash command. It makes no model call, costs nothing, and
just reads the same claude.ai limits endpoint the desktop Usage pane uses —
which is also why Metron needs no API key or token of its own. It shells out to
your existing `claude` CLI and inherits its authentication.

The heatmap and model split are a *local* view. They deliberately do not match
the limit rings: they can't see claude.ai chats or your other machines, and they
count output tokens rather than the server's cost weighting. Treat them as a
picture of your own working rhythm, not as an audit of the limit.

## Install

```bash
./build.sh
cp -R dist/Metron.app /Applications/
open -a Metron
```

Then, from the ••• menu in the panel, turn on **Launch at login**.
(Launch at login only works from `/Applications`.)

## The desktop window

The ••• menu can detach the panel into a borderless window that lives on the
desktop — drag it anywhere, and it remembers where you put it. **Desktop window
sits** chooses whether it floats above your other windows or tucks behind them
like wallpaper furniture. If the display it was parked on goes away, it snaps
back onto an attached screen rather than stranding itself offscreen.

## Settings

All in the ••• menu: refresh interval (30s / 1m / 5m / 15m), whether to show the
percentage next to the menu bar ring, the desktop window, and launch at login.

## Development

```bash
swift build -c release
```

`Metron --render out.png` renders the panel to an image with live data — useful
for design review, since a menu bar popover is awkward to screenshot. Add
`--window` to render through real AppKit (needed for controls `ImageRenderer`
can't draw), `--light` for the light appearance, `--floating` for the detached
window's chrome.

## Notes

- The heatmap only goes back as far as your transcripts do; it fills in as you
  work.
- Transcript scanning caches per file by size and mtime, so refreshes after the
  first are cheap. A cold scan of ~470 files / 340 MB takes well under a second.
