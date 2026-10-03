#!/usr/bin/env bash
# Measure how much of the squad's scripts this repository's tests run (agent-squad #180), in CI.
# Each scripts/check-*.sh runs under kcov, which follows the bash scripts it starts and records the
# lines each one ran. The tests also run copies of the scripts, from an installed playbook or a
# tag's tarball in a temporary directory: a copy counts for the repository's script of the same
# name when kcov found exactly the same lines to measure in both, which a different script of that
# name (the pre-push shim, a stub installer) does not have.
#
# Usage: ci-coverage.sh <output directory>
# It writes there summary.md, the total and one line per script, thinnest first, which CI adds to
# the job's summary; report/, kcov's HTML report of every test merged, where each copy keeps its
# temporary path; and runs/, each test's own report and output. No figure fails it, and a test
# that fails under kcov is named in the summary. Exit: 0 measured; 1 kcov is missing or measured
# nothing.
set -u
out="${1:?usage: ci-coverage.sh <output directory>}"
command -v kcov >/dev/null 2>&1 || { echo "ci-coverage: kcov is not installed" >&2; exit 1; }
root="$(git rev-parse --show-toplevel)" || exit 1
cd "$root" || exit 1
mkdir -p "$out/runs" || exit 1
out="$(cd "$out" && pwd -P)"

# 1. Each test under kcov, which keeps the bash files whose path contains one of these names.
failed=()
for test in scripts/check-*.sh; do
  name="$(basename "$test" .sh)"
  kcov --include-pattern=squad-,pre-push,install.sh "$out/runs/$name" "$test" \
    >"$out/runs/$name.log" 2>&1 </dev/null || failed+=("$name")
done
# kcov writes a codecov.json per script it ran and, for some tests, a merged one too: reading
# every one is safe, since a line counts as run when any record says so.
recorded=()
while IFS= read -r file; do recorded+=("$file"); done < <(find "$out/runs" -name codecov.json)
[ ${#recorded[@]} -gt 0 ] || { echo "ci-coverage: kcov recorded nothing in $out/runs" >&2; exit 1; }

# 2. Per script, across every test and every copy with the same lines: the lines kcov measures,
#    and those that ran at least once. kcov writes a line's hits as a number, or as "hits/total",
#    and a file under the directory it ran in by its path relative to it.
measured=(scripts/squad-*.sh .githooks/pre-push install.sh)
cat "${recorded[@]}" | jq -s -r --arg root "$root" --arg failed "${failed[*]}" '
  def hits: if type == "number" then . else tostring | split("/")[0] | tonumber end;
  def basename: split("/") | last;
  def pct($r; $m): if $m == 0 then "not run" else "\($r * 1000 / $m | round / 10) %" end;
  # path -> {line: ran?}, every test merged.
  (map(.coverage | to_entries[] | .key |= if startswith("/") then . else $root + "/" + . end) | group_by(.key)
   | map({key: .[0].key, value: (map(.value | with_entries(.value |= (hits > 0))) | reduce .[] as $m ({};
       reduce ($m | to_entries[]) as $l (.; .[$l.key] = ((.[$l.key] // false) or $l.value))))})
   | from_entries) as $files
  | [$ARGS.positional[] as $script | ($root + "/" + $script) as $path
     | if $files[$path] == null then {script: $script, measured: 0, ran: 0}
       else ($files[$path] | keys) as $lines
         | [$files | to_entries[] | select((.key | basename) == ($script | basename) and (.value | keys) == $lines)]
           as $copies
         | {script: $script, measured: ($lines | length), copies: (($copies | length) - 1),
            ran: ([$lines[] as $l | select(any($copies[]; .value[$l]))] | length)}
       end]
  | sort_by(if .measured == 0 then -1 else .ran / .measured end) as $rows
  | ($rows | map(.ran) | add) as $ran | ($rows | map(.measured) | add) as $all
  | "## Test coverage of the scripts",
  "",
  "The lines of each script that `scripts/check-*.sh` ran, measured with kcov. A copy that a test runs from a temporary directory counts for the script it copies.",
  "",
  "| Script | Lines run | Lines measured | Coverage |",
  "|---|--:|--:|--:|",
  "| **Total** | **\($ran)** | **\($all)** | **\(pct($ran; $all))** |",
  ($rows[] | "| `\(.script)`\(if (.copies // 0) > 0 then " (and \(.copies) cop\(if .copies == 1 then "y" else "ies" end))" else "" end) | \(.ran) | \(.measured) | \(pct(.ran; .measured)) |"),
  (if $failed == "" then empty else "", "Tests that failed under kcov, so their figures may be short: `\($failed)`." end)
' --args "${measured[@]}" >"$out/summary.md" || exit 1

# 3. kcov's own report, every test merged into one.
kcov --merge "$out/report" "$out"/runs/*/ >/dev/null 2>&1 || echo "ci-coverage: kcov could not merge the reports" >&2
cat "$out/summary.md"
