#!/usr/bin/env bash
# Check that squad-outside.sh lists what came from outside the squad as agent-squad #281 says,
# against a gh that serves fixed lists at a fixed time: the open issues and PRs an outside account
# opened that wait for their triage, whatever their signature, and the comments outside accounts
# wrote or edited since the last triage, on conversations and on code, each with its account. The
# mark records the last listing's time, so that a comment written during a triage is listed next
# time. GitHub unreadable is an error, never an empty list. Everything happens in a temporary
# directory; this script touches neither its repository nor GitHub.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
outside="$root/scripts/squad-outside.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)
export TZ=UTC

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-outside.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# A main checkout with the squad installed, and a linked worktree to run from.
repo="$lab/repo"
git init -q "$repo" && mkdir -p "$repo/.agent-squad" || exit 2
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init || exit 2
git -C "$repo" worktree add -q --detach "$repo/.agent-squad/worktrees/dev" || exit 2
squad="$repo/.agent-squad"

# GitHub, as far as squad-outside.sh is concerned: the REST lists of open issues and PRs, of
# conversation comments and of comments on code come from files in $lab/gh, and each query is
# written down in $lab/queries.txt. GH_FAIL=<list> makes that call fail; <list>-partial prints a
# first page, then fails; <list>-garbage answers with something that is not JSON.
mkdir -p "$lab/bin" "$lab/gh"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
lab="$(dirname "$0")/.."
case "$1 ${2:-}" in
  "repo view") [ "${GH_FAIL:-}" != repo ] || exit 1; echo o/r; exit 0 ;;
esac
for arg; do
  case "$arg" in
    repos/o/r/issues\?state=open*) list=opened ;;
    repos/o/r/issues/comments*) list=conversation ;;
    repos/o/r/pulls/comments*) list=code ;;
    *) continue ;;
  esac
  echo "$list ${arg#*\?}" >> "$lab/queries.txt"
  case "${GH_FAIL:-}" in
    "$list") exit 1 ;;
    "$list-garbage") echo "not JSON"; exit 0 ;;
  esac
  echo "[$(cat "$lab/gh/$list.json" 2>/dev/null || echo '[]')]"
  [ "${GH_FAIL:-}" != "$list-partial" ] || exit 1
  exit 0
done
exit 1
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH"

# The clock: noon. `at <minutes after noon>` prints that time as GitHub writes times.
noon="$(jq -n '"2026-10-03T12:00:00Z" | fromdateiso8601')"
at() { jq -nr --argjson t "$((noon + $1 * 60))" '$t | todateiso8601'; }
# `item <number> <login> <association> <minutes> [pr] [label...]` prints an open issue or PR;
# `said <id> <on: "#n" or "PR #n"> <login> <association> <minutes updated> [code]` a comment, on a
# conversation or, with code, on a PR's code.
item() {
  local n="$1" login="$2" association="$3" minutes="$4" pr="${5:-}"
  shift 4; [ $# -gt 0 ] && shift
  jq -nc --argjson n "$n" --arg l "$login" --arg a "$association" --arg c "$(at "$minutes")" --arg pr "$pr" \
    '{number: $n, user: {login: $l}, author_association: $a, created_at: $c, labels: ($ARGS.positional | map({name: .})),
      html_url: "https://github.com/o/r/\(if $pr == "pr" then "pull" else "issues" end)/\($n)"}
     + (if $pr == "pr" then {pull_request: {}} else {} end)' --args "$@"
}
said() {
  jq -nc --argjson id "$1" --arg on "$2" --arg l "$3" --arg a "$4" --arg u "$(at "$5")" --arg code "${6:-}" '
    ($on | ltrimstr("PR ") | ltrimstr("#")) as $n | ($on | startswith("PR ")) as $pr
    | {id: $id, user: {login: $l}, author_association: $a, created_at: "2026-10-03T09:00:00Z", updated_at: $u}
      + if $code == "code" then {pull_request_url: "https://api.github.com/repos/o/r/pulls/\($n)",
                                 html_url: "https://github.com/o/r/pull/\($n)#discussion_r\($id)"}
        else {issue_url: "https://api.github.com/repos/o/r/issues/\($n)",
              html_url: "https://github.com/o/r/\(if $pr then "pull" else "issues" end)/\($n)#issuecomment-\($id)"} end'
}
# `github <opened> <conversation> <code>` sets what GitHub answers, each a JSON array.
github() { echo "$1" > "$lab/gh/opened.json"; echo "$2" > "$lab/gh/conversation.json"; echo "$3" > "$lab/gh/code.json"; }

