#!/usr/bin/env bash
# Check what the merge gate of SQUAD.md §4.9 does when a PR is behind its base. Up to date: nothing.
# Behind, with no file the PR also changes: a warning (#64), and the gate's result unchanged, exit 0
# and the head alone on stdout. Behind, with a file the PR also changes: the gate stops, exit 3 and
# nothing on stdout, naming the base's SHA (#80), unless SQUAD_BEHIND_CHECKED holds that SHA, which
# acknowledges that base and no other. When the gate cannot tell (no comparison, no count, no base
# SHA, no files of the PR, a comparison cut at GitHub's 300 files), it stops the same way, and an
# acknowledgement after a manual comparison lets it pass. A rename counts under both of its names,
# on either side. The comparison is of the base whose SHA was read, even when the base moves
# between the two calls.
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
# GATE_COMPARE=no-count makes it answer without the count of commits, GATE_COMPARE=300 makes it
# answer with GitHub's maximum of 300 files, GATE_BASE=unreadable makes the base's tip unreadable,
# GATE_BASE=moves lands a commit on main right after its SHA is read, GATE_FILES=fail makes the
# listing of the PR's files fail after printing part of it (a gate that read the output of a failed
# call would take it for the whole), GATE_FILES=none makes it empty, GATE_LABELS, a JSON array
# of names, replaces the PR's labels, and GATE_COMMENTS and GATE_INLINE, JSON arrays of bodies, are
# the PR's comments and its inline review comments. Files are reported as GitHub does: a rename under its new
# name, with the old one as previous_filename.
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
# `changed <from> <to>` prints the files changed between two commits as GitHub's API lists them.
changed() {
  g diff --name-status -M "$1" "$2" | jq -R 'split("\t") | if .[0] | startswith("R")
    then {filename: .[2], previous_filename: .[1]} else {filename: .[1]} end' | jq -s .
}
case "$endpoint" in
  graphql)
    json='{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true}]}}}}}' ;;
  repos/o/r/pulls/7/reviews)
    json="$(jq -n --arg head "$head" '[{commit_id: $head, body: "a review\n\nQA-VERDICT: APPROVED"}]')" ;;
  repos/o/r/pulls/7/files)
    if [ "${GATE_FILES:-}" = fail ]; then printf '[[{"filename":"page/one.txt"}]]\n'; exit 1; fi
    if [ "${GATE_FILES:-}" = none ]; then json='[]'; else json="$(changed "$(g merge-base pr main)" pr)"; fi ;;
  repos/o/r/issues/7/comments)
    json="$(jq '[.[] | {body: .}]' <<<"${GATE_COMMENTS:-[]}")" ;;
  repos/o/r/pulls/7/comments)
    json="$(jq '[.[] | {body: ., path: "tool.sh", line: 1}]' <<<"${GATE_INLINE:-[]}")" ;;
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
    json="$(changed "$(g merge-base "$from" "$to")" "$to" \
      | jq --argjson ahead "$(g rev-list --count "$from..$to")" '{ahead_by: $ahead, files: .}')"
    if [ "${GATE_COMPARE:-}" = 300 ]; then
      json="$(jq '.files = [range(300) | {filename: "bulk/\(.)"}]' <<<"$json")"
    fi ;;
  repos/o/r/pulls/7)
    # GATE_LABELS=unreadable makes the call that reads the labels fail, and only that one.
    if [ "${GATE_LABELS:-}" = unreadable ]; then case "$filter" in *labels*) echo "gh: HTTP 502" >&2; exit 1 ;; esac; GATE_LABELS="[]"; fi
    json="$(jq -n --arg head "$head" --arg body "${PR_BODY:-}" --argjson labels "${GATE_LABELS:-[\"✅ status:approved\"]}" \
      '{head: {sha: $head}, base: {ref: "main"}, labels: [$labels[] | {name: .}], body: $body}')" ;;
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

# 1b. The state labels (#99): to be merged, a PR carries exactly one of the three, ✅ status:approved.
#     Two or three at once stop the gate with exit 1, naming them, and so do the wrong one and
#     none, which is what a PR is left with when one command adds and removes the same label. A
#     label that is not a state does not count. GATE_LABELS replaces the PR's labels.
# `labels_refused <case> <labels as JSON> <reason>` expects exit 1, nothing on stdout and the reason.
labels_refused() {
  export GATE_LABELS="$2"
  run_gate
  unset GATE_LABELS
  if [ "$code" -eq 1 ] && [ -z "$out" ] && grep -qF -- "$3" <<<"$err"; then
    pass "$1: the gate fails, exit 1, saying so"
  else
    fail "$1: the gate exited $code, printed '$out', and said: $err"
  fi
}
labels_refused "approved and in review" '["✅ status:approved","👀 status:in-review"]' \
  "PR carries 2 state labels, where one is the rule: ✅ status:approved, 👀 status:in-review"
labels_refused "in progress and approved" '["🚧 status:in-progress","✅ status:approved"]' \
  "PR carries 2 state labels, where one is the rule: 🚧 status:in-progress, ✅ status:approved"
labels_refused "all three" '["👀 status:in-review","🚧 status:in-progress","✅ status:approved"]' \
  "PR carries 3 state labels, where one is the rule"
labels_refused "in review only" '["👀 status:in-review"]' "PR does not carry ✅ status:approved"
labels_refused "no label at all" '[]' "PR does not carry ✅ status:approved"
export GATE_LABELS='["📝 docs","✅ status:approved","🟡 P2"]'
run_gate
unset GATE_LABELS
result_unchanged "approved, with labels that are not states"
#     A label list that cannot be read stops the gate, and a state is a name that ends in one of the
#     three: a bare one counts, a name that only contains one does not.
labels_refused "unreadable label list" unreadable "cannot read the labels of PR #7"
labels_refused "approved and a bare in-review" '["✅ status:approved","status:in-review"]' "PR carries 2 state labels"
export GATE_LABELS='["✅ status:approved","⛔ status:blocked","🔁 status:in-review-2"]'
run_gate
unset GATE_LABELS
result_unchanged "approved, with blocked and a name that only contains a state"

# 1c. Body-only findings (#111): a PR comment whose first line, read without its bold markers, starts
#     with QA's signature, a status and a priority tag, and that has no Settled: line, stops the
#     gate. The signature may be plain or bold, and so may the Settled: line. Look-alikes do not
#     count: another role's signature, a note without a priority, a quote, a finding on a later line,
#     a signature without its colon, and an inline comment, which is a review thread.
# `findings <case> <unsettled> <comments as JSON>` expects exit 1 and that count when it is not 0,
# and the gate's usual pass when it is.
findings() {
  export GATE_COMMENTS="$3"
  run_gate
  unset GATE_COMMENTS
  if [ "$2" -eq 0 ]; then
    result_unchanged "$1"
  elif [ "$code" -eq 1 ] && [ -z "$out" ] && grep -qF -- "$2 body-only finding(s) without a Settled: line" <<<"$err"; then
    pass "$1: the gate fails, exit 1, counting $2 unsettled finding(s)"
  else
    fail "$1: the gate exited $code, printed '$out', and said: $err"
  fi
}
plain='👩🏼‍🔬[QA]: ⚠️ [P2] claims: no. The README says v24.'
bold='**👩🏼‍🔬[QA]:** ⚠️ [P3] A typo on line 4.'
settled_by='\n\nSettled: https://github.com/o/r/pull/7#issuecomment-1'
findings "a plain finding, not settled" 1 "$(jq -n --arg b "$plain" '[$b]')"
findings "a plain finding, settled" 0 "$(jq -n --arg b "$plain$(printf '%b' "$settled_by")" '[$b]')"
findings "a bold finding, not settled" 1 "$(jq -n --arg b "$bold" '[$b]')"
findings "a bold finding, settled" 0 "$(jq -n --arg b "$bold$(printf '%b' "$settled_by")" '[$b]')"
findings "a bold finding, settled by a bold Settled: line" 0 \
  "$(jq -n --arg b "$bold"$'\n\n**Settled:** https://github.com/o/r/pull/7#issuecomment-2' '[$b]')"
findings "a finding with bold around its status and priority, not settled" 1 \
  "$(jq -n '["👩🏼‍🔬[QA]: **⚠️ [P2]** claims: yes. The table is wrong."]')"
findings "a finding bold from its signature to its priority, not settled" 1 \
  "$(jq -n '["**👩🏼‍🔬[QA]: ⚠️ [P1]** The gate lets a stale verdict through."]')"
findings "one of each form, both settled" 0 \
  "$(jq -n --arg p "$plain$(printf '%b' "$settled_by")" --arg b "$bold$(printf '%b' "$settled_by")" '[$p, $b]')"
findings "one of each form, the bold one not settled" 1 \
  "$(jq -n --arg p "$plain$(printf '%b' "$settled_by")" --arg b "$bold" '[$p, $b]')"
findings "one of each form, neither settled" 2 "$(jq -n --arg p "$plain" --arg b "$bold" '[$p, $b]')"
findings "look-alikes that are not findings" 0 "$(jq -n '[
  "**👨🏼‍💻[DEV]:** ⚠️ [P2] A finding of my own, in bold.",
  "👨🏼‍💻[DEV]: ⚠️ [P2] And one in plain.",
  "**👩🏼‍🔬[QA]:** ⏳ Starting the review of PR #7 [P2 items first].",
  "👩🏼‍🔬[QA]: ✅ QA review — PR #7. Reviewed commit: PR #7 (`abc1234`).",
  "> **👩🏼‍🔬[QA]:** ⚠️ [P2] quoted in a reply",
  "**👨🏼‍💻[DEV]:** ✅ Answering the finding:\n**👩🏼‍🔬[QA]:** ⚠️ [P2] on its second line",
  "**👩🏼‍🔬[QA]** ⚠️ [P2] without the colon"
]')"
GATE_INLINE="$(jq -n --arg b "$bold" '[$b]')"
export GATE_INLINE
findings "a bold finding posted inline, where it is a review thread" 0 '[]'
unset GATE_INLINE

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

