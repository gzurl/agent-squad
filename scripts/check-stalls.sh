#!/usr/bin/env bash
# Check that squad-stalls.sh finds the squad's stalls as agent-squad #174 says, against a gh that
# serves fixed pull requests, issues and reviews, at a fixed time. Who owns the next step: the
# reviewer of a PR whose head has no verdict (DEV on one QA authors), the author of one whose
# verdict asks for changes or approves, the author of a draft, the owner of an issue in progress.
# Items whose wait is declared, labelled needs-ceo or status:blocked themselves or through a PR's
# closing issue, are not watched. A stall is an item quiet for 30 minutes whose owner's session is
# idle: the owner is pinged once,
# and the CEO told once if it is still there an hour later. A session that waits on the CEO, or is
# not open, is reported to the CEO at once; a busy one never. Activity starts a stall afresh.
# Nothing found prints nothing; GitHub unreadable is an error, never an all-clear. Everything
# happens in a temporary directory; this script touches neither its repository nor GitHub.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
stalls="$root/scripts/squad-stalls.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)
export TZ=UTC

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-stalls.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# A main checkout with the squad installed, and a linked worktree.
repo="$lab/repo"
git init -q "$repo" && mkdir -p "$repo/.agent-squad" || exit 2
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init || exit 2
git -C "$repo" worktree add -q --detach "$repo/.agent-squad/worktrees/dev" || exit 2
state="$repo/.agent-squad/watch.tsv"

