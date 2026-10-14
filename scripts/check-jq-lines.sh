#!/usr/bin/env bash
# Every squad script that runs jq drops the CR that jq ends each line with on Windows (#405): it
# defines the wrapper below, which every jq of the script then goes through, and asks `type -P`, not
# `command -v`, whether jq is installed, since `command -v` finds the wrapper. A script runs jq when
# a line of its code, not a comment, names jq as a word: gh's --jq is gh's own, and writes LF there.
set -u
root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root" || exit 2

wrapper="jq() { command jq \"\$@\" | tr -d '\\r'; return \"\${PIPESTATUS[0]}\"; }"
found=0 walked=0
for file in scripts/squad-*.sh; do
  grep -vE '^[[:space:]]*#' "$file" | grep -qE '(^|[^[:alnum:]_.-])jq([^[:alnum:]_.-]|$)' || continue
  walked=$((walked + 1))
  if ! grep -qxF -- "$wrapper" "$file"; then
    echo "check-jq-lines: $file runs jq without defining, as the other squad scripts do: $wrapper" >&2
    found=1
  fi
  if grep -nE '^[^#]*command -v jq' "$file" >&2; then
    echo "check-jq-lines: $file asks command -v whether jq is installed, which finds the wrapper; ask type -P" >&2
    found=1
  fi
done
# A walk that found no script is no check: the glob or the search is wrong.
if [ "$walked" -eq 0 ]; then
  echo "check-jq-lines: no squad script runs jq, so nothing was checked" >&2
  exit 1
fi
[ "$found" -eq 0 ] || exit 1
echo "check-jq-lines: the $walked squad scripts that run jq each drop its CRs" >&2
