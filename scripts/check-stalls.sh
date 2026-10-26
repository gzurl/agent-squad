#!/usr/bin/env bash
# Check that squad-stalls.sh finds the squad's stalls as agent-squad #174 says, against a gh that
# serves fixed pull requests, issues and reviews, at a fixed time. Who owns the next step: the
# reviewer of a PR whose head has no verdict (DEV on one QA authors), the author of one whose
# verdict asks for changes or approves, the author of a draft, the owner of an issue in progress.
# Items whose wait is declared, labelled needs-ceo or status:blocked themselves or through a PR's
# closing issue, are not watched. A stall is an item quiet for 30 minutes whose owner's session is
# idle: the owner is pinged once,
# and the CEO told once if it is still there an hour later. A session that waits on the CEO, or is
# not open, is reported to the CEO at once; a busy one never. Activity starts a stall afresh. An
# issue or a PR opened from outside the squad, by the account's association and whatever its
# signature, is the CTO's to triage once it has waited 30 minutes, and nobody else's (#281). An
# approved PR with a review still requested on GitHub waits for that reviewer: nobody is pinged, and
# the CEO is told once it has been quiet for an hour, whatever the sessions (#306). An issue in
# progress whose owner has written no state on it since its label was set is its owner's, to write
# one that names its approach, 15 minutes after the label, whatever the activity since and even
# when that owner is busy (#521). A jq that ends its lines with CRLF, as on Windows, finds the same
# (#405). Nothing found prints nothing; GitHub unreadable is an error, never an all-clear. Everything
# happens in a temporary directory; this script touches neither its repository nor GitHub.
# shellcheck disable=SC2016 # jq programs use jq variables
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

# GitHub, as far as squad-stalls.sh is concerned: the open PRs, the open issues, who opened each
# (the REST list of open issues and PRs), each PR's reviews and each issue's timeline come from
# files in $lab/gh;
# GH_FAIL=<what> makes that call fail, and GH_FAIL=prs-hang makes the list of PRs never answer, its
# PID in $lab/gh/hung.pid.
mkdir -p "$lab/bin" "$lab/gh"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
gh_dir="$(dirname "$0")/../gh"
case "$1 ${2:-}" in
  "repo view") [ "${GH_FAIL:-}" != repo ] || exit 1; echo o/r ;;
  "pr list")
    [ "${GH_FAIL:-}" != prs ] || exit 1
    if [ "${GH_FAIL:-}" = prs-hang ]; then echo "$$" > "$gh_dir/hung.pid"; exec sleep 60; fi
    cat "$gh_dir/prs.json" ;;
  "issue list") [ "${GH_FAIL:-}" != issues ] || exit 1; cat "$gh_dir/issues.json" ;;
  api*)
    for arg; do
      case "$arg" in
        repos/o/r/issues\?state=open*)
          # opened fails at once; opened-partial prints its first page, then fails, as a
          # pagination cut short does; opened-garbage answers with something that is not JSON.
          case "${GH_FAIL:-}" in
            opened) exit 1 ;;
            opened-garbage) echo "not JSON"; exit 0 ;;
          esac
          echo "[$(cat "$gh_dir/opened.json" 2>/dev/null || echo '[]')]"
          [ "${GH_FAIL:-}" != opened-partial ] || exit 1
          exit 0 ;;
        repos/o/r/issues/*/timeline*)
          # timeline fails at once; timeline-garbage answers with something that is not JSON.
          case "${GH_FAIL:-}" in
            timeline) exit 1 ;;
            timeline-garbage) echo "not JSON"; exit 0 ;;
          esac
          n="${arg#repos/o/r/issues/}"
          echo "[$(cat "$gh_dir/timeline-${n%%/*}.json" 2>/dev/null || echo '[]')]"
          exit 0 ;;
      esac
    done
    [ "${GH_FAIL:-}" != reviews ] || exit 1
    for arg; do case "$arg" in repos/o/r/pulls/*/reviews) n="${arg#repos/o/r/pulls/}"; n="${n%/reviews}" ;; esac; done
    # --paginate --slurp: one array per page, all in one array.
    if [ -f "$gh_dir/reviews-$n.json" ]; then echo "[[$(cat "$gh_dir/reviews-$n.json")]]"; else echo '[[]]'; fi ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH"