# GitHub, as far as squad-stalls.sh is concerned: the open PRs, the open issues and each PR's
# reviews come from files in $lab/gh; GH_FAIL=<what> makes that call fail.
mkdir -p "$lab/bin" "$lab/gh"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
gh_dir="$(dirname "$0")/../gh"
case "$1 ${2:-}" in
  "repo view") [ "${GH_FAIL:-}" != repo ] || exit 1; echo o/r ;;
  "pr list") [ "${GH_FAIL:-}" != prs ] || exit 1; cat "$gh_dir/prs.json" ;;
  "issue list") [ "${GH_FAIL:-}" != issues ] || exit 1; cat "$gh_dir/issues.json" ;;
  api*)
    [ "${GH_FAIL:-}" != reviews ] || exit 1
    for arg; do case "$arg" in repos/o/r/pulls/*/reviews) n="${arg#repos/o/r/pulls/}"; n="${n%/reviews}" ;; esac; done
    # --paginate --slurp: one array per page, all in one array.
    if [ -f "$gh_dir/reviews-$n.json" ]; then echo "[[$(cat "$gh_dir/reviews-$n.json")]]"; else echo '[[]]'; fi ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH"

# The clock: noon. `at <minutes ago>` prints the time that many minutes before it, as GitHub
# writes times.
noon="$(jq -n '"2026-10-03T12:00:00Z" | fromdateiso8601')"
at() { jq -nr --argjson t "$((noon - $1 * 60))" '$t | todateiso8601'; }
head1=1111111111111111111111111111111111111111 head2=2222222222222222222222222222222222222222
# `pr <number> <author> <head> <minutes quiet> [draft]` prints a PR; `issue <number> <owner label>
# <status label> <minutes quiet>` an issue; `review <commit> <verdict> [association]` a review.
pr() {
  jq -nc --argjson n "$1" --arg a "$2" --arg h "$3" --arg u "$(at "$4")" --argjson d "${5:-false}" \
    '{number: $n, title: "PR \($n)", isDraft: $d, headRefOid: $h, updatedAt: $u,
      url: "https://github.com/o/r/pull/\($n)",
      body: ({QA: "**👩🏼‍🔬[QA]:**", DEV: "**👨🏼‍💻[DEV]:**", CTO: "**👷🏼‍♂️[CTO]:**", none: "Closes #1."}[$a] + " Closes #1.")}'
}
issue() {
  jq -nc --argjson n "$1" --arg o "$2" --arg s "$3" --arg u "$(at "$4")" \
    '{number: $n, title: "Issue \($n)", updatedAt: $u, url: "https://github.com/o/r/issues/\($n)",
      labels: ([$o, $s] | map(select(. != "")) | map({name: .}))}'
}
review() {
  jq -nc --arg c "$1" --arg v "$2" --arg a "${3:-OWNER}" \
    '{commit_id: $c, body: "**👩🏼‍🔬[QA]:** a review\n\nQA-VERDICT: \($v)", author_association: $a}'
}
# `github <prs as JSON> <issues as JSON>` sets what GitHub answers; reviews are set by hand.
github() { echo "$1" > "$lab/gh/prs.json"; echo "$2" > "$lab/gh/issues.json"; rm -f "$lab/gh"/reviews-*.json; }

# `run <minutes after noon> <option...>` runs the detector from the worktree, leaving its output in
# $out, its stderr in $err and its exit code in $code.
run() {
  local minutes="$1"
  shift
  out="$(cd "$repo/.agent-squad/worktrees/dev" && SQUAD_NOW="$((noon + minutes * 60))" "$stalls" "$@" 2>"$lab/err")"
  code=$?
  err="$(cat "$lab/err")"
}
# `finds <case> <expected output>` passes when the last run exited 0 and printed exactly that.
finds() {
  if [ "$code" -eq 0 ] && [ "$out" = "$2" ]; then pass "$1"; else fail "$1: exit $code, printed '$out', said '$err'"; fi
}
tsv() { local IFS=$'\t'; echo "$*"; }
everyone_idle=(--session CTO=idle --session DEV=idle --session QA=idle)

# 1. Who owns the next step of a PR. DEV authors #1 to #5 and the draft #6; QA authors #7.
github "[$(pr 1 DEV "$head1" 40),$(pr 2 DEV "$head1" 40),$(pr 3 DEV "$head1" 40),$(pr 4 DEV "$head1" 40),$(pr 5 DEV "$head1" 40),$(pr 6 DEV "$head1" 40 true),$(pr 7 QA "$head1" 40)]" '[]'
review "$head1" CHANGES-REQUESTED > "$lab/gh/reviews-2.json"
review "$head1" APPROVED > "$lab/gh/reviews-3.json"
review "$head2" APPROVED > "$lab/gh/reviews-4.json"
echo "$(review "$head1" CHANGES-REQUESTED),$(review "$head1" APPROVED CONTRIBUTOR)" > "$lab/gh/reviews-5.json"
since="2026-10-03 11:20"
run 0 "${everyone_idle[@]}"
finds "each PR's next step goes to whoever owns it, and each owner is pinged" "$(
  tsv ping QA "PR #1" https://github.com/o/r/pull/1 "review its head 1111111" "$since" ""
  tsv ping DEV "PR #2" https://github.com/o/r/pull/2 "answer the changes requested on 1111111" "$since" ""
  tsv ping DEV "PR #3" https://github.com/o/r/pull/3 "merge it: QA approved its head 1111111" "$since" ""
  tsv ping QA "PR #4" https://github.com/o/r/pull/4 "review its head 1111111" "$since" ""
  tsv ping DEV "PR #5" https://github.com/o/r/pull/5 "answer the changes requested on 1111111" "$since" ""
  tsv ping DEV "PR #6" https://github.com/o/r/pull/6 "finish the draft" "$since" ""
  tsv ping DEV "PR #7" https://github.com/o/r/pull/7 "review its head 1111111" "$since" "")"
#    A verdict on an earlier commit (#4) asks for a new review, a stranger's approval (#5) counts
#    for nothing, and a PR QA authors (#7) is DEV's to review.

# 2. Who owns the next step of an issue in progress; other issues are not watched.
rm -f "$state"
github '[]' "[$(issue 10 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 45),$(issue 11 '👩🏼‍🔬 owner:qa' '🚧 status:in-progress' 45),$(issue 12 '' '🚧 status:in-progress' 45),$(issue 13 '👨🏼‍💻 owner:dev' '👀 status:in-review' 45),$(issue 14 '👨🏼‍💻 owner:dev' '' 45)]"
run 0 "${everyone_idle[@]}"
finds "an issue in progress is its owner's to carry on, one with no owner the CTO's, and other issues are not watched" "$(
  tsv ping DEV "#10" https://github.com/o/r/issues/10 "carry on with it" "2026-10-03 11:15" ""
  tsv ping QA "#11" https://github.com/o/r/issues/11 "carry on with it" "2026-10-03 11:15" ""
  tsv ping CTO "#12" https://github.com/o/r/issues/12 "give it an owner" "2026-10-03 11:15" "")"

# 3. Thirty minutes of quiet make a stall, not fewer; a busy owner is working.
rm -f "$state"
github "[$(pr 1 DEV "$head1" 29),$(pr 2 DEV "$head1" 31)]" '[]'
run 0 "${everyone_idle[@]}"
finds "an item quiet for 29 minutes is no stall, one quiet for 31 is" \
  "$(tsv ping QA "PR #2" https://github.com/o/r/pull/2 "review its head 1111111" "2026-10-03 11:29" "")"
rm -f "$state"
run 0 --session CTO=idle --session DEV=idle --session QA=busy
finds "a busy owner is not pinged" ""

# 4. A session that waits on the CEO, or is not open, is reported to the CEO at once and never
#    pinged; then not again.
rm -f "$state"
github "[$(pr 1 DEV "$head1" 40),$(pr 2 QA "$head1" 40)]" '[]'
run 0 --session CTO=idle --session QA=waiting
finds "an owner waiting on the CEO, and one with no session, are the CEO's to know" "$(
  tsv ceo QA "PR #1" https://github.com/o/r/pull/1 "review its head 1111111" "2026-10-03 11:20" "its session waits on the CEO in its own terminal"
  tsv ceo DEV "PR #2" https://github.com/o/r/pull/2 "review its head 1111111" "2026-10-03 11:20" "it has no session open")"
run 30 --session CTO=idle --session QA=waiting
finds "and only once" ""

# 5. A ping, then an hour of the same stall, then the CEO, once.
rm -f "$state"
github "[$(pr 1 DEV "$head1" 40)]" '[]'
ping_line="$(tsv ping QA "PR #1" https://github.com/o/r/pull/1 "review its head 1111111" "2026-10-03 11:20" "")"
run 0 "${everyone_idle[@]}"
finds "a new stall pings its owner" "$ping_line"
run 30 "${everyone_idle[@]}"
finds "half an hour later, the same stall is not pinged again" ""
run 60 "${everyone_idle[@]}"
finds "an hour after the ping, the CEO is told" \
  "$(tsv ceo QA "PR #1" https://github.com/o/r/pull/1 "review its head 1111111" "2026-10-03 11:20" "pinged at 2026-10-03 12:00, and nothing since")"
run 90 "${everyone_idle[@]}"
finds "and only once" ""

# 6. Activity starts afresh: the item moves on, and a later quiet is a new stall, pinged anew.
github "[$(pr 1 DEV "$head1" -50)]" '[]'
run 70 "${everyone_idle[@]}"
finds "an item with activity 20 minutes ago is no stall" ""
if [ -z "$(cut -f1 "$state" 2>/dev/null)" ]; then
  pass "and what was kept of its earlier stall is gone"
else
  fail "the state still holds: $(cat "$state")"
fi
run 130 "${everyone_idle[@]}"
finds "and when it goes quiet again, its owner is pinged anew" \
  "$(tsv ping QA "PR #1" https://github.com/o/r/pull/1 "review its head 1111111" "2026-10-03 12:50" "")"

#    Activity between two passes, and quiet again by the second: a new stall, pinged anew, not the
#    old one carried on to the CEO.
rm -f "$state"
github "[$(pr 1 DEV "$head1" 40)]" '[]'
run 0 "${everyone_idle[@]}"
github "[$(pr 1 DEV "$head1" -5)]" '[]'
run 40 "${everyone_idle[@]}"
finds "activity between two passes makes the next quiet a new stall" \
  "$(tsv ping QA "PR #1" https://github.com/o/r/pull/1 "review its head 1111111" "2026-10-03 12:05" "")"
run 60 "${everyone_idle[@]}"
finds "and the CEO is not told an hour after the first ping" ""

# 6b. A PR whose description carries no signature is the CTO's, to find its author.
rm -f "$state"
github "[$(pr 1 none "$head1" 40)]" '[]'
run 0 "${everyone_idle[@]}"
finds "an unsigned PR is the CTO's, to find its author" \
  "$(tsv ping CTO "PR #1" https://github.com/o/r/pull/1 "find its author: its description is not signed" "2026-10-03 11:20" "")"

# 6c. A declared wait is not a stall (#174, the CTO's decision on PR #193): an issue or PR labelled
#     needs-ceo or status:blocked, and a PR whose closing issue is, named by GitHub or by the PR's
#     own "Closes #N", are left out. #24, waiting on nobody, is the control.
rm -f "$state"
labelled() { jq -c --arg l "$1" '.labels = [{name: $l}]'; }
closing() { jq -c --argjson n "$1" '.closingIssuesReferences = [{number: $n}]'; }
needs_ceo='👨🏻‍💼 needs-ceo' blocked='⛔ status:blocked'
github "[$(pr 20 DEV "$head1" 40 | labelled "$needs_ceo"),$(pr 21 DEV "$head1" 40 | labelled "$blocked"),$(pr 22 DEV "$head1" 40 | closing 30),$(pr 23 DEV "$head1" 40 | jq -c '.body += "\nCloses #31."'),$(pr 24 DEV "$head1" 40)]" \
  "[$(issue 25 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 45 | jq -c --arg l "$needs_ceo" '.labels += [{name: $l}]'),$(issue 26 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 45 | jq -c --arg l "$blocked" '.labels += [{name: $l}]'),$(issue 30 '' '' 45 | labelled "$needs_ceo"),$(issue 31 '' '' 45 | labelled "$blocked")]"
run 0 "${everyone_idle[@]}"
finds "needs-ceo and status:blocked, on an issue, on a PR or on a PR's closing issue, leave the item out" \
  "$(tsv ping QA "PR #24" https://github.com/o/r/pull/24 "review its head 1111111" "2026-10-03 11:20" "")"

# 6d. Records that cannot be kept fail the run, since every pass would then report the same
#     findings again: a directory where watch.tsv goes, or a .agent-squad/ that cannot be written.
rm -f "$state"
github "[$(pr 1 DEV "$head1" 40)]" '[]'
# The script names the physical path: on macOS, TMPDIR's /var is a link to /private/var.
state_p="$(cd "$repo/.agent-squad" && pwd -P)/watch.tsv"
mkdir "$state"
run 0 "${everyone_idle[@]}"
if [ "$code" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "squad-stalls: cannot keep its records in $state_p"* ]]; then
  pass "a directory in watch.tsv's place fails the run, exit 1, before anything is reported"
else
  fail "a directory in watch.tsv's place: exit $code, printed '$out', said '$err'"
fi
rmdir "$state"
chmod 500 "$repo/.agent-squad"
run 0 "${everyone_idle[@]}"
chmod 700 "$repo/.agent-squad"
if [ "$code" -eq 1 ] && [[ "$err" == "squad-stalls: cannot keep its records in $state_p"* ]] && [ ! -e "$state" ]; then
  pass "an .agent-squad/ that cannot be written fails the run, exit 1"
else
  fail "an unwritable .agent-squad/: exit $code, printed '$out', said '$err'"
fi

# 7. Nothing to find prints nothing; GitHub unreadable is an error, never an all-clear.
rm -f "$state"
github '[]' '[]'
run 0 "${everyone_idle[@]}"
finds "with nothing open, nothing is printed" ""
github "[$(pr 1 DEV "$head1" 40)]" "[$(issue 10 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 45)]"
for what in repo prs issues reviews; do
  rm -f "$state"
  GH_FAIL="$what" run 0 "${everyone_idle[@]}"
  if [ "$code" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "squad-stalls: cannot read "*"; nothing was checked" ]] && [ ! -e "$state" ]; then
    pass "GitHub failing on $what is an error, exit 1, saying nothing was checked"
  else
    fail "GitHub failing on $what: exit $code, printed '$out', said '$err'"
  fi
done

# 8. Bad usage, and a place that is not a squad's checkout, exit 2.
for args in "--session" "--session QA=asleep" "--session BOSS=idle" "--bogus"; do
  # shellcheck disable=SC2086 # the options are split on purpose
  run 0 $args
  if [ "$code" -eq 2 ]; then pass "'$args' is bad usage, exit 2"; else fail "'$args': exit $code, said '$err'"; fi
done
mkdir -p "$lab/plain" && git init -q "$lab/plain"
out="$(cd "$lab/plain" && "$stalls" 2>&1)"
code=$?
if [ "$code" -eq 2 ] && [[ "$out" == *"has no .agent-squad/"* ]]; then
  pass "a checkout without the squad installed is refused, exit 2"
else
  fail "a checkout without the squad: exit $code, said '$out'"
fi

# 9. --current prints each role's current item for the squad board (agent-squad #205): the item
#    whose next step it owns with the latest activity, a declared wait included; failing one, the
#    PR it authored that waits on someone else. QA owns the reviews of #1, #4 (needs-ceo, the
#    latest) and #5; DEV owns the merge of #2 and the issue #10, the later; the CTO owns nothing,
#    and authored #5.
rm -f "$state"
github "[$(pr 1 DEV "$head1" 40),$(pr 2 DEV "$head1" 50),$(pr 4 DEV "$head1" 5 | labelled "$needs_ceo"),$(pr 5 CTO "$head1" 60)]" \
  "[$(issue 10 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 20)]"
review "$head1" APPROVED > "$lab/gh/reviews-2.json"
run 0 --current
finds "--current prints each role's item: its own next step with the latest activity, else its PR that waits" "$(
  tsv CTO "PR #5" https://github.com/o/r/pull/5 "wait for QA to review its head 1111111"
  tsv DEV "#10" https://github.com/o/r/issues/10 "carry on with it"
  tsv QA "PR #4" https://github.com/o/r/pull/4 "review its head 1111111")"
if [ ! -e "$state" ]; then pass "--current keeps no records"; else fail "--current wrote $(cat "$state")"; fi
github "[]" "[$(issue 10 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 20)]"
mkdir "$state"
run 0 --current
rmdir "$state"
finds "a role with no item has no line, and a directory where the records go does not matter" \
  "$(tsv DEV "#10" https://github.com/o/r/issues/10 "carry on with it")"
GH_FAIL="prs" run 0 --current
if [ "$code" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "squad-stalls: cannot read the open pull requests; nothing was checked" ]]; then
  pass "--current with GitHub unreadable is an error, exit 1"
else
  fail "--current with GitHub unreadable: exit $code, printed '$out', said '$err'"
fi
run 0 --current --session DEV=idle
if [ "$code" -eq 2 ]; then pass "--current with --session is bad usage, exit 2"; else fail "--current with --session: exit $code, said '$err'"; fi

exit "$status"