# `run <minutes after noon> [--mark]` runs the script from the worktree, leaving its output in $out,
# its stderr in $err and its exit code in $code.
run() {
  local minutes="$1"
  shift
  rm -f "$lab/queries.txt"
  out="$(cd "$squad/worktrees/dev" && SQUAD_NOW="$((noon + minutes * 60))" "$outside" "$@" 2>"$lab/err")"
  code=$?
  err="$(cat "$lab/err")"
}
# `finds <case> <expected output>` passes when the last run exited 0 and printed exactly that.
finds() {
  if [ "$code" -eq 0 ] && [ "$out" = "$2" ]; then pass "$1"; else fail "$1: exit $code, printed '$out', said '$err'"; fi
}
tsv() { local IFS=$'\t'; echo "$*"; }
triage='📥 needs-triage'

# 1. The first listing. Items: #1 waits for triage, #2 too with no label at all (the workflow did
#    not run), PR #5 too though it is signed as DEV's; #3 was triaged, and #4 is the owner's. The
#    comments: outside ones on an issue (#3), on a PR's conversation (PR #5) and on a PR's code
#    (PR #6), each with its account; the owner's and a member's are not listed.
github "[$(item 1 stranger NONE -60 '' "$triage"),$(item 2 helper CONTRIBUTOR -50),$(item 3 stranger NONE -40 '' '👷🏼‍♂️ owner:cto' '🐛 bug'),$(item 4 gzurl OWNER -30),$(item 5 mimic NONE -20 pr "$triage")]" \
  "[$(said 11 '#3' stranger NONE -60),$(said 12 '#3' gzurl OWNER -50),$(said 13 'PR #5' helper CONTRIBUTOR -40)]" \
  "[$(said 14 'PR #6' newcomer FIRST_TIME_CONTRIBUTOR -30 code),$(said 15 'PR #6' teammate MEMBER -20 code)]"
run 0
finds "the first listing shows the items that wait for triage, then every outside comment, each with its account" "$(
  tsv item "#1" https://github.com/o/r/issues/1 stranger NONE "2026-10-03 11:00"
  tsv item "#2" https://github.com/o/r/issues/2 helper CONTRIBUTOR "2026-10-03 11:10"
  tsv item "PR #5" https://github.com/o/r/pull/5 mimic NONE "2026-10-03 11:40"
  tsv comment "#3" "https://github.com/o/r/issues/3#issuecomment-11" stranger NONE "2026-10-03 11:00"
  tsv comment "PR #5" "https://github.com/o/r/pull/5#issuecomment-13" helper CONTRIBUTOR "2026-10-03 11:20"
  tsv comment "PR #6" "https://github.com/o/r/pull/6#discussion_r14" newcomer FIRST_TIME_CONTRIBUTOR "2026-10-03 11:30")"
if ! grep -q since "$lab/queries.txt"; then pass "with no triage marked yet, every comment is asked for"; else fail "a first listing asked for: $(cat "$lab/queries.txt")"; fi

# 2. The mark records the listing's time, noon, not its own: a comment written during the triage
#    (12:03) and one edited after it (written at 9:00, edited at 12:20) are listed next time; one
#    from before the listing (11:59) is not. The items wait until they are triaged.
github "[$(item 1 stranger NONE -60 '' "$triage")]" \
  "[$(said 21 '#1' stranger NONE -1),$(said 22 '#1' stranger NONE 3),$(said 23 '#1' helper CONTRIBUTOR 20)]" '[]'
