#!/usr/bin/env bash
# Exploration for agent-squad #180: what kcov records while two checks run.
set -u
out="${1:-coverage}"
mkdir -p "$out"
for test in scripts/check-merge-gate.sh scripts/check-gate.sh; do
  name="$(basename "$test" .sh)"
  kcov --include-pattern=squad-,pre-push,install.sh "$out/$name" "$test" >"$out/$name.log" 2>&1
  echo "== $test exit $?, last lines:"; tail -3 "$out/$name.log"
  echo "== files:"; find "$out/$name" -maxdepth 2 | sed "s|$out/||" | head -30
  for f in "$out/$name"/*/codecov.json; do [ -f "$f" ] && { echo "== $f"; jq -c '.coverage | to_entries[] | {key, lines: (.value | length), hit: ([.value[] | select(. != "0" and (startswith("0/") | not))] | length)}' "$f"; }; done
  for f in "$out/$name"/*/coverage.json; do [ -f "$f" ] && { echo "== $f"; jq -c '.files[] | {file, percent_covered, covered_lines, total_lines}' "$f"; }; done
done
