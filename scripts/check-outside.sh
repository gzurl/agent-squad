#!/usr/bin/env bash
# Check that squad-outside.sh lists what came from outside the squad as agent-squad #281 says,
# against a gh that serves fixed lists at a fixed time: the open issues and PRs an outside account
# opened that wait for their triage, whatever their signature, and the comments and reviews outside
# accounts wrote since the last triage, each with its account. A listing changes nothing and names
# its own time for --mark, so that a comment written during a triage is listed next time. Lists
# over a megabyte, as a real repository's comments are, go through, and so does a jq that ends its
# lines with CRLF, as on Windows (agent-squad #405). GitHub unreadable is an error, never an empty
# list. Everything happens in a temporary directory; this script touches neither its
# repository nor GitHub.
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
# conversation comments, of comments on code and of each PR's reviews come from files in $lab/gh,
# and each query is written down in $lab/queries.txt. GH_FAIL=<list> makes that call fail;
# <list>-partial prints a first page, then fails; <list>-garbage answers with something that is not
# JSON; <list>-hang never answers, its PID in $lab/hung.pid.
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
    repos/o/r/pulls/*/reviews*) n="${arg#repos/o/r/pulls/}"; n="${n%%/*}"; list=reviews ;;
    *) continue ;;
  esac
  echo "$list ${arg#*\?}" >> "$lab/queries.txt"
  case "${GH_FAIL:-}" in
    "$list") exit 1 ;;
    "$list-garbage") echo "not JSON"; exit 0 ;;
    "$list-hang") echo "$$" > "$lab/hung.pid"; exec sleep 60 ;;
  esac
  echo "[$(cat "$lab/gh/$list${n:+-$n}.json" 2>/dev/null || echo '[]')]"
  [ "${GH_FAIL:-}" != "$list-partial" ] || exit 1
  exit 0
done
exit 1
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH"
# jq as on Windows (agent-squad #405), in the runs that `crlf <command...>` makes: every line it
# writes ends with CRLF.
mkdir -p "$lab/crlf"
# shellcheck disable=SC2016 # the stub's lines are code, written as they are
printf '#!/usr/bin/env bash\n[ -n "${STUB_CRLF:-}" ] || exec %q "$@"\n%q "$@" | awk %q\nexit "${PIPESTATUS[0]}"\n' \
  "$(command -v jq)" "$(command -v jq)" '{ printf "%s\r\n", $0 }' > "$lab/crlf/jq"
chmod +x "$lab/crlf/jq"
crlf() { STUB_CRLF=1 PATH="$lab/crlf:$PATH" "$@"; }

# The clock: noon. `at <minutes after noon>` prints that time as GitHub writes times.
noon="$(jq -n '"2026-10-03T12:00:00Z" | fromdateiso8601')"
at() { jq -nr --argjson t "$((noon + $1 * 60))" '$t | todateiso8601'; }
# `item <number> <login> <association> <minutes> [pr] [label...]` prints an open issue or PR;
# `said <id> <on: "#n" or "PR #n"> <login> <association> <minutes updated> [code]` a comment, on a
# conversation or, with code, on a PR's code; `reviewed <id> <PR number> <login> <association>
# <minutes submitted>` a review. Each carries a body, as GitHub's do, which BODY sets.
item() {
  local n="$1" login="$2" association="$3" minutes="$4" pr="${5:-}"
  shift 4; [ $# -gt 0 ] && shift
  jq -nc --argjson n "$n" --arg l "$login" --arg a "$association" --arg c "$(at "$minutes")" --arg pr "$pr" \
    '{number: $n, user: {login: $l}, author_association: $a, created_at: $c, labels: ($ARGS.positional | map({name: .})),
      body: env.BODY,
      html_url: "https://github.com/o/r/\(if $pr == "pr" then "pull" else "issues" end)/\($n)"}
     + (if $pr == "pr" then {pull_request: {}} else {} end)' --args "$@"
}
said() {
  jq -nc --argjson id "$1" --arg on "$2" --arg l "$3" --arg a "$4" --arg u "$(at "$5")" --arg code "${6:-}" '
    ($on | ltrimstr("PR ") | ltrimstr("#")) as $n | ($on | startswith("PR ")) as $pr
    | {id: $id, user: {login: $l}, author_association: $a, created_at: "2026-10-03T09:00:00Z", updated_at: $u, body: env.BODY}
      + if $code == "code" then {pull_request_url: "https://api.github.com/repos/o/r/pulls/\($n)",
                                 html_url: "https://github.com/o/r/pull/\($n)#discussion_r\($id)"}
        else {issue_url: "https://api.github.com/repos/o/r/issues/\($n)",
              html_url: "https://github.com/o/r/\(if $pr then "pull" else "issues" end)/\($n)#issuecomment-\($id)"} end'
}
reviewed() {
  jq -nc --argjson id "$1" --argjson n "$2" --arg l "$3" --arg a "$4" --arg s "$(at "$5")" \
    '{id: $id, user: {login: $l}, author_association: $a, submitted_at: $s, body: env.BODY,
      html_url: "https://github.com/o/r/pull/\($n)#pullrequestreview-\($id)"}'
}
export BODY="A text, which the list never shows."
# `github <opened> <conversation> <code>` sets what GitHub answers, each a JSON array; each PR's
# reviews are set by hand, in reviews-<n>.json.
github() {
  echo "$1" > "$lab/gh/opened.json"; echo "$2" > "$lab/gh/conversation.json"; echo "$3" > "$lab/gh/code.json"
  rm -f "$lab/gh"/reviews-*.json
}

# `run <minutes after noon> [--mark <time>]` runs the script from the worktree, leaving its output
# in $out, its stderr in $err and its exit code in $code.
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
# `marks <case> <time>` passes when the last run's stderr ends with the --mark command for that time.
marks() {
  if [ "$(tail -n 1 <<<"$err")" = "squad-outside: once this is triaged, record it with: squad-outside.sh --mark $2" ]; then
    pass "$1"
  else
    fail "$1: said '$err'"
  fi
}

# 1. The first listing. Items: #1 waits for triage, #2 too with no label at all (the workflow did
#    not run), PR #5 too though it is signed as DEV's; #3 was triaged, and #4 is the owner's. The
#    comments: outside ones on an issue (#3), on a PR's conversation (PR #5) and on a PR's code
#    (PR #6), each with its account; the owner's and a member's are not listed. The reviews of the
#    open PR #5: an outside one is listed, the owner's is not.
github "[$(item 1 stranger NONE -60 '' "$triage"),$(item 2 helper CONTRIBUTOR -50),$(item 3 stranger NONE -40 '' '👷🏼‍♂️ owner:cto' '🐛 bug'),$(item 4 gzurl OWNER -30),$(item 5 mimic NONE -20 pr "$triage")]" \
  "[$(said 11 '#3' stranger NONE -60),$(said 12 '#3' gzurl OWNER -50),$(said 13 'PR #5' helper CONTRIBUTOR -40)]" \
  "[$(said 14 'PR #6' newcomer FIRST_TIME_CONTRIBUTOR -30 code),$(said 15 'PR #6' teammate MEMBER -20 code)]"
echo "[$(reviewed 51 5 mimic NONE -10),$(reviewed 52 5 gzurl OWNER -5)]" > "$lab/gh/reviews-5.json"
run 0
finds "the first listing shows the items that wait for triage, then every outside comment and review, each with its account" "$(
  tsv item "#1" https://github.com/o/r/issues/1 stranger NONE "2026-10-03 11:00"
  tsv item "#2" https://github.com/o/r/issues/2 helper CONTRIBUTOR "2026-10-03 11:10"
  tsv item "PR #5" https://github.com/o/r/pull/5 mimic NONE "2026-10-03 11:40"
  tsv comment "#3" "https://github.com/o/r/issues/3#issuecomment-11" stranger NONE "2026-10-03 11:00"
  tsv comment "PR #5" "https://github.com/o/r/pull/5#issuecomment-13" helper CONTRIBUTOR "2026-10-03 11:20"
  tsv comment "PR #6" "https://github.com/o/r/pull/6#discussion_r14" newcomer FIRST_TIME_CONTRIBUTOR "2026-10-03 11:30"
  tsv review "PR #5" "https://github.com/o/r/pull/5#pullrequestreview-51" mimic NONE "2026-10-03 11:50")"
if ! grep -q since "$lab/queries.txt"; then pass "with no triage marked yet, every comment is asked for"; else fail "a first listing asked for: $(cat "$lab/queries.txt")"; fi
marks "and it ends with the --mark that records its own time" 2026-10-03T12:00:00Z
if [ ! -e "$squad/triage.since" ]; then pass "a listing marks nothing by itself"; else fail "a listing wrote $(cat "$squad/triage.since")"; fi
#    With a jq that ends its lines with CRLF, as on Windows, the same listing (agent-squad #405).
listing="$out"
crlf run 0
finds "with a jq that ends its lines with CRLF, the same listing, every item, comment and review in it" "$listing"

# 2. The mark takes the time the CTO's listing named, noon, whatever ran since: a comment written
#    during the triage (12:03), one edited after it (written at 9:00, edited at 12:20) and a review
#    submitted after it (12:10) are listed next time; a comment and a review from before (11:59,
#    11:50) are not. The items wait until they are triaged.
github "[$(item 1 stranger NONE -60 '' "$triage"),$(item 7 stranger NONE -60 pr)]" \
  "[$(said 21 '#1' stranger NONE -1),$(said 22 '#1' stranger NONE 3),$(said 23 '#1' helper CONTRIBUTOR 20)]" '[]'
echo "[$(reviewed 71 7 stranger NONE -10),$(reviewed 72 7 helper CONTRIBUTOR 10)]" > "$lab/gh/reviews-7.json"
run 4
run 5 --mark 2026-10-03T12:00:00Z
if [ "$code" -eq 0 ] && [ -z "$out" ] && [ "$(cat "$squad/triage.since")" = "2026-10-03T12:00:00Z" ]; then
  pass "--mark records the time it is given, the listing's, and prints nothing"
else
  fail "--mark: exit $code, printed '$out', said '$err', kept '$(cat "$squad/triage.since" 2>/dev/null)'"
fi
run 30
finds "the next listing shows the comments and reviews written since that time, and the items still untriaged" "$(
  tsv item "#1" https://github.com/o/r/issues/1 stranger NONE "2026-10-03 11:00"
  tsv item "PR #7" https://github.com/o/r/pull/7 stranger NONE "2026-10-03 11:00"
  tsv comment "#1" "https://github.com/o/r/issues/1#issuecomment-22" stranger NONE "2026-10-03 12:03"
  tsv comment "#1" "https://github.com/o/r/issues/1#issuecomment-23" helper CONTRIBUTOR "2026-10-03 12:20"
  tsv review "PR #7" "https://github.com/o/r/pull/7#pullrequestreview-72" helper CONTRIBUTOR "2026-10-03 12:10")"
if [ "$(grep -c 'since=2026-10-03T12:00:00Z' "$lab/queries.txt")" -eq 2 ]; then
  pass "and asks GitHub for the comments since then, on conversations and on code"
else
  fail "the queries were: $(cat "$lab/queries.txt")"
fi
if [ "$(cat "$squad/triage.since")" = "2026-10-03T12:00:00Z" ]; then
  pass "and that listing, like any other, leaves the mark where it was"
else
  fail "a listing moved the mark to $(cat "$squad/triage.since")"
fi

# 2b. Lists the size of a real repository's go through, read from files, never as arguments: 8,000
#     comments on conversations and as many on code, over a megabyte each even cut down to the
#     fields the list uses, over what macOS allows a command's arguments in all and Linux one
#     argument. Only the outside comment is listed.
many() {
  jq -nc --arg at "$(at 31)" --arg kind "$1" '[range(8000) | . as $i
    | {id: $i, user: {login: "gzurl"}, author_association: "OWNER", updated_at: $at, body: "A text."}
      + if $kind == "code" then {pull_request_url: "https://api.github.com/repos/o/r/pulls/6", html_url: "https://github.com/o/r/pull/6#discussion_r\($i)"}
        else {issue_url: "https://api.github.com/repos/o/r/issues/4", html_url: "https://github.com/o/r/issues/4#issuecomment-\($i)"} end]'
}
github "[$(item 4 gzurl OWNER -30)]" "$(many conversation | jq -c --argjson one "$(said 9000 '#4' stranger NONE 32)" '. + [$one]')" "$(many code)"
run 40
finds "lists over a megabyte go through, and only the outside comment is listed" \
  "$(tsv comment "#4" "https://github.com/o/r/issues/4#issuecomment-9000" stranger NONE "2026-10-03 12:32")"

# 3. Nothing from outside prints nothing.
github "[$(item 4 gzurl OWNER -30)]" "[$(said 31 '#4' gzurl OWNER 10)]" '[]'
run 40
finds "with nothing from outside, nothing is printed" ""

# 4. GitHub unreadable is an error, never an empty list, and the listing's time is not kept.
github "[$(item 1 stranger NONE -60 '' "$triage"),$(item 7 stranger NONE -60 pr)]" '[]' '[]'
echo "[$(reviewed 71 7 stranger NONE 45)]" > "$lab/gh/reviews-7.json"
for what in repo opened opened-partial opened-garbage conversation conversation-partial code code-garbage reviews reviews-partial; do
  GH_FAIL="$what" run 50
  if [ "$code" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "squad-outside: cannot read "*"; nothing was listed" ]]; then
    pass "GitHub failing on $what is an error, exit 1, with nothing listed and no --mark offered"
  else
    fail "GitHub failing on $what: exit $code, printed '$out', said '$err'"
  fi
done
#    A call that GitHub never answers is stopped after SQUAD_GH_TIMEOUT seconds of wall-clock time,
#    and fails the run as any other failure does, saying why (agent-squad #430).
started=$SECONDS
GH_FAIL=conversation-hang SQUAD_GH_TIMEOUT=1 run 50
took=$((SECONDS - started))
# Within 30 s: well under its stub's 60 s, and over what CI's kcov takes (agent-squad #447).
if [ "$code" -eq 1 ] && [ -z "$out" ] && [ "$took" -le 30 ] \
  && [ "$err" = "squad-outside: GitHub did not answer within 1 s"$'\n'"squad-outside: cannot read the comments; nothing was listed" ] \
  && ! kill -0 "$(cat "$lab/hung.pid")" 2>/dev/null; then
  pass "a call that GitHub never answers is stopped after its bound: exit 1, saying so, and nothing left running"
else
  fail "a call that GitHub never answers: exit $code after $took s, printed '$out', said '$err'"
fi
#    A SQUAD_GH_TIMEOUT that is not a whole number above 0 is 120 s: the run reads GitHub as without
#    one (QA's finding on PR #432).
run 50
expected="$code|$out"
SQUAD_GH_TIMEOUT=abc run 50
if [ "$expected" = "0|$out" ] && [ "$code" -eq 0 ] && [ -n "$out" ]; then
  pass "a SQUAD_GH_TIMEOUT that is no number reads GitHub as without one"
else
  fail "a SQUAD_GH_TIMEOUT that is no number: exit $code, printed '$out', said '$err'"
fi

# 5. Marks and times that do not hold.
rm -f "$squad/triage.since"
echo "yesterday" > "$squad/triage.since"
run 0
if [ "$code" -eq 1 ] && [[ "$err" == *"does not hold a time"* ]]; then
  pass "a last triage's time that is not one is an error, exit 1"
else
  fail "a time that is not one: exit $code, said '$err'"
fi
rm -f "$squad/triage.since"
mkdir "$squad/triage.since"
run 0 --mark 2026-10-03T12:00:00Z
rmdir "$squad/triage.since"
if [ "$code" -eq 1 ] && [[ "$err" == *"cannot keep the last triage's time in "*"triage.since: it is not a file"* ]]; then
  pass "a mark that cannot be kept is an error, exit 1"
else
  fail "a mark that cannot be kept: exit $code, printed '$out', said '$err'"
fi

# 6. Bad usage, and a place that is not a squad's checkout, exit 2.
for args in "--mark" "--mark yesterday" "--mark 2026-10-03T12:00:00Z extra" "--bogus" "list"; do
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