# jq as on Windows (agent-squad #405), in the runs that `crlf <command...>` makes: every line it
# writes ends with CRLF.
mkdir -p "$lab/crlf"
printf '#!/usr/bin/env bash\n[ -n "${STUB_CRLF:-}" ] || exec %q "$@"\n%q "$@" | awk %q\nexit "${PIPESTATUS[0]}"\n' \
  "$(command -v jq)" "$(command -v jq)" '{ printf "%s\r\n", $0 }' > "$lab/crlf/jq"
chmod +x "$lab/crlf/jq"
crlf() { STUB_CRLF=1 PATH="$lab/crlf:$PATH" "$@"; }

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
# `github <prs as JSON> <issues as JSON> [<opened as JSON>]` sets what GitHub answers, the last the
# REST list of who opened what, outside items alone unless given; reviews and timelines are set by
# hand.
github() {
  echo "$1" > "$lab/gh/prs.json"; echo "$2" > "$lab/gh/issues.json"; echo "${3:-[]}" > "$lab/gh/opened.json"
  rm -f "$lab/gh"/reviews-*.json "$lab/gh"/timeline-*.json
}
# `timeline <number> <event as JSON>...` sets an issue's timeline: `labeled <minutes ago> [label]`
# prints a label set, status:in-progress unless given, and `commented <body> <minutes ago> [<minutes
# ago it was last edited> [association]]` a comment.
timeline() { local n="$1" IFS=,; shift; echo "[$*]" > "$lab/gh/timeline-$n.json"; }
labeled() { jq -nc --arg c "$(at "$1")" --arg l "${2:-🚧 status:in-progress}" '{event: "labeled", label: {name: $l}, created_at: $c}'; }
commented() {
  jq -nc --arg b "$1" --arg c "$(at "$2")" --arg u "$(at "${3:-$2}")" --arg a "${4:-OWNER}" \
    '{event: "commented", body: $b, created_at: $c, updated_at: $u, author_association: $a}'
}
# `opened <number> <login> <association> <minutes ago> [pr] [label...]` prints an item of the REST
# list: who opened it, when, and its labels.
opened() {
  local n="$1" login="$2" association="$3" ago="$4" pr="${5:-}"
  shift 4; [ $# -gt 0 ] && shift
  jq -nc --argjson n "$n" --arg l "$login" --arg a "$association" --arg c "$(at "$ago")" --arg pr "$pr" \
    '{number: $n, user: {login: $l}, author_association: $a, created_at: $c, labels: ($ARGS.positional | map({name: .})),
      html_url: "https://github.com/o/r/\(if $pr == "pr" then "pull" else "issues" end)/\($n)"}
     + (if $pr == "pr" then {pull_request: {}} else {} end)' --args "$@"
}

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
#    With a jq that ends its lines with CRLF, as on Windows, the same pings, and the state they
#    leave is read back: a minute later, nobody is pinged again (agent-squad #405).
pings="$out"
rm -f "$state"
crlf run 0 "${everyone_idle[@]}"
finds "with a jq that ends its lines with CRLF, the same pings" "$pings"
crlf run 1 "${everyone_idle[@]}"
finds "and a minute later, from the state they left, nobody is pinged again" ""

