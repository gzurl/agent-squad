#!/usr/bin/env bash
# Check that squad-tokens.sh reports token usage as agent-squad #119 says, on fixture transcripts:
# each response counts once, by its message id, however many times it is written and whichever
# transcripts hold it; a subagent counts for its session; the role is read on either side of the
# colon, so that two projects with the same role stay apart; the default report covers the project
# it runs from, --all the whole machine; the history keeps what the transcripts lose, and a change
# in their format stops the script. Everything happens in a temporary directory, with
# CLAUDE_CONFIG_DIR pointing at it, so this script reads none of the machine's transcripts.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
tokens="$root/scripts/squad-tokens.sh"
# This script builds repositories of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-tokens.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# The project: a main checkout whose path has a space and a dot, with the squad installed, and
# the Claude Code directory its sessions are kept in, named as Claude Code names it.
repo="$lab/My Project.v2"
mkdir -p "$repo/.agent-squad" && git -C "$repo" init -q || exit 2
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init || exit 2
here="$(cd "$repo" && pwd -P | tr -d '\n' | tr -c 'A-Za-z0-9' '-')"
history="$repo/.agent-squad/tokens.tsv"
export CLAUDE_CONFIG_DIR="$lab/claude"
projects="$CLAUDE_CONFIG_DIR/projects"
mkdir -p "$projects/$here" "$projects/-elsewhere-beta"

# `response <id> <model> <timestamp> <input> <cache write> <cache read> <output>` prints one line
# of a transcript as Claude Code writes a model response; `named <name>` the line of a rename.
response() {
  jq -nc --arg id "$1" --arg m "$2" --arg ts "$3" --argjson i "$4" --argjson cw "$5" --argjson cr "$6" --argjson o "$7" \
    '{type: "assistant", timestamp: $ts, sessionId: "s", message: {id: $id, model: $m, role: "assistant",
      content: [{type: "text", text: "..."}], usage: {input_tokens: $i, cache_creation_input_tokens: $cw,
      cache_read_input_tokens: $cr, output_tokens: $o, service_tier: "standard"}}}'
}
named() { jq -nc --arg t "$1" '{type: "custom-title", customTitle: $t, sessionId: "s"}'; }
prompt() { jq -nc --arg ts "$1" '{type: "user", timestamp: $ts, message: {role: "user", content: "go"}}'; }

# This project's sessions. CTO:alpha writes r1 once per content block, its output growing as it
# streams; r2 on the next day, with another model; a placeholder response; and a subagent's r3.
# alpha:QA carries its role after the colon; `notes` has no role, and one session has no name.
d1=2026-09-10 d2=2026-09-11 d3=2026-09-12
{ named "CTO:alpha"; prompt "${d1}T07:59:00.000Z"
  response r1 claude-test-1 "${d1}T08:00:00.000Z" 1 10 100 5
  response r1 claude-test-1 "${d1}T08:00:01.000Z" 1 10 100 5
  response r1 claude-test-1 "${d1}T08:00:02.000Z" 1 10 100 40
  response syn1 '<synthetic>' "${d1}T08:01:00.000Z" 0 0 0 0
  response r2 claude-test-2 "${d2}T09:00:00.000Z" 2 20 200 50
} >"$projects/$here/s1.jsonl"
mkdir -p "$projects/$here/s1/subagents"
response r3 claude-test-1 "${d1}T08:30:00.000Z" 3 30 300 60 >"$projects/$here/s1/subagents/agent-a1.jsonl"
{ named "DEV:alpha"; response r4 claude-test-1 "${d1}T10:00:00.000Z" 4 40 400 70; } >"$projects/$here/s2.jsonl"
{ named "alpha:QA"; response r5 claude-test-1 "${d1}T11:00:00.000Z" 5 50 500 80; } >"$projects/$here/s3.jsonl"
{ named "notes"; response r6 claude-test-1 "${d1}T12:00:00.000Z" 6 60 600 90; } >"$projects/$here/s4.jsonl"
response r7 claude-test-1 "${d1}T13:00:00.000Z" 7 70 700 100 >"$projects/$here/s5.jsonl"
# Another project's sessions, launched elsewhere. DEV:beta was forked from CTO:beta: it holds a copy
# of r8 and a copy of r9 with its usage zeroed, then goes on to r10, so its last entry is later.
{ named "CTO:beta"
  response r8 claude-test-1 "${d1}T10:00:00.000Z" 8 80 800 110
  response r9 claude-test-1 "${d1}T10:05:00.000Z" 9 90 900 120
} >"$projects/-elsewhere-beta/s6.jsonl"
{ named "DEV:beta"
  response r8 claude-test-1 "${d1}T10:00:00.000Z" 8 80 800 110
  response r9 claude-test-1 "${d1}T10:05:00.000Z" 0 0 0 0
  response r10 claude-test-1 "${d3}T10:00:00.000Z" 10 100 1000 130
} >"$projects/-elsewhere-beta/s7.jsonl"

