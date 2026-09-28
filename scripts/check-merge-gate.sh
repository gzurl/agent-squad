#!/usr/bin/env bash
# Check what the merge gate of SQUAD.md §4.9 does when a PR is behind its base. Up to date: nothing.
# Behind, with no file the PR also changes: a warning (#64), and the gate's result unchanged, exit 0
# and the head alone on stdout. Behind, with a file the PR also changes: the gate stops, exit 3 and
# nothing on stdout, naming the base's SHA (#80), unless SQUAD_BEHIND_CHECKED holds that SHA, which
# acknowledges that base and no other. When the gate cannot tell (no comparison, no count, no base
# SHA), it stops the same way, and an acknowledgement after a manual comparison lets it pass. The
# comparison is of the base whose SHA was read, even when the base moves between the two calls.
# GitHub is replaced by a gh that answers every call the gate makes, computing the comparison from a
# scratch repository; this script touches neither the repository it is run from nor GitHub.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
gate="$root/scripts/squad-merge-gate.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Gate check" GIT_AUTHOR_EMAIL=gate@example.com
export GIT_COMMITTER_NAME="Gate check" GIT_COMMITTER_EMAIL=gate@example.com

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-merge-gate.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# GitHub, as far as the gate is concerned. PR 7 of o/r is the branch `pr` of the scratch repository
# SCRATCH, against `main`, approved on its head, with no open thread, the approved label and green
# CI. `compare` and the PR's files come from git; GATE_COMPARE=fail makes the comparison fail,
# GATE_COMPARE=no-count makes it answer without the count of commits, GATE_BASE=unreadable makes
# the base's tip unreadable, and GATE_BASE=moves lands a commit on main right after its SHA is read.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
[ "${1:-}" = api ] || exit 1
shift
filter=""
slurp=0
endpoint=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) filter="$2"; shift 2 ;;
    --slurp) slurp=1; shift ;;
    --paginate) shift ;;
    -f) shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
