#!/bin/bash
# A release build must be universal and signed by the expected identity. Both
# have been wrong before: build.sh shipped arm64-thin for weeks, and a codesign
# failure was swallowed by `|| true` and surfaced days later as a bundle that
# would not launch.
#
# Checks dist/Metron.app if it exists. Referenced by PLAN.md.
set -uo pipefail
cd "$(dirname "$0")/../.."
APP=dist/Metron.app
TEAM=C7WX7DJYLP

fail=0
pass() { printf "  \033[32mok\033[0m   %s\n" "$1"; }
bad()  { printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=1; }
skip() { printf "  \033[33mskip\033[0m %s\n" "$1"; }

if [[ ! -d "$APP" ]]; then
  skip "no $APP — run: METRON_UNIVERSAL=1 METRON_SIGN_ID=\"Developer ID Application: Vessels Publishing LLC ($TEAM)\" ./build.sh"
  exit 0
fi

archs=$(lipo -archs "$APP/Contents/MacOS/Metron" 2>/dev/null)
[[ "$archs" == *x86_64* && "$archs" == *arm64* ]] \
  && pass "universal ($archs)" || bad "not universal — got '$archs'"

codesign --verify --deep --strict "$APP" 2>/dev/null \
  && pass "signature verifies" || bad "signature does not verify"

info=$(codesign -dv --verbose=4 "$APP" 2>&1)
if grep -q "TeamIdentifier=$TEAM" <<<"$info"; then
  pass "signed by team $TEAM"
elif grep -q "Signature=adhoc" <<<"$info"; then
  bad "ad-hoc signed — METRON_SIGN_ID was not set"
else
  bad "unexpected signer: $(grep -m1 '^Authority=' <<<"$info")"
fi

# Hardened runtime is a precondition for notarisation, not a nicety.
grep -q "flags=.*runtime" <<<"$info" \
  && pass "hardened runtime" || bad "hardened runtime missing — notarisation will reject"

# Notarisation is the owner's step; report honestly either way.
if spctl -a -t exec "$APP" 2>/dev/null; then
  pass "Gatekeeper accepts it — notarised and stapled"
else
  skip "not notarised yet — see PLAN.md 'Notarising'"
fi

echo
[[ $fail -eq 0 ]] && echo "signature checks passed" || echo "SIGNATURE IS WRONG (see FAIL above)"
exit $fail