# `run <directory> <options...>` runs the script there; its output, error and exit status land in
# $out, $err and $code.
run() {
  local dir="$1"; shift
  out="$(cd "$dir" && "$tokens" "$@" </dev/null 2>"$lab/err")"; code=$?
  err="$(cat "$lab/err")"
}
# `row <agent>` prints the agent's row of the last --tsv output, without its project and role.
row() { printf '%s\n' "$out" | awk -F'\t' -v a="$1" '$3 == a { r = $3; for (c = 4; c <= NF; c++) r = r "\t" $c; print r }'; }
# `expect <case> <agent> <expected row>` checks one agent's row of the last --tsv output.
expect() {
  local got; got="$(row "$2")"
  if [ "$got" = "$3" ]; then pass "$1"; else fail "$1: $2 reads '$got', expected '$3'"; fi
}
tsv_row() { local IFS=$'\t'; echo "$*"; }

# 1. The default report covers the sessions of the project it runs from, whatever their names, and
#    reads nothing it should not write: the transcripts are only read.
sums_before="$(find "$projects" -type f -exec cksum {} + | sort)"
run "$repo" --tsv
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -n +2 | cut -f3 | tr '\n' ' ')" = "CTO:alpha DEV:alpha alpha:QA (untitled) notes " ] \
   && [ "$(printf '%s\n' "$out" | tail -n +2 | cut -f1 | sort -u)" = "My Project.v2" ]; then
  pass "by default, the report covers the sessions launched from this checkout, under its name, and leaves out another project's"
else
  fail "the default report: exit $code, output:"$'\n'"$out"$'\n'"$err"
fi
if [ "$(find "$projects" -type f -exec cksum {} + | sort)" = "$sums_before" ]; then
  pass "the transcripts are left as they were"
else
  fail "a transcript changed"
fi

# 2. --all covers every project on the machine, one block per project read from the sessions'
#    names; a name with no role is among the other sessions.
run "$repo" --all --tsv
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -n 1)" = "$(tsv_row project role agent responses input cache_write cache_read output models)" ] \
   && [ "$(printf '%s\n' "$out" | tail -n +2 | cut -f1-3 | tr '\t\n' '/ ')" = "alpha/CTO/CTO:alpha alpha/DEV/DEV:alpha alpha/QA/alpha:QA beta/CTO/CTO:beta beta/DEV/DEV:beta //(untitled) //notes " ]; then
  pass "--all covers every project, the roles in order CTO, DEV, QA, then the sessions without a role"
else
  fail "--all: exit $code, output:"$'\n'"$out"$'\n'"$err"
fi
expect "a response written once per content block counts once, with its full output; a placeholder response counts for nothing; a subagent counts for its session" \
  CTO:alpha "$(tsv_row CTO:alpha 3 6 60 600 150 claude-test-1,claude-test-2)"
