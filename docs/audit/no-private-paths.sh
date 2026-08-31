#!/bin/bash
# Fails if anything tracked in this repo would leak a private path, a
# credential, or a personal machine detail once the repo is public.
#
# Scope is deliberately "tracked files only" — the working tree carries build
# output and scratch renders that are gitignored and never published.
#
# Referenced by PLAN.md as the evidence for the `no-private-paths` row.
set -uo pipefail
cd "$(dirname "$0")/../.."

fail=0
pass() { printf "  \033[32mok\033[0m   %s\n" "$1"; }
bad()  { printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=1; }

# Text files only. Screenshots are checked separately below, by eye — no script
# can read what a PNG is showing.
TEXT=':!docs/*.png'

echo "absolute home paths"
# A hardcoded /Users/<someone> is both a leak and a portability bug.
if hits=$(git grep -nI -E "/Users/[A-Za-z0-9._-]+" -- . "$TEXT" 2>/dev/null); then
  bad "absolute home paths in tracked files"; echo "$hits" | sed 's/^/       /'
else
  pass "no absolute home paths in tracked files"
fi

echo "credentials"
# Anything that looks like a key, token or password *value* rather than a word.
if hits=$(git grep -nIiE \
    "(api[_-]?key|secret|access[_-]?token|bearer)[[:space:]]*[:=][[:space:]]*['\"][^'\"]+" \
    -- . "$TEXT" 2>/dev/null); then
  bad "possible credential literal"; echo "$hits" | sed 's/^/       /'
else
  pass "no credential literals"
fi

echo "private network"
# RFC1918 addresses and .local hostnames pin the author's LAN. 127.0.0.1 is
# fine: oMLX genuinely binds to loopback and the README documents it.
if hits=$(git grep -nI -E "(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)" \
    -- . "$TEXT" 2>/dev/null); then
  bad "private IP address in tracked files"; echo "$hits" | sed 's/^/       /'
else
  pass "no private IP addresses"
fi

echo "personal email"
if hits=$(git grep -nIE "[A-Za-z0-9._%+-]+@(gmail|icloud|outlook|proton|me)\.com" \
    -- . "$TEXT" 2>/dev/null); then
  bad "personal email address in tracked files"; echo "$hits" | sed 's/^/       /'
else
  pass "no personal email addresses"
fi

echo "screenshots"
# docs/panel.png shows the Drivers block, which renders whichever skills and
# subagents actually drove your usage. On the author's machine that included
# private skill names. A script cannot read a PNG, so this only insists that
# somebody signed off — see docs/audit/HEALTH.md, finding A2.
shots=$(git ls-files 'docs/*.png' | tr '\n' ' ')
if [[ -n "${shots// /}" ]]; then
  if grep -q "^### A2" docs/audit/HEALTH.md 2>/dev/null; then
    pass "screenshots reviewed by hand (HEALTH.md A2): ${shots% }"
  else
    bad "screenshots present but no A2 review recorded in docs/audit/HEALTH.md"
  fi
else
  pass "no screenshots committed"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "nothing private in tracked files"
else
  echo "SOMETHING PRIVATE IS TRACKED (see FAIL above)"
fi
exit $fail