# 2. Who owns the next step of an issue in progress; other issues are not watched.
rm -f "$state"
github '[]' "[$(issue 10 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 45),$(issue 11 '👩🏼‍🔬 owner:qa' '🚧 status:in-progress' 45),$(issue 12 '' '🚧 status:in-progress' 45),$(issue 13 '👨🏼‍💻 owner:dev' '👀 status:in-review' 45),$(issue 14 '👨🏼‍💻 owner:dev' '' 45)]"
timeline 12 "$(labeled 45)"
run 0 "${everyone_idle[@]}"
finds "an issue in progress is its owner's to carry on, one with no owner the CTO's, and other issues are not watched" "$(
  tsv ping DEV "#10" https://github.com/o/r/issues/10 "carry on with it" "2026-10-03 11:15" ""
  tsv ping QA "#11" https://github.com/o/r/issues/11 "carry on with it" "2026-10-03 11:15" ""
  tsv ping CTO "#12" https://github.com/o/r/issues/12 "give it an owner" "2026-10-03 11:15" "")"

# 2b. A state that names the approach (#521): an issue in progress whose owner has written no state
#     on it since its label was set is its owner's, to write one, 15 minutes after the label,
#     though it saw activity 5 minutes ago and its owner is busy. A state is a comment by an inside
#     account whose first line opens with the owner's signature, bold or not, a status emoji and
#     `State:`; one edited in place counts from its edit. DEV owns all of them.
rm -f "$state"
dev_state='**👨🏼‍💻[DEV]:** ⏳ State: started. Approach: the cache.'
issues=""
for n in 60 61 62 63 64 65 66 67 68 69; do issues+="${issues:+,}$(issue "$n" '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 5)"; done
github '[]' "[$issues]"
timeline 60 "$(labeled 20)"
timeline 61 "$(labeled 20)" "$(commented "$dev_state" 18)"
timeline 62 "$(labeled 10)"
timeline 63 "$(commented "$dev_state" 40)" "$(labeled 20)"
timeline 64 "$(commented "$dev_state" 40 10)" "$(labeled 20)"
timeline 65 "$(labeled 20)" "$(commented '**👩🏼‍🔬[QA]:** ⏳ State: testing it.' 18)"
timeline 66 "$(labeled 20)" "$(commented '**👨🏼‍💻[DEV]:** ⏳ Taking it. State: soon.' 18)"
timeline 67 "$(labeled 20)" "$(commented "$dev_state" 18 18 NONE)"
timeline 68 "$(labeled 60)" "$(commented "$dev_state" 50)" "$(labeled 20 '👀 status:in-review')" "$(labeled 20)"
timeline 69 "$(labeled 20)" "$(commented '👨🏼‍💻[DEV]: ⚠️ State: stuck on the cache.' 18)"
approach="write a state on it that names its approach: none from its owner since it went in progress"
stateless() { tsv "${1:-ping}" DEV "#$2" "https://github.com/o/r/issues/$2" "$approach" "${3:-2026-10-03 11:40}" "${4:-}"; }
run 0 --session CTO=idle --session DEV=busy --session QA=idle
finds "an issue in progress with no state from its owner 15 minutes after its label is its owner's, busy or not" "$(
  stateless ping 60; stateless ping 63; stateless ping 65; stateless ping 66; stateless ping 67; stateless ping 68)"
#    #61 has its state, #62 went in progress 10 minutes ago, #64's state was edited after the label,
#    and #69's is signed without bold; #63's state predates the label, #65's is QA's, #66 opens with
#    no `State:`, #67's comes from outside, and #68 went in progress again after its state.
run 5 --session CTO=idle --session DEV=busy --session QA=idle
finds "five minutes later, #62 reaches its 15 minutes and is pinged, and the others are not pinged again" \
  "$(stateless ping 62 "2026-10-03 11:50")"
#    With a jq that ends its lines with CRLF, as on Windows, the same.
rm -f "$state"
crlf run 0 --session CTO=idle --session DEV=busy --session QA=idle
finds "with a jq that ends its lines with CRLF, the same" "$(
  stateless ping 60; stateless ping 63; stateless ping 65; stateless ping 66; stateless ping 67; stateless ping 68)"