expect "the role is read after the colon too (alpha:QA)" alpha:QA "$(tsv_row alpha:QA 1 5 50 500 80 claude-test-1)"
expect "two projects with the same role stay apart (CTO:beta)" CTO:beta "$(tsv_row CTO:beta 1 9 90 900 120 claude-test-1)"
expect "a response copied into a forked session counts once, for the transcript written last, and a zeroed copy loses to the full record" \
  DEV:beta "$(tsv_row DEV:beta 2 18 180 1800 240 claude-test-1)"
expect "a session with no name is reported as (untitled)" "(untitled)" "$(tsv_row "(untitled)" 1 7 70 700 100 claude-test-1)"

# 3. The plain report: one block per project with its subtotal, then the roles, the other sessions
#    and the total, the figures in millions.
run "$repo" --all
labels="$(printf '%s\n' "$out" | sed -n '/^Agent /,$p' | tail -n +2 | sed -E 's/^ +//; s/  +.*//' | tr '\n' '/')"
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -n 1)" = "Token usage of every project on this machine, $d1 → $d3 (UTC days)." ] \
   && [ "$labels" = "alpha/CTO:alpha/DEV:alpha/alpha:QA/subtotal/beta/CTO:beta/DEV:beta/subtotal/By role/CTO/DEV/QA/Other sessions/(untitled)/notes/subtotal/Total/" ]; then
  pass "the plain report lists each project's block, then the roles, the other sessions and the total"
else
  fail "the plain report's lines read '$labels'; output:"$'\n'"$out"
fi
total="$(printf '%s\n' "$out" | grep '^Total ' | tr -s ' ')"
# 10 responses, r1 to r10: response k reads k + 10k + 100k input tokens, 100k of them from the
# cache, so 5500 of the 6105 in all (90 %), and writes 850 output tokens.
if [ "$total" = "Total 10 0.0 M 90 % 0.00 M claude-test-1, claude-test-2" ]; then
  pass "the total counts 10 responses, 90 % of their input read from the cache"
else
  fail "the total reads '$total'"
fi

# 4. --project, --since and --by-day.
run "$repo" --project beta --tsv
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -n +2 | cut -f3 | tr '\n' ' ')" = "CTO:beta DEV:beta " ]; then
  pass "--project beta reports that project only"
else
  fail "--project beta: exit $code, output:"$'\n'"$out"
fi
run "$repo" --all --since "$d2" --tsv
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -n +2 | cut -f3,4 | tr '\t\n' '= ')" = "CTO:alpha=1 DEV:beta=1 " ]; then
  pass "--since leaves out the days before it"
else
  fail "--since: exit $code, output:"$'\n'"$out"
fi
#    The fixtures' days are past, so a period of the last two days finds nothing, and says from when.
run "$repo" --all --since 2d --tsv
if [ "$code" -eq 0 ] && [ "$out" = "No token usage recorded since $(date -u -r $(($(date -u +%s) - 86400)) +%F 2>/dev/null || date -u -d yesterday +%F)." ]; then
  pass "--since 2d means from yesterday on, in UTC"
else
  fail "--since 2d: exit $code, output '$out'"
fi
for n in 0d 1x d; do
  run "$repo" --since "$n"
  if [ "$code" -eq 2 ]; then
    pass "--since $n is bad usage, exit 2"
  else
    fail "--since $n: exit $code"
  fi
done
run "$repo" --by-day --tsv
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | awk -F'\t' '$4 == "CTO:alpha" { print $1 "=" $5 }' | tr '\n' ' ')" = "$d1=2 $d2=1 " ]; then
  pass "--by-day splits each agent's usage per day"
else
  fail "--by-day: exit $code, output:"$'\n'"$out"
fi
run "$repo" --by-day
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^== ')" -eq 2 ]; then
  pass "--by-day prints one report per day"
else
  fail "--by-day, plain: output:"$'\n'"$out"
fi

