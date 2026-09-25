#!/usr/bin/env bash
# No squad script filters gh's listings by label: for labels whose emoji is a ZWJ sequence, as the
# owner and needs-ceo labels are, gh silently finds nothing (#56). Filter `--json labels` in jq
# instead, as squad-handoff.sh does. Comments may name the flag; code may not, in its long form
# (--label, --label=) or its short one (-l), on one line or continued over several with a backslash.
set -u
root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root" || exit 2

# `joined <file>` prints the file with its continued lines joined, so that a flag on the line after
# a backslash still counts.
joined() { awk '/\\$/ { sub(/\\$/, ""); printf "%s", $0; next } { print }' "$1"; }

found=0
for file in scripts/squad-*.sh .githooks/*; do
  # gh, then a label flag before any comment or pipe (a `grep -l` after a pipe is not gh's).
  matches="$(joined "$file" | grep -nE '^[^#]*(^|[^[:alnum:]_])gh [^#|]*[[:space:]](--label|-l)([ =]|$)')"
  if [ -n "$matches" ]; then
    printf '%s\n' "$matches" | sed "s|^|$file: joined line |"
    found=1
  fi
done
if [ "$found" -ne 0 ]; then
  echo "check-gh-filters: a squad script filters gh by label; filter --json labels in jq instead (#56)" >&2
  exit 1
fi
