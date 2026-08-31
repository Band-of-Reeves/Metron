#!/bin/bash
# The Ledger claims the transcripts are the source of truth and the CLI's
# stats roll-up is a lagging summary of them. This is the command that proves
# it, rather than the sentence that asserts it.
#
# Referenced by PLAN.md as the evidence for the `ledger-sources-agree` row.
set -uo pipefail
exec python3 "$(dirname "$0")/reconcile.py" "$@"
