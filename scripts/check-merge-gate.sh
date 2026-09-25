#!/usr/bin/env bash
# Check that the merge gate of SQUAD.md §4.9 warns, without failing, when a PR is behind its base
# (#64): nothing when the PR is up to date; when it is behind, how many commits the base gained and
# the files they touched, marking those the PR also changes or names in its description; and a note
# when GitHub cannot compare. In every case the gate's result stays what it was: exit 0 and the
# verified head, alone, on stdout. GitHub is replaced by a gh that answers every call the gate makes,
# computing the comparison from a scratch repository; this script touches neither the repository it
# is run from nor GitHub.
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
# CI. `compare` and the PR's files come from git; GATE_COMPARE=fail makes the comparison fail, and
# GATE_COMPARE=no-count makes it answer without the count of commits.
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
# `result_unchanged <case>` passes when the gate exited 0 and printed the head, alone, on stdout.
result_unchanged() {
  if [ "$code" -eq 0 ] && [ "$out" = "$head" ]; then
    pass "$1: the gate exits 0 and prints the head alone on stdout"
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

# 2. Behind: main gains two commits, touching the three files and adding two: `a`, which the
#    description only seems to name ("a note"), and `notes`, which it names in backticks.
git -C "$scratch" switch -q main
echo "main's change" >> "$scratch/README.md" && echo "main's change" >> "$scratch/other.txt"
echo "new" > "$scratch/a" && echo "new" > "$scratch/notes"
git -C "$scratch" add -A && git -C "$scratch" commit -qm "main moves"
echo "main's change" >> "$scratch/tool.sh" && git -C "$scratch" commit -qam "main moves again"
run_gate
result_unchanged "behind"
if grep -qF 'PR #7 is behind main by 2 commit(s)' <<<"$err"; then
  pass "behind: the warning says by how many commits"
else
  fail "behind: no count of the commits main gained: $err"
fi
if grep -qxF '  tool.sh (the PR changes it too)' <<<"$err" \
  && grep -qxF "  README.md (the PR's description names it)" <<<"$err" && grep -qxF '  other.txt' <<<"$err" \
  && grep -qxF "  notes (the PR's description names it)" <<<"$err" && grep -qxF '  a' <<<"$err"; then
  pass "behind: it lists the files main touched, marking those the PR changes or names, and only those"
else
  fail "behind: the files are not listed as expected: $err"
fi
if grep -qF "check the PR's claims against main" <<<"$err"; then
  pass "behind: it says what to do before merging"
else
  fail "behind: it does not say what to do: $err"
fi

# 3. GitHub cannot compare: a note, and the same result.
export GATE_COMPARE=fail
run_gate
unset GATE_COMPARE
result_unchanged "no comparison"
if grep -qF 'cannot tell whether PR #7 is behind' <<<"$err"; then
  pass "no comparison: the gate says it cannot tell"
else
  fail "no comparison: no note: $err"
fi

# 4. GitHub compares, but without the count of commits: the same note, not a shell error.
export GATE_COMPARE=no-count
run_gate
unset GATE_COMPARE
result_unchanged "no count"
if grep -qF 'cannot tell whether PR #7 is behind' <<<"$err" && ! grep -q 'integer expected' <<<"$err"; then
  pass "no count: the gate says it cannot tell"
else
  fail "no count: no note, or a shell error: $err"
fi

exit "$status"
