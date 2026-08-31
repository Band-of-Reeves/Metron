#!/usr/bin/env python3
"""Reconcile the two local records of Claude Code token usage, day by day.

There are two, and Metron has to say which one it quotes:

  ~/.claude/stats-cache.json      the CLI's own roll-up. One fused number per
                                  model per day, written only when a human
                                  opens the stats screen, through *yesterday*.
  ~/.claude/projects/**/*.jsonl   the session transcripts. One record per
                                  assistant message, carrying the real
                                  four-way token split and the cache TTL.

The roll-up is *derived from* the transcripts, so it cannot hold anything they
do not. What it can do is lag: it merges additively and never revisits a day it
has already computed. A session that starts on Monday and is still being
appended to on Friday is counted as far as it had got when the roll-up ran, and
that day is then frozen short forever.

So this script asserts the thing that must be true if that story is right:

  every SETTLED day agrees to the token.

A day is settled when no transcript that contributes to it was written after
the day ended. Days that are not settled are reported, with the lag that
explains them, and are not counted as failures. Any other disagreement is.

Exit 0 if every settled day agrees, 1 otherwise.
"""
import collections
import datetime as dt
import glob
import json
import os
import sys
from pathlib import Path

CACHE = Path.home() / ".claude" / "stats-cache.json"
PROJECTS = Path.home() / ".claude" / "projects"

# A transcript flushed a little after local midnight is still that day's work,
# not a late rewrite. An hour is generous and keeps the check from crying wolf.
GRACE = dt.timedelta(hours=1)


def transcripts():
    """Per-day totals, and the latest mtime of any file feeding each day."""
    day_tokens = collections.defaultdict(collections.Counter)
    day_mtime = {}
    files = glob.glob(str(PROJECTS / "**" / "*.jsonl"), recursive=True)
    for fp in files:
        try:
            lines = open(fp, errors="replace").read().splitlines()
        except OSError:
            continue
        mtime = dt.datetime.fromtimestamp(os.path.getmtime(fp))
        for line in lines:
            if '"usage"' not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") != "assistant":
                continue
            msg = rec.get("message") or {}
            usage = msg.get("usage") or {}
            if not usage:
                continue
            day = (rec.get("timestamp") or "")[:10]
            if not day:
                continue
            day_tokens[day][msg.get("model", "?")] += sum(
                usage.get(k, 0)
                for k in ("input_tokens", "output_tokens",
                          "cache_read_input_tokens", "cache_creation_input_tokens")
            )
            if mtime > day_mtime.get(day, dt.datetime.min):
                day_mtime[day] = mtime
    return day_tokens, day_mtime, len(files)


def main():
    if not CACHE.exists():
        print(f"  no {CACHE.name} — open the CLI's stats screen once", file=sys.stderr)
        return 1

    cache = json.loads(CACHE.read_text())
    rollup = {r["date"]: r["tokensByModel"] for r in cache["dailyModelTokens"]}
    watermark = cache["lastComputedDate"]
    day_tokens, day_mtime, n_files = transcripts()

    print(f"reconciling {n_files:,} transcripts against {CACHE.name}")
    print(f"  roll-up computed through {watermark}\n")

    agreed = late = 0
    failures = []
    for day in sorted(set(rollup) | set(day_tokens)):
        if day > watermark:
            continue  # the roll-up has not reached this day yet; not a mismatch
        mine = sum(day_tokens[day].values())
        theirs = sum(rollup.get(day, {}).values())
        if mine == theirs:
            agreed += 1
            continue
        end_of_day = dt.datetime.fromisoformat(day) + dt.timedelta(days=1) + GRACE
        written = day_mtime.get(day, dt.datetime.min)
        if written > end_of_day:
            late += 1
            lag = (written - end_of_day).days
            print(f"  late-written  {day}  roll-up short by {mine - theirs:>15,} "
                  f"— still being appended {lag}d later")
        else:
            failures.append((day, mine, theirs))

    print()
    for day, mine, theirs in failures:
        print(f"  MISMATCH      {day}  transcripts {mine:,}  roll-up {theirs:,} "
              f"  delta {mine - theirs:+,}")

    total = agreed + late + len(failures)
    print(f"  {agreed}/{total} settled days agree to the token, "
          f"{late} late-written, {len(failures)} unexplained")
    if failures:
        print("\n  A settled day that disagrees means the story in this file's "
              "docstring is wrong.\n  Do not quote either number until it is "
              "explained.")
        return 1
    print("\n  The transcripts are the primary record; the roll-up is a "
          "derived summary\n  that can lag but never exceed it. Metron quotes "
          "the transcripts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
