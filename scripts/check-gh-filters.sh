#!/usr/bin/env bash
# No squad script filters gh's listings with --label: for labels whose emoji is a ZWJ sequence, as
# the owner and needs-ceo labels are, gh silently finds nothing (#56). Filter `--json labels` in jq
# instead, as squad-handoff.sh does. Comments may name the flag; code may not.
set -u
root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root" || exit 2
if grep -nE '^[^#]*(^|[^[:alnum:]_])gh [^#]*--label' scripts/squad-*.sh .githooks/*; then
  echo "check-gh-filters: a squad script filters gh by --label; filter --json labels in jq instead (#56)" >&2
  exit 1
fi