g() { git -C "$SCRATCH" "$@"; }
head="$(g rev-parse pr)"
case "$endpoint" in
  graphql)
    json='{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true}]}}}}}' ;;
  repos/o/r/pulls/7/reviews)
    json="$(jq -n --arg head "$head" '[{commit_id: $head, body: "a review\n\nQA-VERDICT: APPROVED"}]')" ;;
  repos/o/r/pulls/7/files)
    json="$(g diff --name-only "$(g merge-base pr main)" pr | jq -R . | jq -s 'map({filename: .})')" ;;
  repos/o/r/issues/7/comments)
    json='[]' ;;
  repos/o/r/commits/*/check-runs)
    json='{"check_runs":[{"conclusion":"success"}]}' ;;
  repos/o/r/commits/*)
    [ "${GATE_BASE:-}" != unreadable ] || exit 1
    json="$(jq -n --arg sha "$(g rev-parse "${endpoint#repos/o/r/commits/}")" '{sha: $sha}')"
    if [ "${GATE_BASE:-}" = moves ]; then
      echo "late" > "$SCRATCH/late.txt" && g add late.txt && g commit -qm "lands late"
    fi ;;
  repos/o/r/compare/*)
    [ "${GATE_COMPARE:-}" != fail ] || exit 1
    if [ "${GATE_COMPARE:-}" = no-count ]; then
      json='{"files":[]}'
      [ "$slurp" -eq 0 ] || json="[$json]"
      printf '%s' "$json" | jq -r "${filter:-.}"
      exit 0
    fi
    spec="${endpoint#repos/o/r/compare/}"
    from="${spec%%...*}"
    to="${spec##*...}"
    json="$(g diff --name-only "$(g merge-base "$from" "$to")" "$to" | jq -R . \
      | jq -s --argjson ahead "$(g rev-list --count "$from..$to")" '{ahead_by: $ahead, files: map({filename: .})}')" ;;
  repos/o/r/pulls/7)
    json="$(jq -n --arg head "$head" --arg body "${PR_BODY:-}" \
      '{head: {sha: $head}, base: {ref: "main"}, labels: [{name: "✅ status:approved"}], body: $body}')" ;;
  *) exit 1 ;;
esac
[ "$slurp" -eq 0 ] || json="[$json]"
if [ -n "$filter" ]; then
  printf '%s' "$json" | jq -r "$filter"
else
  printf '%s\n' "$json"
fi
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH"

# The scratch repository: main with three files, and the PR's branch, which changes tool.sh and
# whose description names README.md.
scratch="$lab/scratch"
git init -q -b main "$scratch" || exit 2
for f in README.md tool.sh other.txt; do echo "first $f" > "$scratch/$f"; done
git -C "$scratch" add -A && git -C "$scratch" commit -qm "the base" || exit 2
git -C "$scratch" switch -q -c pr && echo "the PR's change" >> "$scratch/tool.sh" \
  && git -C "$scratch" commit -qam "the PR" || exit 2
export SCRATCH="$scratch" PR_BODY="Makes tool.sh faster, as the README.md explains. It leaves a note in \`notes\`."
head="$(git -C "$scratch" rev-parse pr)"

# `run_gate` runs the gate on PR 7, leaving its stdout in $out, its stderr in $err and its exit code
# in $code.
run_gate() {
  out="$("$gate" 7 o/r 2>"$lab/err")"
  code=$?
  err="$(cat "$lab/err")"
}
# `result_unchanged <case>` passes when the gate exited 0 and printed the head, alone, on stdout;
# `stopped <case>` when it exited 3 and printed nothing there, so that §4.9's `&&` merges nothing.
result_unchanged() {
  if [ "$code" -eq 0 ] && [ "$out" = "$head" ]; then
    pass "$1: the gate exits 0 and prints the head alone on stdout"
  else
    fail "$1: the gate exited $code and printed '$out'"
  fi
}
stopped() {
  if [ "$code" -eq 3 ] && [ -z "$out" ]; then
    pass "$1: the gate stops, exit 3, nothing on stdout"
  else
    fail "$1: the gate exited $code and printed '$out'"
  fi
}

# 1. Up to date: no warning.
run_gate
result_unchanged "up to date"
if grep -q 'WARNING' <<<"$err"; then
  fail "up to date: the gate warned: $err"
else
  pass "up to date: no warning"
fi

# 2. Behind, with no file in common: main gains a commit that touches README.md and other.txt and
#    adds two files: `a`, which the description only seems to name ("a note"), and `notes`, which
#    it names in backticks. The PR changes tool.sh, which main has not touched: a warning only.
git -C "$scratch" switch -q main
echo "main's change" >> "$scratch/README.md" && echo "main's change" >> "$scratch/other.txt"
echo "new" > "$scratch/a" && echo "new" > "$scratch/notes"
git -C "$scratch" add -A && git -C "$scratch" commit -qm "main moves"
first_base="$(git -C "$scratch" rev-parse main)"
run_gate
result_unchanged "behind, no file in common"
if grep -qF 'PR #7 is behind main by 1 commit(s)' <<<"$err"; then
  pass "behind, no file in common: the warning says by how many commits"
else
  fail "behind, no file in common: no count of the commits main gained: $err"
fi
if grep -qxF "  README.md (the PR's description names it)" <<<"$err" && grep -qxF '  other.txt' <<<"$err" \
  && grep -qxF "  notes (the PR's description names it)" <<<"$err" && grep -qxF '  a' <<<"$err"; then
  pass "behind, no file in common: it lists the files main touched, marking those the PR names, and only those"
else
  fail "behind, no file in common: the files are not listed as expected: $err"
fi
if grep -qF "check the PR's claims against main" <<<"$err" && ! grep -q 'gate FAILED' <<<"$err"; then
  pass "behind, no file in common: it says what to do before merging, and does not fail"
else
  fail "behind, no file in common: it does not say what to do, or it fails: $err"
fi

# 3. Behind, with a file in common: main changes tool.sh too. The gate stops, names the base's SHA
#    and says how to acknowledge it.
echo "main's change" >> "$scratch/tool.sh" && git -C "$scratch" commit -qam "main moves again"
base="$(git -C "$scratch" rev-parse main)"
run_gate
stopped "behind, with a file in common"
if grep -qxF '  tool.sh (the PR changes it too)' <<<"$err" && grep -qF 'gate FAILED' <<<"$err" \
  && grep -qF "SQUAD_BEHIND_CHECKED=$base" <<<"$err"; then
  pass "behind, with a file in common: it names the file in common, the base's SHA and the acknowledgement"
else
  fail "behind, with a file in common: the reason is not as expected: $err"
fi

# 4. Acknowledged: SQUAD_BEHIND_CHECKED holds the base's SHA, in full or as a prefix of 7 or more.
for acknowledged in "$base" "${base:0:7}"; do
  export SQUAD_BEHIND_CHECKED="$acknowledged"
  run_gate
  unset SQUAD_BEHIND_CHECKED
  result_unchanged "acknowledged as ${acknowledged:0:12}"
  if grep -qF "checked against main at ${base:0:7}" <<<"$err"; then
    pass "acknowledged as ${acknowledged:0:12}: the gate says whose acknowledgement lets it pass"
  else
    fail "acknowledged as ${acknowledged:0:12}: no line about the acknowledgement: $err"
  fi
done

# 5. An acknowledgement of another base does not count: the base the author checked has moved, or
#    the value is not that base's SHA at all.
for acknowledged in "$first_base" "${base:0:6}" "not-a-sha"; do
  export SQUAD_BEHIND_CHECKED="$acknowledged"
  run_gate
  unset SQUAD_BEHIND_CHECKED
  stopped "acknowledged as '${acknowledged:0:12}', which is not the base"
done

# 6. GitHub cannot compare: the gate stops, naming the base's SHA, which an acknowledgement after a
#    manual comparison lets through.
export GATE_COMPARE=fail
run_gate
stopped "no comparison"
if grep -qF 'cannot tell whether PR #7 is behind main' <<<"$err" && grep -qF "SQUAD_BEHIND_CHECKED=$base" <<<"$err"; then
  pass "no comparison: it says it cannot tell, and names the base's SHA to acknowledge"
else
  fail "no comparison: the reason is not as expected: $err"
fi
export SQUAD_BEHIND_CHECKED="$base"
run_gate
unset SQUAD_BEHIND_CHECKED GATE_COMPARE
result_unchanged "no comparison, checked by hand"
if grep -qF "checked by hand against main at ${base:0:7}" <<<"$err"; then
  pass "no comparison, checked by hand: the gate says so"
else
  fail "no comparison, checked by hand: no line about it: $err"
fi

# 7. GitHub compares, but without the count of commits: the same stop, not a shell error.
export GATE_COMPARE=no-count
run_gate
unset GATE_COMPARE
stopped "no count"
if grep -qF 'cannot tell whether PR #7 is behind main' <<<"$err" && ! grep -q 'integer expected' <<<"$err"; then
  pass "no count: it says it cannot tell, without a shell error"
else
  fail "no count: the reason is not as expected, or a shell error: $err"
fi

# 8. The base's tip cannot be read: the gate stops and asks to be run again.
export GATE_BASE=unreadable
run_gate
unset GATE_BASE
stopped "no base SHA"
if grep -qF 'Run the gate again' <<<"$err"; then
  pass "no base SHA: it asks to run the gate again"
else
  fail "no base SHA: the reason is not as expected: $err"
fi

# 9. The base moves between the two calls: the comparison is of the SHA that was read, so a commit
#    that lands on main in between is not listed, and the acknowledgement of that SHA still holds.
export GATE_BASE=moves SQUAD_BEHIND_CHECKED="$base"
run_gate
unset GATE_BASE SQUAD_BEHIND_CHECKED
result_unchanged "a base that moves during the gate, acknowledged as read"
if ! grep -q 'late.txt' <<<"$err"; then
  pass "a base that moves during the gate: the commit that landed in between is not listed"
else
  fail "a base that moves during the gate: it compared with a newer base than the SHA it read: $err"
fi

exit "$status"