# 5. From a linked worktree, the report and the history are the main checkout's.
git -C "$repo" worktree add -q --detach "$repo/.agent-squad/worktrees/dev" || exit 2
run "$repo" --tsv; from_main="$out"
run "$repo/.agent-squad/worktrees/dev" --tsv
if [ "$code" -eq 0 ] && [ "$out" = "$from_main" ] && [ ! -e "$repo/.agent-squad/worktrees/dev/.agent-squad" ]; then
  pass "from a linked worktree, the report covers the main checkout's sessions"
else
  fail "from a worktree: exit $code, output:"$'\n'"$out"$'\n'"$err"
fi

# 6. The history keeps one row per day, session, agent and model, under the header it is read by.
if [ "$(head -n 1 "$history")" = "$(tsv_row day dir session agent model responses input cache_write cache_read output)" ] \
   && grep -qF "$(tsv_row "$d1" "$here" s1 CTO:alpha claude-test-1 2 4 40 400 100)" "$history"; then
  pass "the history keeps one row per day, session, agent and model"
else
  fail "the history reads:"$'\n'"$(cat "$history")"
fi
#    A session whose transcript is gone keeps its rows.
rm "$projects/$here/s2.jsonl"
run "$repo" --tsv
expect "a session whose transcript is gone keeps its usage, from the history" DEV:alpha "$(tsv_row DEV:alpha 1 4 40 400 70 claude-test-1)"
#    A subagent's transcript is gone while its session's is still there: the day keeps its stored
#    rows, which count more responses. The next day, still in the transcripts, grows with r11.
rm "$projects/$here/s1/subagents/agent-a1.jsonl"
response r11 claude-test-2 "${d2}T09:30:00.000Z" 11 110 1100 140 >>"$projects/$here/s1.jsonl"
run "$repo" --tsv
expect "a day that lost a subagent's transcript keeps its stored rows, and a day still in the transcripts is recomputed" \
  CTO:alpha "$(tsv_row CTO:alpha 4 17 170 1700 290 claude-test-1,claude-test-2)"
#    A session renamed moves its whole day to its new name.
named "QA:alpha" >>"$projects/$here/s3.jsonl"
run "$repo" --tsv
if [ -z "$(row alpha:QA)" ] && [ "$(row QA:alpha)" = "$(tsv_row QA:alpha 1 5 50 500 80 claude-test-1)" ]; then
  pass "a renamed session's usage moves to its new name, and is not counted under both"
else
  fail "after a rename: output:"$'\n'"$out"
fi

# 7. An empty projects directory says so, and the report reads the history.
run "$repo" --tsv
before="$out"
CLAUDE_CONFIG_DIR="$lab/empty" run "$repo" --tsv
if [ "$code" -eq 0 ] && grep -qF "no Claude Code transcripts in $lab/empty/projects" <<<"$err" && [ "$out" = "$before" ]; then
  pass "with no transcripts, the script says so and reports the history"
else
  fail "no transcripts: exit $code, said '$err', output:"$'\n'"$out"
fi
mkdir -p "$lab/bare/.agent-squad" && git -C "$lab/bare" init -q
CLAUDE_CONFIG_DIR="$lab/empty" run "$lab/bare"
if [ "$code" -eq 0 ] && [[ "$out" == "No token usage recorded for bare "* ]]; then
  pass "with no transcripts and no history, the script says that nothing is recorded"
else
  fail "nothing recorded: exit $code, output '$out'"
fi

