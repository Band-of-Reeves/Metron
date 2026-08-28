#!/bin/bash
# One command that answers "is Metron actually working?" without reading prose.
# Exits non-zero on the first real failure. Every check below is something that
# has genuinely broken at least once.
set -uo pipefail
cd "$(dirname "$0")"

fail=0
pass() { printf "  \033[32mok\033[0m   %s\n" "$1"; }
bad()  { printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=1; }

echo "build"
if swift build -c release >/tmp/metron-verify-build.log 2>&1; then
  pass "release build"
else
  bad "release build — see /tmp/metron-verify-build.log"; exit 1
fi

BIN=./.build/release/Metron

echo "popover sizing"
# Catches the class of bug where a panel grows after the popover is sized and
# the header ends up clipped off the top.
if out=$("$BIN" --measure 2>&1) && grep -q "^ok:" <<<"$out"; then
  pass "every popover matches its panel"
else
  bad "popover sizing"; echo "$out" | sed 's/^/       /'
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

rm -rf "$tmp"
echo
if [[ $fail -eq 0 ]]; then echo "all checks passed"; else echo "SOMETHING IS BROKEN (see FAIL above)"; fi
exit $fail