#    An idle owner is pinged as a busy one; one that waits on the CEO, or has no session open, is the
#    CEO's at once, and then not again.
github '[]' "[$(issue 60 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 5)]"
timeline 60 "$(labeled 20)"
rm -f "$state"
run 0 "${everyone_idle[@]}"
finds "an idle owner with no state is pinged" "$(stateless ping 60)"
rm -f "$state"
run 0 --session CTO=idle --session DEV=waiting
finds "an owner waiting on the CEO is the CEO's to know" "$(stateless ceo 60 "" "its session waits on the CEO in its own terminal")"
rm -f "$state"
run 0 --session CTO=idle
finds "and so is an owner with no session" "$(stateless ceo 60 "" "it has no session open")"
run 30 --session CTO=idle
finds "and only once" ""

#    An hour after the ping, with still no state, the CEO is told, once.
rm -f "$state"
run 0 --session DEV=busy
finds "a missing state pings its owner" "$(stateless ping 60)"
run 30 --session DEV=busy
finds "half an hour later, it is not pinged again" ""
run 60 --session DEV=busy
finds "an hour after the ping, with no state yet, the CEO is told" \
  "$(stateless ceo 60 "" "pinged at 2026-10-03 12:00, and still no state from its owner")"
run 90 --session DEV=busy
finds "and only once" ""

#    Once its owner writes a state, the issue is a stall like any other: nothing while it moves, and
#    its owner pinged to carry on once it has been quiet 30 minutes and its owner idle.
rm -f "$state"
run 0 --session DEV=busy
timeline 60 "$(labeled 20)" "$(commented "$dev_state" -2)"
run 5 --session DEV=busy
finds "a state written after the ping ends it" ""
if [ -z "$(cut -f1 "$state" 2>/dev/null)" ]; then
  pass "and what was kept of it is gone"
else
  fail "the state still holds: $(cat "$state")"
fi
github '[]' "[$(issue 60 '👨🏼‍💻 owner:dev' '🚧 status:in-progress' 40)]"
timeline 60 "$(labeled 60)" "$(commented "$dev_state" 50)"
run 0 --session DEV=busy
finds "an issue with its state, quiet for 40 minutes, is not pinged while its owner is busy" ""
run 0 "${everyone_idle[@]}"
finds "and its owner is pinged to carry on once idle" \
  "$(tsv ping DEV "#60" https://github.com/o/r/issues/60 "carry on with it" "2026-10-03 11:20" "")"

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
timeline 25 "$(labeled 45)"
timeline 26 "$(labeled 45)"
run 0 "${everyone_idle[@]}"
finds "needs-ceo and status:blocked, on an issue, on a PR or on a PR's closing issue, leave the item out" \
  "$(tsv ping QA "PR #24" https://github.com/o/r/pull/24 "review its head 1111111" "2026-10-03 11:20" "")"

# 6e. An issue or a PR opened from outside the squad is the CTO's to triage once it has waited 30
#     minutes, whatever its labels or its signature say, while it carries needs-triage (#40) or no
#     owner label (#41, as when the triage workflow failed), and whether the author is new to the
#     repository or has contributed before (CONTRIBUTOR). A triaged one (#42), a young one (#43) and
#     an inside one with no labels (#44) are not. PR #45, from outside, is signed as DEV's: no
#     signature makes it DEV's or QA's, so only its triage is asked for.
rm -f "$state"
triage='📥 needs-triage'
github "[$(pr 45 DEV "$head1" 40)]" "[$(issue 40 '' '' 40),$(issue 41 '' '' 40),$(issue 42 '👷🏼‍♂️ owner:cto' '' 40),$(issue 43 '' '' 20),$(issue 44 '' '' 40)]" \
  "[$(opened 40 stranger NONE 40 '' "$triage"),$(opened 41 helper CONTRIBUTOR 40),$(opened 42 stranger NONE 40 '' '👷🏼‍♂️ owner:cto' '🐛 bug'),$(opened 43 stranger FIRST_TIME_CONTRIBUTOR 20 '' "$triage"),$(opened 44 gzurl OWNER 40),$(opened 45 mimic NONE 40 pr "$triage")]"