# 8. A change in the transcripts' format stops the script, naming the file and what is missing,
#    and leaves the history as it was. `broken <case> <what it says> <line...>` writes a transcript
#    of those lines alone and runs the script on it.
broken() {
  local case="$1" says="$2"; shift 2
  rm -rf "$lab/broken"; mkdir -p "$lab/broken/projects/$here"
  printf '%s\n' "$@" >"$lab/broken/projects/$here/bad.jsonl"
  local kept; kept="$(cksum <"$history")"
  CLAUDE_CONFIG_DIR="$lab/broken" run "$repo" --tsv
  if [ "$code" -eq 1 ] && [ -z "$out" ] && grep -qF "bad.jsonl: line " <<<"$err" && grep -qF -- "$says" <<<"$err" \
     && [ "$(cksum <"$history")" = "$kept" ]; then
    pass "$case stops the script, exit 1: $err"
  else
    fail "$case: exit $code, output '$out', said: $err"
  fi
}
broken "a response without usage" "a response without message.usage" \
  "$(response r20 claude-test-1 "${d1}T08:00:00.000Z" 1 1 1 1 | jq -c 'del(.message.usage)')"
broken "a response without one of its counts" "a response without message.usage.output_tokens" \
  "$(response r21 claude-test-1 "${d1}T08:00:00.000Z" 1 1 1 1 | jq -c 'del(.message.usage.output_tokens)')"
broken "a response whose time is not in UTC" "a response without a UTC timestamp" \
  "$(response r22 claude-test-1 "2026-09-10T10:00:00+02:00" 1 1 1 1)"
broken "a rename without its name" "a custom-title entry without customTitle" '{"type":"custom-title","title":"x"}'
broken "a line that is not JSON" "bad.jsonl: line 2: a line that is not JSON" "$(named "CTO:alpha")" '{"type": "assistant", "message": ' "$(prompt "${d1}T08:00:00.000Z")"
#    A last line with no newline yet is still being written: it is left for the next run.
rm -rf "$lab/partial"; mkdir -p "$lab/partial/projects/$here"
{ named "CTO:alpha"; response r30 claude-test-1 "${d3}T08:00:00.000Z" 1 1 1 1
  response r31 claude-test-1 "${d3}T08:01:00.000Z" 1 1 1 1 | tr -d '\n'; } >"$lab/partial/projects/$here/s.jsonl"
CLAUDE_CONFIG_DIR="$lab/partial" run "$repo" --since "$d3" --tsv
if [ "$code" -eq 0 ] && [ "$(row CTO:alpha | cut -f2)" = 1 ]; then
  pass "a last line still being written is skipped, not refused"
else
  fail "a partial last line: exit $code, output '$out', said: $err"
fi

# 9. A history this script did not write stops it, untouched.
mkdir -p "$lab/foreign/.agent-squad" && git -C "$lab/foreign" init -q
printf 'when\twho\n2026-09-10\tme\n' >"$lab/foreign/.agent-squad/tokens.tsv"
run "$lab/foreign"
if [ "$code" -eq 1 ] && grep -qF "does not start with the header this script writes" <<<"$err" \
  && [ "$(cat "$lab/foreign/.agent-squad/tokens.tsv")" = $'when\twho\n2026-09-10\tme' ]; then
  pass "a history with another header stops the script, exit 1, and is left as it was"
else
  fail "a foreign history: exit $code, said: $err"
fi

# 10. Bad usage, and a place that is not a squad's checkout, exit 2.
for args in "--bogus" "--since 2026-9-1" "--project"; do
  # shellcheck disable=SC2086 # the options are split on purpose
  run "$repo" $args
  if [ "$code" -eq 2 ]; then
    pass "'$args' is bad usage, exit 2"
  else
    fail "'$args': exit $code"
  fi
done
mkdir -p "$lab/plain" && git -C "$lab/plain" init -q
run "$lab/plain"
if [ "$code" -eq 2 ] && grep -qF "has no .agent-squad/" <<<"$err"; then
  pass "a checkout without the squad installed is refused, exit 2"
else
  fail "no squad: exit $code, said: $err"
fi
mkdir -p "$lab/nogit"
run "$lab/nogit"
if [ "$code" -eq 2 ]; then
  pass "outside a git checkout, exit 2"
else
  fail "outside git: exit $code, said: $err"
fi

exit "$status"