# 10. The PR's files cannot be read, or come back empty: the gate cannot tell whether the base
#     changed one of them, so it stops, naming the base's SHA, which an acknowledgement lets through.
for files in fail none; do
  export GATE_FILES="$files"
  run_gate
  stopped "the PR's files: $files"
  if grep -qF "cannot tell whether PR #7 is behind main" <<<"$err" && grep -qF 'SQUAD_BEHIND_CHECKED=' <<<"$err"; then
    pass "the PR's files: $files: it says it cannot tell, and names the base's SHA to acknowledge"
  else
    fail "the PR's files: $files: the reason is not as expected: $err"
  fi
  unset GATE_FILES
done
tip="$(git -C "$scratch" rev-parse main)"
export GATE_FILES=fail SQUAD_BEHIND_CHECKED="$tip"
run_gate
unset GATE_FILES SQUAD_BEHIND_CHECKED
result_unchanged "the PR's files unreadable, checked by hand"

# 11. A comparison that lists GitHub's maximum of 300 files may hide the file in common: it stops.
export GATE_COMPARE=300
run_gate
unset GATE_COMPARE
stopped "a comparison cut at 300 files"
if grep -qF "cannot tell whether PR #7 is behind main" <<<"$err"; then
  pass "a comparison cut at 300 files: it says it cannot tell"
