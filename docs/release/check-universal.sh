#!/bin/bash
# Proves the release artifact is what the release page claims it is: a
# universal, signed .app that launches far enough to render a glance.
#
# The old build.sh produced an arm64-thin binary, so anything handed to an
# Intel Mac simply would not run — and nothing said so. This is the check that
# would have caught it.
set -uo pipefail
cd "$(dirname "$0")/../.."

fail=0
pass() { printf "  \033[32mok\033[0m   %s\n" "$1"; }
bad()  { printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=1; }

METRON_UNIVERSAL=1 ./build.sh >/tmp/metron-universal.log 2>&1 \
  || { bad "universal build — see /tmp/metron-universal.log"; exit 1; }
pass "universal build"

BIN=dist/Metron.app/Contents/MacOS/Metron
arches=$(lipo -archs "$BIN" 2>/dev/null)
for want in arm64 x86_64; do
  if grep -qw "$want" <<<"$arches"; then
    pass "$want present"
  else
    bad "$want missing — got: ${arches:-nothing}"
  fi
done

# An unsigned bundle does not fail at build time. It fails to launch days
# later, with no explanation.
if codesign --verify --strict dist/Metron.app 2>/dev/null; then
  pass "signature verifies"
else
  bad "signature does not verify"
fi

# The bundle actually runs. `system` is the one glance that needs no external
# source, so this is true on any machine — including a CI runner.
out=$(mktemp -d)/probe.png
if "$BIN" --render "$out" --glance system --size large >/dev/null 2>&1 && [[ -s "$out" ]]; then
  pass "the built bundle renders"
else
  bad "the built bundle did not render"
fi

exit $fail
