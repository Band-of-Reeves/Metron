#!/usr/bin/env python3
"""Reference implementation for the Metron Ledger glance.

Turns Claude Code token counts into "what this would have cost on the
Anthropic API", and compares that to a flat subscription price.

Two sources, deliberately kept side by side so the accuracy gap is visible:

  stats-cache  ~/.claude/stats-cache.json
               Cheap (12 KB, one read). Gives an EXACT all-time four-way
               token split per model (`modelUsage`), but per-day it only
               gives a SINGLE fused number per model — input + output +
               cache-read + cache-write summed together. Daily costs from
               this source are therefore ESTIMATES: we apply each model's
               all-time blended $/token to its daily fused total.

  transcripts  ~/.claude/projects/**/*.jsonl
               Expensive (thousands of files). Gives a TRUE per-day,
               per-model four-way split, and additionally splits cache
               writes into 5-minute and 1-hour TTLs, which are priced
               differently (1.25x vs 2x base input). This is strictly
               more accurate and is what the shipped glance should use.

Run:
    python3 cost_model.py                 # stats-cache only (fast)
    python3 cost_model.py --transcripts   # add the exact scan + delta
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
STATS_CACHE = HOME / ".claude" / "stats-cache.json"
PROJECTS = HOME / ".claude" / "projects"

SUBSCRIPTION_USD_PER_MONTH = 200.0  # Claude Max 20x

# ---------------------------------------------------------------------------
# Pricing
# ---------------------------------------------------------------------------
# USD per million tokens. Source: https://platform.claude.com/docs/en/about-claude/pricing
# Fetched 2026-08-31. Columns are the doc's own columns:
#   Base Input | 5m Cache Writes | 1h Cache Writes | Cache Hits & Refreshes | Output
# Cache multipliers are 1.25x (5m write), 2x (1h write), 0.1x (read) of base input.

PRICES = {
    #                    input   w5m     w1h     read    output
    "claude-fable-5":  (10.00, 12.50, 20.00, 1.00, 50.00),
    "claude-opus-5":   (5.00,  6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-8": (5.00,  6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-7": (5.00,  6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-6": (5.00,  6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-5": (5.00,  6.25, 10.00, 0.50, 25.00),
    "claude-sonnet-5": (2.00,  2.50,  4.00, 0.20, 10.00),
    "claude-sonnet-4-6": (3.00, 3.75, 6.00, 0.30, 15.00),
    "claude-haiku-4-5": (1.00, 1.25,  2.00, 0.10,  5.00),
}

FREE = (0.0, 0.0, 0.0, 0.0, 0.0)


def normalize(model: str) -> str:
    """Map a transcript/stats model id onto a pricing-table key.

    Claude Code writes both bare ids (`claude-opus-5`) and dated snapshots
    (`claude-haiku-4-5-20251001`). Strip a trailing 8-digit date.
    """
    parts = model.rsplit("-", 1)
    if len(parts) == 2 and len(parts[1]) == 8 and parts[1].isdigit():
        return parts[0]
    return model


def is_local(model: str) -> bool:
    """Non-Anthropic models routed through Claude Code (oMLX etc.) cost $0."""
    return not normalize(model).startswith("claude-")


def rates(model: str):
    key = normalize(model)
    if is_local(model):
        return FREE
    return PRICES.get(key)


def cost_exact(model: str, inp: int, out: int, read: int, w5m: int, w1h: int) -> float:
    r = rates(model)
    if r is None:
        return float("nan")
    pi, p5, p1, pr, po = r
    return (inp * pi + out * po + read * pr + w5m * p5 + w1h * p1) / 1_000_000.0


def money(x: float) -> str:
    if x != x:  # NaN
        return "     n/a"
    return f"${x:,.2f}"


# ---------------------------------------------------------------------------
# stats-cache source
# ---------------------------------------------------------------------------

def load_stats_cache(path: Path = STATS_CACHE) -> dict:
    with path.open() as fh:
        return json.load(fh)


def alltime_from_cache(cache: dict):
    """Exact per-model all-time cost from `modelUsage`.

    `modelUsage` does NOT split cache writes by TTL, so we must pick one.
    We assume the 5-minute write price (1.25x), the cheaper and far more
    common of the two — this UNDERSTATES cost wherever 1h caching was used.
    The transcript path measures the real split.
    """
    rows = []
    for model, u in cache["modelUsage"].items():
        inp = u["inputTokens"]
        out = u["outputTokens"]
        read = u["cacheReadInputTokens"]
        write = u["cacheCreationInputTokens"]
        total = inp + out + read + write
        c = cost_exact(model, inp, out, read, write, 0)
        rows.append({
            "model": model,
            "input": inp, "output": out, "read": read, "write": write,
            "tokens": total, "cost": c,
            "usd_per_token": (c / total) if total else 0.0,
            "local": is_local(model),
            "priced": rates(model) is not None,
        })
    rows.sort(key=lambda r: -r["cost"])
    return rows


def blended_ratios(rows) -> dict:
    """model -> USD per fused token, from the all-time four-way split."""
    return {r["model"]: r["usd_per_token"] for r in rows}


def daily_costs_estimated(cache: dict, ratio: dict):
    """date -> (cost, {model: cost}), estimated via the blended ratio.

    ACCURACY CAVEAT: this assumes every day had the same input/output/
    cache mix as the model's all-time average. A day that was unusually
    output-heavy is UNDERSTATED; a day that was almost entirely cache
    reads is OVERSTATED. Typical error is a few percent on busy days and
    can be large on a low-volume day. See --transcripts for the truth.
    """
    out = {}
    for entry in cache["dailyModelTokens"]:
        per_model = {}
        for model, tok in entry["tokensByModel"].items():
            per_model[model] = tok * ratio.get(model, 0.0)
        out[entry["date"]] = (sum(per_model.values()), per_model)
    return out


# ---------------------------------------------------------------------------
# transcript source (exact per-day four-way + TTL split)
# ---------------------------------------------------------------------------

def scan_transcripts(root: Path = PROJECTS):
    """date -> model -> [input, output, read, write5m, write1h].

    Mirrors the CLI's own accounting so the two are comparable:
      * only `type == "assistant"` lines with a `message.usage` object
      * main transcripts drop `isSidechain` entries
      * `subagents/agent-*.jsonl` files are counted in full
      * the day bucket is the UTC date of `timestamp` (the CLI uses
        `toISOString().split("T")[0]`, which is UTC, NOT local time)
      * `<synthetic>` model ids are skipped
    """
    days = defaultdict(lambda: defaultdict(lambda: [0, 0, 0, 0, 0]))
    files = 0
    for path in root.rglob("*.jsonl"):
        is_subagent = f"{os.sep}subagents{os.sep}" in str(path)
        if is_subagent and not path.name.startswith("agent-"):
            continue
        files += 1
        try:
            raw = path.read_bytes()
        except OSError:
            continue
        for line in raw.split(b"\n"):
            if b'"usage"' not in line or b'"assistant"' not in line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get("type") != "assistant":
                continue
            if not is_subagent and obj.get("isSidechain"):
                continue
            msg = obj.get("message") or {}
            usage = msg.get("usage")
            if not isinstance(usage, dict):
                continue
            model = msg.get("model") or "unknown"
            if model == "<synthetic>":
                continue
            ts = obj.get("timestamp") or ""
            day = ts[:10]
            if len(day) != 10:
                continue
            cc = usage.get("cache_creation") or {}
            w5 = int(cc.get("ephemeral_5m_input_tokens") or 0)
            w1 = int(cc.get("ephemeral_1h_input_tokens") or 0)
            write = int(usage.get("cache_creation_input_tokens") or 0)
            if w5 + w1 == 0:
                # No TTL breakdown on this record; assume 5m (the default).
                w5 = write
            slot = days[day][model]
            slot[0] += int(usage.get("input_tokens") or 0)
            slot[1] += int(usage.get("output_tokens") or 0)
            slot[2] += int(usage.get("cache_read_input_tokens") or 0)
            slot[3] += w5
            slot[4] += w1
    return days, files


def daily_costs_exact(days):
    out = {}
    for day, models in days.items():
        per_model = {}
        for model, (i, o, r, w5, w1) in models.items():
            per_model[model] = cost_exact(model, i, o, r, w5, w1)
        out[day] = (sum(v for v in per_model.values() if v == v), per_model)
    return out


# ---------------------------------------------------------------------------
# windows
# ---------------------------------------------------------------------------

def window(daily, days_back: int, anchor: str):
    end = dt.date.fromisoformat(anchor)
    start = end - dt.timedelta(days=days_back - 1)
    keep = {d: v for d, v in daily.items()
            if start <= dt.date.fromisoformat(d) <= end}
    return keep, start, end


def report(title, daily):
    total = sum(c for c, _ in daily.values())
    per_model = defaultdict(float)
    for _, pm in daily.values():
        for m, c in pm.items():
            per_model[m] += c
    return total, per_model


# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts", action="store_true",
                    help="also do the exact per-day scan of ~/.claude/projects")
    args = ap.parse_args()

    cache = load_stats_cache()
    W = 78
    print("=" * W)
    print("METRON LEDGER — reference cost model")
    print("=" * W)
    # Print home-relative: this output is committed, and an absolute
    # /Users/<name> path is a leak the repo's own scan rejects.
    print(f"source        ~/{STATS_CACHE.relative_to(Path.home())}")
    print(f"schema        version={cache['version']} "
          f"dailyModelTokensVersion={cache['dailyModelTokensVersion']}")
    print(f"lastComputed  {cache['lastComputedDate']}  "
          f"(the cache is written through YESTERDAY; today is scanned live)")
    print(f"firstSession  {cache['firstSessionDate']}")
    print(f"sessions      {cache['totalSessions']:,}   "
          f"messages {cache['totalMessages']:,}")
    ls = cache["longestSession"]
    print(f"longest       {ls['duration'] / 3_600_000:.1f} h "
          f"({ls['messageCount']:,} messages, {ls['timestamp'][:10]})  "
          f"— duration is MILLISECONDS")
    print()

    # ---- all-time, exact four-way ----------------------------------------
    rows = alltime_from_cache(cache)
    alltime = sum(r["cost"] for r in rows if r["cost"] == r["cost"])
    tokens_all = sum(r["tokens"] for r in rows)

    print("-" * W)
    print("ALL-TIME, per model  (exact four-way split from modelUsage)")
    print("-" * W)
    hdr = (f"{'model':34}{'tokens':>16}{'cost':>13}  {'$/Mtok':>8}")
    print(hdr)
    for r in rows:
        tag = "  local" if r["local"] else ""
        print(f"{r['model'][:33]:34}{r['tokens']:>16,}{money(r['cost']):>13}"
              f"  {r['usd_per_token'] * 1e6:>8.3f}{tag}")
    print(f"{'TOTAL':34}{tokens_all:>16,}{money(alltime):>13}")
    print()
    print("  breakdown of the total:")
    for r in rows[:4]:
        print(f"    {r['model'][:30]:32} in {r['input']:>12,}  out {r['output']:>12,}"
              f"  read {r['read']:>14,}  write {r['write']:>12,}")
    print()

    # ---- daily windows, estimated ----------------------------------------
    ratio = blended_ratios(rows)
    daily_est = daily_costs_estimated(cache, ratio)
    anchor = max(daily_est)

    d30, s30, e30 = window(daily_est, 30, anchor)
    d7, s7, e7 = window(daily_est, 7, anchor)
    t30, m30 = report("30d", d30)
    t7, m7 = report("7d", d7)

    peak_day, (peak_cost, _) = max(daily_est.items(), key=lambda kv: kv[1][0])
    active_days = len(daily_est)
    span = (dt.date.fromisoformat(anchor)
            - dt.date.fromisoformat(min(daily_est))).days + 1

    print("-" * W)
    print("WINDOWS  (daily figures ESTIMATED — see caveat below)")
    print("-" * W)
    print(f"  all-time ({span} d span, {active_days} active)   {money(alltime):>14}")
    print(f"  last 30 days  {s30} .. {e30}      {money(t30):>14}")
    print(f"  last 7 days   {s7} .. {e7}      {money(t7):>14}")
    print(f"  peak day      {peak_day}                     {money(peak_cost):>14}")
    print()
    print(f"  cost / calendar day (all-time)         {money(alltime / span):>14}")
    print(f"  cost / active day  (all-time)          {money(alltime / active_days):>14}")
    print(f"  cost / day (last 30)                   {money(t30 / 30):>14}")
    print(f"  cost / day (last 7)                    {money(t7 / 7):>14}")
    print()

    print("-" * W)
    print(f"VERSUS A ${SUBSCRIPTION_USD_PER_MONTH:.0f}/MONTH SUBSCRIPTION")
    print("-" * W)
    months = span / 30.4375
    paid = SUBSCRIPTION_USD_PER_MONTH * months
    print(f"  subscription paid over {span} days     {money(paid):>14}")
    print(f"  equivalent API cost                    {money(alltime):>14}")
    print(f"  MULTIPLE                               {alltime / paid:>13.1f}x")
    print()
    print(f"  last 30 days vs one month              "
          f"{t30 / SUBSCRIPTION_USD_PER_MONTH:>13.1f}x")
    print(f"  peak day alone vs one month            "
          f"{peak_cost / SUBSCRIPTION_USD_PER_MONTH:>13.1f}x")
    print(f"  break-even: the subscription pays for itself after "
          f"{SUBSCRIPTION_USD_PER_MONTH / (t30 / 30):.2f} days of")
    print(f"  usage at the last-30-day rate.")
    print()

    print("-" * W)
    print("30-DAY, per model (estimated)")
    print("-" * W)
    for m, c in sorted(m30.items(), key=lambda kv: -kv[1]):
        share = 100 * c / t30 if t30 else 0
        print(f"  {m[:38]:40}{money(c):>13}   {share:5.1f}%")
    print()

    print("-" * W)
    print("PER-DAY (estimated), most recent 14 active days")
    print("-" * W)
    for day in sorted(daily_est)[-14:]:
        c, _ = daily_est[day]
        bar = "#" * min(46, int(c / max(1.0, peak_cost) * 46))
        print(f"  {day}  {money(c):>11}  {bar}")
    print()

    print("!" * W)
    print("ACCURACY CAVEAT")
    print("!" * W)
    print("  All-time per-model figures above are EXACT: modelUsage carries a real")
    print("  four-way split (input / output / cache-read / cache-write).")
    print()
    print("  Every DAILY figure — the 30d and 7d windows, cost-per-day, and the peak")
    print("  day — is an ESTIMATE. dailyModelTokens.tokensByModel is a single fused")
    print("  number per model per day: input + output + cacheRead + cacheCreation")
    print("  summed together (verified against modelUsage: ratio 1.0000 for every")
    print("  model). Recovering a cost from it requires assuming the day had the")
    print("  model's all-time average mix. Output tokens cost 50x a cache read, so")
    print("  an unusually output-heavy day is understated and a cache-read-heavy")
    print("  day is overstated.")
    print()
    print("  Cache writes are priced at the 5-minute rate (1.25x input) because")
    print("  modelUsage does not record the TTL. Claude Code uses 1-hour caching")
    print("  (2x input) in places, so this UNDERSTATES the true figure.")
    print()
    print("  Both approximations disappear if you read ~/.claude/projects/**/*.jsonl")
    print("  instead: those records carry a true per-message four-way split AND the")
    print("  usage.cache_creation TTL breakdown. Run with --transcripts.")
    print()

    if args.transcripts:
        print("=" * W)
        print("EXACT SCAN of ~/.claude/projects/**/*.jsonl")
        print("=" * W)
        days, nfiles = scan_transcripts()
        print(f"  scanned {nfiles:,} transcript files, {len(days)} distinct UTC days")
        # Compare like with like: the cache stops at `lastComputedDate`, so
        # clip the transcript scan to the same last day.
        days = {d: m for d, m in days.items() if d <= anchor}
        daily_ex = daily_costs_exact(days)
        anchor_x = max(daily_ex)
        dx30, sx, ex = window(daily_ex, 30, anchor_x)
        dx7, s7x, e7x = window(daily_ex, 7, anchor_x)
        tx30, _ = report("30", dx30)
        tx7, _ = report("7", dx7)
        pk_day, (pk_cost, _) = max(daily_ex.items(), key=lambda kv: kv[1][0])
        tx_all = sum(c for c, _ in daily_ex.values())
        print(f"  clipped to <= {anchor} to match the cache watermark: "
              f"{len(daily_ex)} days")

        # 5m vs 1h cache write mix, which stats-cache cannot see at all.
        w5 = w1 = 0
        tok = defaultdict(lambda: [0, 0, 0, 0])
        for models in days.values():
            for m, (i, o, r, a, b) in models.items():
                w5 += a
                w1 += b
                t = tok[normalize(m)]
                t[0] += i; t[1] += o; t[2] += r; t[3] += a + b
        print(f"  cache writes: {w5:,} at 5m, {w1:,} at 1h "
              f"({100 * w1 / max(1, w5 + w1):.1f}% at the 2x rate) "
              f"— invisible to stats-cache")
        print()
        print("  token reconciliation, transcripts vs modelUsage (all-time):")
        print(f"    {'model':30}{'transcripts':>16}{'modelUsage':>16}{'ratio':>8}")
        for r in rows:
            mu = r["tokens"]
            ts = sum(tok.get(normalize(r["model"]), [0, 0, 0, 0]))
            print(f"    {normalize(r['model'])[:29]:30}{ts:>16,}{mu:>16,}"
                  f"{(ts / mu if mu else 0):>8.3f}")
        print()
        print(f"{'window':22}{'estimated':>15}{'exact':>15}{'delta':>12}")
        for label, est, exact in (
            ("all-time", alltime, tx_all),
            ("last 30 days", t30, tx30),
            ("last 7 days", t7, tx7),
            (f"peak day", peak_cost, pk_cost),
        ):
            d = (exact - est) / exact * 100 if exact else 0
            print(f"{label:22}{money(est):>15}{money(exact):>15}{d:>11.1f}%")
        print()
        print(f"  exact peak day: {pk_day}  {money(pk_cost)}")
        print(f"  exact multiple vs ${SUBSCRIPTION_USD_PER_MONTH:.0f}/mo over "
              f"{span} days: {tx_all / paid:.1f}x")
        print()
        print("  Note: the transcript scan can exceed the stats-cache figure because")
        print("  transcripts on disk may predate or outlive what the cache covers,")
        print("  and it can fall short because Claude Code prunes old transcripts")
        print("  while the cache keeps the aggregate forever.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