else
  fail "a comparison cut at 300 files: the reason is not as expected: $err"
fi

# 12. Renames count under both names. A fresh repository, whose PR changes tool.sh: main renames
#     tool.sh; then, in another, the PR renames other.txt while main changes it.
renames="$lab/renames"
git init -q -b main "$renames" || exit 2
for f in tool.sh other.txt; do printf 'first %s\nwith enough lines\nfor git to see a rename\n' "$f" > "$renames/$f"; done
git -C "$renames" add -A && git -C "$renames" commit -qm "the base" || exit 2
git -C "$renames" switch -q -c pr && echo "the PR's change" >> "$renames/tool.sh" \
  && git -C "$renames" mv other.txt other2.txt && git -C "$renames" commit -qam "the PR" || exit 2
git -C "$renames" switch -q main && git -C "$renames" mv tool.sh tool2.sh \
  && git -C "$renames" commit -qm "main renames the PR's file" || exit 2
export SCRATCH="$renames"
head="$(git -C "$renames" rev-parse pr)"
run_gate
stopped "the base renames a file the PR changes"
if grep -qxF '  tool.sh (the PR changes it too)' <<<"$err"; then
  pass "the base renames a file the PR changes: the old name is marked as the PR's"
else
  fail "the base renames a file the PR changes: tool.sh is not marked: $err"
fi
git -C "$renames" reset -q --hard HEAD~1 && echo "main's change" >> "$renames/other.txt" \
  && git -C "$renames" commit -qam "main changes a file the PR renames" || exit 2
run_gate
stopped "the PR renames a file the base changes"
if grep -qxF '  other.txt (the PR changes it too)' <<<"$err"; then
  pass "the PR renames a file the base changes: it is marked as the PR's"
else
  fail "the PR renames a file the base changes: other.txt is not marked: $err"
fi
export SCRATCH="$scratch"

exit "$status"