run 0 "${everyone_idle[@]}"
finds "an untriaged item from outside is the CTO's to triage after 30 minutes, and its signature makes it nobody else's" "$(
  tsv ping CTO "#40" https://github.com/o/r/issues/40 "triage it: stranger opened it from outside the squad (NONE)" "2026-10-03 11:20" ""
  tsv ping CTO "#41" https://github.com/o/r/issues/41 "triage it: helper opened it from outside the squad (CONTRIBUTOR)" "2026-10-03 11:20" ""
  tsv ping CTO "PR #45" https://github.com/o/r/pull/45 "triage it: mimic opened it from outside the squad (NONE)" "2026-10-03 11:20" "")"
run 5 "${everyone_idle[@]}"
finds "and it is pinged once" ""
rm -f "$state"
github '[]' "[$(issue 40 '' '' 40)]" "[$(opened 40 stranger NONE 40 '' "$triage" "$needs_ceo")]"
run 0 "${everyone_idle[@]}"
finds "an outside item whose wait is declared, needs-ceo, is not watched" ""

# 6f. A project whose open PRs, reviews and issues hold megabytes of text, past what macOS allows a
#     command's arguments in all and Linux one argument: every list reaches jq through a file, and
#     the stalls are found as with short texts.
rm -f "$state"
head -c 1500000 /dev/zero | tr '\0' x > "$lab/long.txt"
long() { jq -c --rawfile long "$lab/long.txt" "$1"; }
github "[$(pr 1 DEV "$head1" 40 | long '.body += "\n" + $long')]" '[]' \
  "[$(opened 50 stranger NONE 40 | long '.body = $long')]"
review "$head1" APPROVED | long '.body = $long + "\n\nQA-VERDICT: APPROVED"' > "$lab/gh/reviews-1.json"
run 0 "${everyone_idle[@]}"
finds "megabytes of text in PRs, reviews and issues are read through files, and the stalls found as ever" "$(
  tsv ping DEV "PR #1" https://github.com/o/r/pull/1 "merge it: QA approved its head 1111111" "2026-10-03 11:20" ""
  tsv ping CTO "#50" https://github.com/o/r/issues/50 "triage it: stranger opened it from outside the squad (NONE)" "2026-10-03 11:20" "")"

# 6g. A review requested on GitHub and still pending (agent-squad #306, from another project's PR,
#     where the CEO wanted a person's Approve after QA's verdict). An approved head then waits for
#     that reviewer, not for its author: nobody is pinged, and the CEO, the only one who can reach a
#     person, is told once the PR has been quiet for an hour, once, whatever the sessions. The
#     squad's own steps, a review of a new head and the answer to changes, are pinged as before.
# `requested <PR as JSON> <requests as JSON>` adds GitHub's pending review requests to a PR.
requested() { jq -c --argjson r "$2" '. + {reviewRequests: $r}' <<<"$1"; }
david='[{"__typename": "User", "login": "david"}]'
wait_line() {
  tsv ceo "$1" "PR #$2" "https://github.com/o/r/pull/$2" "wait for the review requested from $1 on GitHub, before the merge" "$3" \
    "a review is requested from $1 on GitHub, whom only the CEO can reach"
}
rm -f "$state"
github "[$(requested "$(pr 1 DEV "$head1" 40)" "$david")]" '[]'
review "$head1" APPROVED > "$lab/gh/reviews-1.json"
run 0 "${everyone_idle[@]}"
finds "an approved PR with a review still requested is not its author's to merge: after 40 minutes, no ping" ""
run 20 "${everyone_idle[@]}"
finds "an hour quiet, the CEO is told that it waits for the requested reviewer" "$(wait_line david 1 "2026-10-03 11:20")"
run 50 "${everyone_idle[@]}"
finds "and only once" ""
rm -f "$state"
run 20
finds "with no session open, the same line, and no ping" "$(wait_line david 1 "2026-10-03 11:20")"
rm -f "$state"
run 20 --session CTO=busy --session DEV=busy --session QA=busy
finds "and with every session busy, the same line too" "$(wait_line david 1 "2026-10-03 11:20")"
rm -f "$state"
github "[$(requested "$(pr 1 DEV "$head1" 70)" '[{"__typename": "Team", "slug": "reviewers", "name": "Reviewers"}]')]" '[]'
review "$head1" APPROVED > "$lab/gh/reviews-1.json"
run 0 "${everyone_idle[@]}"
finds "a team requested is named by its slug" "$(wait_line reviewers 1 "2026-10-03 10:50")"
#    The reviewer reviews: GitHub drops the request, and the approved head is the author's to merge.
rm -f "$state"
github "[$(requested "$(pr 1 DEV "$head1" 40)" '[]')]" '[]'
review "$head1" APPROVED > "$lab/gh/reviews-1.json"
run 0 "${everyone_idle[@]}"
finds "once the request is answered by a review, the author is pinged to merge" \
  "$(tsv ping DEV "PR #1" https://github.com/o/r/pull/1 "merge it: QA approved its head 1111111" "2026-10-03 11:20" "")"
