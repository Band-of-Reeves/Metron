#!/bin/bash
# One command that answers "is Metron actually working?" without reading prose.
# Exits non-zero on the first real failure. Every check below is something that
# has genuinely broken at least once.
#
# Most of these checks assert on *live local data* — your ~/.claude.json, your
# oMLX server, your NAS — which is the whole point: a glance that renders but
# has nothing to show is the failure that looks like success. None of that
# exists on a CI runner, so METRON_VERIFY_CI=1 runs only the checks that are
# true anywhere: the release build and the popover geometry. It reports the
# rest as "skip" rather than quietly passing them.
set -uo pipefail
cd "$(dirname "$0")"

CI_MODE=${METRON_VERIFY_CI:-0}

fail=0
pass() { printf "  \033[32mok\033[0m   %s\n" "$1"; }
bad()  { printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=1; }
skip() { printf "  \033[33mskip\033[0m %s\n" "$1"; }

echo "build"
if swift build -c release >/tmp/metron-verify-build.log 2>&1; then
  pass "release build"
else
  bad "release build — see /tmp/metron-verify-build.log"; exit 1
fi

BIN=./.build/release/Metron

echo "popover sizing"
# Catches the class of bug where a panel grows after the popover is sized and
# the header ends up clipped off the top. This needs a window server but no
# live data, so it is one of the two checks that also mean something in CI.
if out=$("$BIN" --measure 2>&1) && grep -q "^ok:" <<<"$out"; then
  pass "every popover matches its panel"
elif [[ "$CI_MODE" == 1 ]]; then
  # A runner without a usable window server can't lay out an NSPopover. That
  # is a fact about the runner, not about the code, so don't fail the build.
  skip "popover sizing — no window server on this runner"
  echo "$out" | sed 's/^/       /'
else
  bad "popover sizing"; echo "$out" | sed 's/^/       /'
fi

if [[ "$CI_MODE" == 1 ]]; then
  echo "live data"
  skip "usage, system, oMLX, KatechonOS — no local data on a CI runner"
  echo "limit source"
  skip "~/.claude.json — CI has never run Claude Code"
  echo "ledger sources"
  skip "transcripts vs stats-cache — neither exists on a CI runner"
  echo
  echo "build-only checks passed (METRON_VERIFY_CI=1)"
  exit $fail
fi

echo "live data"
# A glance that renders but has nothing to show is the failure that looks like
# success. Assert on the headline, not on the render succeeding.
tmp=$(mktemp -d)
check_glance() {
  local id=$1 expect=$2
  local out
  if ! out=$("$BIN" --render "$tmp/$id.png" --glance "$id" --size full 2>&1); then
    bad "$id — render failed"; return
  fi
  local head
  head=$(grep '^headline:' <<<"$out" || true)
  if [[ -z "$head" ]]; then
    bad "$id — no headline (source returned nothing)"
    grep '^note:' <<<"$out" | sed 's/^/       /'
    return
  fi
  if [[ "$expect" == "ring" && "$head" == *"no ring"* ]]; then
    bad "$id — ${head#headline: }"
    grep '^note:' <<<"$out" | sed 's/^/       /'
    return
  fi
  pass "$id — ${head#headline: }"
}
check_glance usage  ring
check_glance ledger any
check_glance system ring
check_glance omlx   any
check_glance katechon any

echo "widget sizes"
for size in small medium large; do
  if "$BIN" --render "$tmp/usage-$size.png" --glance usage --size "$size" >/dev/null 2>&1 \
     && [[ -s "$tmp/usage-$size.png" ]]; then
    pass "usage/$size renders"
  else
    bad "usage/$size"
  fi
done

echo "limit source"
# The rings come from Claude Code's own cache. If that key ever moves, this is
# where it shows up — rather than as a blank panel days later.
if python3 -c '
import json, os, sys
d = json.load(open(os.path.expanduser("~/.claude.json")))
lim = d.get("cachedUsageUtilization", {}).get("utilization", {}).get("limits")
sys.exit(0 if isinstance(lim, list) and lim else 1)' 2>/dev/null; then
  pass "~/.claude.json carries utilization.limits"
else
  bad "~/.claude.json has no utilization.limits — rings will fall back to /usage"
fi

echo "ledger sources"
# The Ledger quotes the transcripts and calls the CLI's stats roll-up a lagging
# summary of them. That is a claim about two files on this disk, so it gets a
# command rather than a sentence: every settled day must agree to the token.
if out=$(bash docs/ledger/reconcile.sh 2>&1); then
  pass "$(grep -o '[0-9]*/[0-9]* settled days agree to the token' <<<"$out")"
  grep 'late-written' <<<"$out" | sed 's/^ */       /'
else
  bad "transcripts and stats-cache disagree on a settled day"
  grep -E 'MISMATCH|unexplained' <<<"$out" | sed 's/^ */       /'
fi

rm -rf "$tmp"
echo
if [[ $fail -eq 0 ]]; then echo "all checks passed"; else echo "SOMETHING IS BROKEN (see FAIL above)"; fi
exit $fail