run 5 --mark
if [ "$code" -eq 0 ] && [ -z "$out" ] && [ "$(cat "$squad/triage.since")" = "2026-10-03T12:00:00Z" ]; then
  pass "--mark records the time of the last listing, not its own, and prints nothing"
else
  fail "--mark: exit $code, printed '$out', said '$err', kept '$(cat "$squad/triage.since" 2>/dev/null)'"
fi
run 30
finds "the next listing shows the comments written or edited since that time, and the items still untriaged" "$(
  tsv item "#1" https://github.com/o/r/issues/1 stranger NONE "2026-10-03 11:00"
  tsv comment "#1" "https://github.com/o/r/issues/1#issuecomment-22" stranger NONE "2026-10-03 12:03"
  tsv comment "#1" "https://github.com/o/r/issues/1#issuecomment-23" helper CONTRIBUTOR "2026-10-03 12:20")"
if [ "$(grep -c 'since=2026-10-03T12:00:00Z' "$lab/queries.txt")" -eq 2 ]; then
  pass "and asks GitHub for the comments since then, on conversations and on code"
else
  fail "the queries were: $(cat "$lab/queries.txt")"
fi

# 3. Nothing from outside prints nothing.
github "[$(item 4 gzurl OWNER -30)]" "[$(said 31 '#4' gzurl OWNER 10)]" '[]'
run 40
finds "with nothing from outside, nothing is printed" ""

# 4. GitHub unreadable is an error, never an empty list, and the listing's time is not kept.
github "[$(item 1 stranger NONE -60 '' "$triage")]" '[]' '[]'
for what in repo opened opened-partial opened-garbage conversation conversation-partial code code-garbage; do
  cp "$squad/triage.read" "$lab/read.before"
  GH_FAIL="$what" run 50
  if [ "$code" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "squad-outside: cannot read "*"; nothing was listed" ]] \
    && cmp -s "$lab/read.before" "$squad/triage.read"; then
    pass "GitHub failing on $what is an error, exit 1, with nothing listed and no time kept"
  else
    fail "GitHub failing on $what: exit $code, printed '$out', said '$err'"
  fi
done

# 5. Marks and times that do not hold.
rm -f "$squad/triage.read" "$squad/triage.since"
run 0 --mark
if [ "$code" -eq 1 ] && [[ "$err" == *"nothing has been listed yet"* ]] && [ ! -e "$squad/triage.since" ]; then
  pass "--mark before any listing is refused, exit 1, and marks nothing"
else
  fail "--mark before any listing: exit $code, said '$err'"
fi
echo "yesterday" > "$squad/triage.since"
run 0
if [ "$code" -eq 1 ] && [[ "$err" == *"does not hold a time"* ]]; then
  pass "a last triage's time that is not one is an error, exit 1"
else
  fail "a time that is not one: exit $code, said '$err'"
fi
rm -f "$squad/triage.since"
mkdir "$squad/triage.read"
run 0
rmdir "$squad/triage.read"
if [ "$code" -eq 1 ] && [ -z "$out" ] && [[ "$err" == *"cannot keep a time in "*"triage.read: it is not a file"* ]]; then
  pass "a listing whose time cannot be kept prints nothing, exit 1"
else
  fail "a listing whose time cannot be kept: exit $code, printed '$out', said '$err'"
fi

# 6. Bad usage, and a place that is not a squad's checkout, exit 2.
for args in "--mark --mark" "--bogus" "list"; do
  # shellcheck disable=SC2086 # the options are split on purpose
  run 0 $args
  if [ "$code" -eq 2 ]; then pass "'$args' is bad usage, exit 2"; else fail "'$args': exit $code, said '$err'"; fi
done
mkdir -p "$lab/plain" && git init -q "$lab/plain"
out="$(cd "$lab/plain" && "$outside" 2>&1)"
code=$?
if [ "$code" -eq 2 ] && [[ "$out" == *"has no .agent-squad/"* ]]; then
  pass "a checkout without the squad installed is refused, exit 2"
else
  fail "a checkout without the squad: exit $code, said '$out'"
fi

exit "$status"