#    A request does not hold the squad's own steps.
rm -f "$state"
github "[$(requested "$(pr 1 DEV "$head1" 40)" "$david"),$(requested "$(pr 2 DEV "$head1" 40)" "$david")]" '[]'
review "$head1" CHANGES-REQUESTED > "$lab/gh/reviews-2.json"
run 0 "${everyone_idle[@]}"
finds "with a review requested, a head with no verdict is still QA's to review, and changes asked still the author's" "$(
  tsv ping QA "PR #1" https://github.com/o/r/pull/1 "review its head 1111111" "2026-10-03 11:20" ""
  tsv ping DEV "PR #2" https://github.com/o/r/pull/2 "answer the changes requested on 1111111" "2026-10-03 11:20" "")"

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
for what in repo prs issues opened opened-partial opened-garbage reviews timeline timeline-garbage; do
  rm -f "$state"
  GH_FAIL="$what" run 0 "${everyone_idle[@]}"
  if [ "$code" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "squad-stalls: cannot read "*"; nothing was checked" ]] && [ ! -e "$state" ]; then
    pass "GitHub failing on $what is an error, exit 1, saying nothing was checked"
  else
    fail "GitHub failing on $what: exit $code, printed '$out', said '$err'"
  fi
done
#    A call that GitHub never answers is stopped after SQUAD_GH_TIMEOUT seconds of wall-clock time,
#    and fails the run as any other failure does, saying why (agent-squad #430).
rm -f "$state"
started=$SECONDS
GH_FAIL=prs-hang SQUAD_GH_TIMEOUT=1 run 0 "${everyone_idle[@]}"
took=$((SECONDS - started))
# Within 30 s: well under its stub's 60 s, and over what CI's kcov takes (agent-squad #447).
if [ "$code" -eq 1 ] && [ -z "$out" ] && [ ! -e "$state" ] && [ "$took" -le 30 ] \
  && [ "$err" = "squad-stalls: GitHub did not answer within 1 s"$'\n'"squad-stalls: cannot read the open pull requests; nothing was checked" ] \
  && ! kill -0 "$(cat "$lab/gh/hung.pid")" 2>/dev/null; then
  pass "a call that GitHub never answers is stopped after its bound: exit 1, saying so, and nothing left running"
else
  fail "a call that GitHub never answers: exit $code after $took s, 30 s at most, printed '$out', said '$err'"
fi
#    A SQUAD_GH_TIMEOUT that is not a whole number above 0 is 120 s: the run reads GitHub as without
#    one (QA's finding on PR #432).
rm -f "$state"
run 0 "${everyone_idle[@]}"
expected="$code|$out"
rm -f "$state"
SQUAD_GH_TIMEOUT=abc run 0 "${everyone_idle[@]}"
if [ "$expected" = "0|$out" ] && [ "$code" -eq 0 ]; then
  pass "a SQUAD_GH_TIMEOUT that is no number reads GitHub as without one"
else
  fail "a SQUAD_GH_TIMEOUT that is no number: exit $code, printed '$out', said '$err'"
fi

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

exit "$status"
