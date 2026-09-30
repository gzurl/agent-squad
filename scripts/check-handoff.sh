#!/usr/bin/env bash
# Check that the compaction hooks of SQUAD.md §7 behave as agent-squad #34 says: `save` keeps its
# snapshot in the main checkout's .agent-squad/handoff/, from the main checkout and from any linked
# worktree, and `restore` prints it back; `startup` warns in one line when the installed charter is
# missing and prints nothing when it is there; a session id that is not a plain name writes nothing;
# every action exits 0; run by hand on a terminal, it does not wait for input (#42). Everything
# happens in a temporary directory, with a `gh` that always fails, so this script touches neither
# the repository it is run from nor GitHub.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
handoff="$root/scripts/squad-handoff.sh"
# This script builds repositories of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-handoff.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# `run <directory> <action> <payload>` runs the hook there as Claude Code does: payload on stdin.
# A save's payload says "auto", as Claude Code's does for an automatic compaction, so that the
# gate of case 9 lets it through without a word.
run() { (cd "$1" && printf '%s' "$3" | "$handoff" "$2"); }

# The snapshot asks GitHub for PRs and issues; here GitHub never answers.
mkdir -p "$lab/bin"
printf '#!/bin/sh\nexit 1\n' > "$lab/bin/gh"
chmod +x "$lab/bin/gh"
PATH="$lab/bin:$PATH"

# A main checkout with two linked worktrees: one beside it, as this repository has them, and one
# nested in .agent-squad/worktrees/, as an installed project has them.
main="$lab/main"
git init -q "$main" || exit 2
git -C "$main" -c user.email=handoff@example.com -c user.name="Handoff check" \
  commit -q --allow-empty -m "the sandbox" || exit 2
beside="$lab/beside"
nested="$main/.agent-squad/worktrees/dev"
git -C "$main" worktree add -q --detach "$beside" || exit 2
git -C "$main" worktree add -q --detach "$nested" || exit 2
handoff_dir="$main/.agent-squad/handoff"

# `saves_from <directory> <session> <where>` runs save there and expects that session's file in
# the main checkout.
saves_from() {
  if run "$1" save "{\"session_id\":\"$2\",\"trigger\":\"auto\"}" && [ -s "$handoff_dir/$2.md" ]; then
    pass "save from $3 writes the main checkout's .agent-squad/handoff/"
  else
    fail "save from $3 did not write $handoff_dir/$2.md"
  fi
}

# 1. save writes into the main checkout, from wherever the session works, and nowhere else.
saves_from "$main" from-main "the main checkout"
saves_from "$beside" from-beside "a worktree beside the main checkout"
saves_from "$nested" from-nested "a worktree nested in .agent-squad/worktrees/"
written="$(find "$lab" -name '*.md' | sort)"
expected="$(printf '%s\n' "$handoff_dir"/from-{beside,main,nested}.md | sort)"
if [ "$written" = "$expected" ]; then
  pass "save writes no file anywhere else, the old .claude/handoff/ included"
else
  fail "save wrote other files: $(comm -13 <(echo "$expected") <(echo "$written") | tr '\n' ' ')"
fi

# 2. restore, from a linked worktree, prints the snapshot saved for that session.
if out="$(run "$beside" restore '{"session_id":"from-beside"}')" \
  && printf '%s' "$out" | grep -q '^# Squad handoff .*(session from-beside)$'; then
  pass "restore from a linked worktree prints that session's snapshot"
else
  fail "restore from a linked worktree did not print the snapshot of session from-beside"
fi

# 3. A session id that is not a plain name never becomes a path.
before="$(find "$lab" -name '*.md' | sort)"
run "$beside" save '{"session_id":"../escape","trigger":"auto"}'
code=$?
after="$(find "$lab" -name '*.md' | sort)"
if [ "$code" -eq 0 ] && [ "$before" = "$after" ]; then
  pass "save with a session id that is not a plain name writes nothing"
else
  fail "save with the session id ../escape wrote a file"
fi

# 4. startup warns, in one line, when the installed charter is missing.
if out="$(run "$nested" startup '{"session_id":"x"}')" && [ -n "$out" ] \
  && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] \
  && printf '%s' "$out" | grep -q 'charter is not installed'; then
  pass "startup without the charter prints a one-line warning"
else
  fail "startup without the charter printed: '$out'"
fi

# 5. startup prints nothing when the charter is there, from any worktree.
mkdir -p "$main/.agent-squad/playbook"
echo "# Squad Charter" > "$main/.agent-squad/playbook/SQUAD.md"
if out="$(run "$beside" startup '{"session_id":"x"}')" && [ -z "$out" ]; then
  pass "startup with the charter installed prints nothing"
else
  fail "startup with the charter installed printed: '$out'"
fi

# 6. Run by hand, with a terminal as stdin and no payload, restore does not wait for input.
# `on_a_terminal <out> <last line> <command...>` runs the command with a pseudo-terminal as stdin
# that stays open for five seconds, its output in <out>, and passes when the command's last line is
# out within three seconds. It does not wait for script(1) itself, which may outlive the command
# until its own stdin closes. script(1) comes in a util-linux form and a BSD one (macOS).
on_a_terminal() {
  local out="$1" last="$2" pid tries=0
  shift 2
  command -v script >/dev/null 2>&1 || return 1
  if script -q -c true /dev/null </dev/null >/dev/null 2>&1; then
    script -q -c "$(printf '%q ' "$@")" /dev/null > "$out" 2>&1 < <(sleep 5) &
  else
    script -q /dev/null "$@" > "$out" 2>&1 < <(sleep 5) &
  fi
  pid=$!
  while ! grep -qF -- "$last" "$out" 2>/dev/null && [ "$tries" -lt 60 ]; do
    sleep 0.05
    tries=$((tries + 1))
  done
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  grep -qF -- "$last" "$out"
}
# restore's last line when no session id came with the payload.
last_line="(no handoff file was saved for this session; rely on GitHub and the repository)"
if (cd "$beside" && on_a_terminal "$lab/tty.out" "$last_line" "$handoff" restore); then
  pass "restore run by hand on a terminal does not wait for input"
else
  fail "restore run by hand on a terminal waited for input, or did not run"
fi

# 7. The snapshot's listings ask gh for an explicit limit, and say so on a line of their own when a
#    listing reaches it (#63): a cut snapshot must not read as a complete one. This gh answers with
#    GH_ITEMS pull requests and issues, honouring --limit and defaulting to 30 as gh does.
mkdir -p "$lab/bin-listing"
cat > "$lab/bin-listing/gh" <<'GH'
#!/usr/bin/env bash
limit=30
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = --limit ] && limit="${args[$((i + 1))]}"
done
n="${GH_ITEMS:-0}"
[ "$n" -gt "$limit" ] && n="$limit"
case "$1 ${2:-}" in
  "repo view") echo sandbox ;;
  "pr list")
    jq -n --argjson n "$n" '[range(1; $n + 1) | {number: ., title: "PR \(.)", headRefName: "b\(.)",
      headRefOid: "0123456789abcdef0123456789abcdef01234567", labels: []}]' ;;
  "issue list")
    jq -n --argjson n "$n" '[range(1; $n + 1) | {number: ., title: "Issue \(.)",
      labels: [{name: "🚧 status:in-progress"}]}]' ;;
  "api graphql") echo 0 ;;
  api*) echo '[]' ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin-listing/gh"
# `snapshot_with <items>` saves a snapshot against that gh and prints it.
snapshot_with() {
  rm -f "$handoff_dir/listing.md"
  (cd "$main" && echo '{"session_id":"listing","trigger":"auto"}' \
    | GH_ITEMS="$1" PATH="$lab/bin-listing:$PATH" "$handoff" save)
  cat "$handoff_dir/listing.md" 2>/dev/null
}
snapshot="$(snapshot_with 100)"
if [ "$(grep -c '^- PR #' <<<"$snapshot")" -eq 100 ] && [ "$(grep -c '^- #' <<<"$snapshot")" -eq 100 ] \
  && [ "$(grep -c 'the limit of this snapshot' <<<"$snapshot")" -eq 2 ]; then
  pass "with as many PRs and issues as the limit, all are listed and two lines say there may be more"
else
  fail "with 100 PRs and issues, the snapshot listed $(grep -c '^- PR #' <<<"$snapshot") PRs, $(grep -c '^- #' <<<"$snapshot") issues and $(grep -c 'the limit of this snapshot' <<<"$snapshot") limit lines"
fi
snapshot="$(snapshot_with 5)"
if [ "$(grep -c '^- PR #' <<<"$snapshot")" -eq 5 ] && ! grep -q 'the limit of this snapshot' <<<"$snapshot"; then
  pass "below the limit, the snapshot lists everything and says nothing about a limit"
else
  fail "with 5 PRs and issues, the snapshot did not list them plainly"
fi

# 8. The snapshot's last section is the remote's default branch as git records it (origin/HEAD),
#    whatever its name, not origin/main (#85); when git does not know it, the section says that it
#    shows the local log instead.
# `branch_section` saves a snapshot from the main checkout and prints its default branch section.
branch_section() {
  rm -f "$handoff_dir/branch.md"
  run "$main" save '{"session_id":"branch","trigger":"auto"}'
  sed -n '/^## Default branch/,$p' "$handoff_dir/branch.md" 2>/dev/null
}
# `commit_on <subject>` makes a commit on top of the local HEAD, without moving any branch.
commit_on() {
  git -C "$main" -c user.email=handoff@example.com -c user.name="Handoff check" \
    commit-tree 'HEAD^{tree}' -p HEAD -m "$1"
}
section="$(branch_section)"
if grep -qx '## Default branch: unknown to git, so the local log' <<<"$section" \
  && grep -q 'the sandbox' <<<"$section"; then
  pass "without origin/HEAD, the snapshot says so and shows the local log"
else
  fail "without origin/HEAD, the snapshot's last section was: $section"
fi
git -C "$main" update-ref refs/remotes/origin/main "$(commit_on "on main")" || exit 2
git -C "$main" update-ref refs/remotes/origin/trunk "$(commit_on "on trunk")" || exit 2
git -C "$main" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk || exit 2
section="$(branch_section)"
if grep -qx '## Default branch: origin/trunk' <<<"$section" && grep -q 'on trunk' <<<"$section" \
  && ! grep -q 'on main' <<<"$section"; then
  pass "with origin/HEAD at origin/trunk, the snapshot shows origin/trunk, not origin/main"
else
  fail "with origin/HEAD at origin/trunk, the snapshot's last section was: $section"
fi

# 9. The pre-compact gate (#100). A manual /compact goes through when the last thing the user or
#    another agent did was /squad-save-state; otherwise it is stopped once, with exit 2 and a line
#    on stderr. An automatic compaction is never stopped; a second manual /compact within ten
#    minutes of a stopped one goes through; a transcript the gate cannot read or understand lets it
#    through, saying so. The snapshot is saved in every case. The sample transcripts are built from
#    the entries Claude Code 2.1.284 writes, as recorded on #100.
tr="$lab/transcripts"
mkdir -p "$tr"
# Entries, one JSON line each: a prompt the CEO typed, a message from another agent, the
# /squad-save-state command and its expansion, a tool call and its result, the agent's answer, a
# system reminder, and the echo a stopped /compact leaves.
typed='{"type":"user","message":{"role":"user","content":"Carry on with the PR."},"origin":{"kind":"human"},"promptSource":"typed"}'
peer='{"type":"user","isMeta":true,"origin":{"kind":"peer","name":"CTO:x"},"promptSource":"system","message":{"role":"user","content":"Another Claude session sent a message:\n<cross-session-message from=\"uds:/tmp/x.sock\">A new task.</cross-session-message>"}}'
command='{"type":"user","message":{"role":"user","content":"<command-message>squad-save-state</command-message>\n<command-name>/squad-save-state</command-name>\n<command-args></command-args>"}}'
expansion='{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Record on the issue or PR it belongs to any decision…"}]}}'
tool_use='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gh issue comment 7"}}]}}'
tool_result='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}'
answer='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ready: type /compact"}]}}'
reminder='{"type":"user","isMeta":true,"message":{"role":"user","content":"<system-reminder>A note.</system-reminder>"}}'
caveat='{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>Caveat: the messages below were generated by the user while running local commands.</local-command-caveat>"}}'
compact_echo='{"type":"user","message":{"role":"user","content":"<command-name>/compact</command-name>\n            <command-message>compact</command-message>\n            <command-args></command-args>"}}'
stopped_echo='{"type":"system","subtype":"local_command","content":"<local-command-stderr>Compaction blocked by PreCompact hook: squad</local-command-stderr>"}'
# `transcript <name> <entry...>` writes a sample transcript, one entry per line.
transcript() {
  local name="$1"
  shift
  printf '%s\n' "$@" > "$tr/$name.jsonl"
}
transcript saved "$typed" "$command" "$expansion" "$tool_use" "$tool_result" "$reminder" "$answer"
transcript not-saved "$typed" "$tool_use" "$tool_result" "$answer"
transcript prompt-after "$command" "$expansion" "$answer" "$typed" "$answer"
transcript peer-after "$command" "$expansion" "$answer" "$peer" "$answer"
transcript stopped-then-saved "$typed" "$answer" "$caveat" "$compact_echo" "$stopped_echo" "$command" "$expansion" "$answer"
transcript saved-then-echo "$command" "$expansion" "$answer" "$caveat" "$compact_echo" "$stopped_echo"
# The interactive CLI (Claude Code 2.1.285) writes the typed command itself as a plain user entry,
# just before its markup, by the time the hook runs (#134).
plain_compact='{"type":"user","userType":"external","entrypoint":"cli","message":{"role":"user","content":"/compact"}}'
plain_compact_args='{"type":"user","userType":"external","entrypoint":"cli","message":{"role":"user","content":"/compact keep the PR state"}}'
not_compact='{"type":"user","origin":{"kind":"human"},"promptSource":"typed","message":{"role":"user","content":"/compactify the notes"}}'
transcript saved-then-plain "$command" "$expansion" "$tool_use" "$tool_result" "$answer" "$plain_compact" "$compact_echo"
transcript saved-then-plain-args "$command" "$expansion" "$answer" "$plain_compact_args" "$compact_echo"
transcript not-saved-then-plain "$typed" "$answer" "$plain_compact" "$compact_echo"
transcript saved-then-look-alike "$command" "$expansion" "$answer" "$not_compact"
quoting='{"type":"user","isMeta":true,"origin":{"kind":"peer","name":"QA:x"},"promptSource":"system","message":{"role":"user","content":"Another Claude session sent a message:\n<cross-session-message from=\"uds:/tmp/y.sock\">The gate looks for <command-name>/squad-save-state</command-name>.</cross-session-message>"}}'
transcript quoting-after "$typed" "$answer" "$quoting"
printf '%s\n' "$command" '{"type":"user", "message": {' > "$tr/broken.jsonl"
# `gate <session> <trigger> <transcript>` runs save as the PreCompact hook does, from the main
# checkout; its exit status lands in $code and its stderr in $err.
gate() {
  local payload
  payload="$(jq -cn --arg s "$1" --arg t "$2" --arg p "$3" '{session_id: $s, hook_event_name: "PreCompact", trigger: $t, transcript_path: $p, custom_instructions: null}')"
  err="$(cd "$main" && printf '%s' "$payload" | "$handoff" save 2>&1 >/dev/null)"
  code=$?
}
# `passes <case> <session> <trigger> <transcript> [<stderr text>]` expects exit 0, and that text on
# stderr when one is given; `stopped <case> <session> <trigger> <transcript>` expects exit 2 and
# the line that says what to do.
passes() {
  gate "$2" "$3" "$4"
  if [ "$code" -eq 0 ] && { [ -z "${5:-}" ] || grep -qF -- "$5" <<<"$err"; }; then
    pass "$1: /compact goes through"
  else
    fail "$1: exit $code, stderr: $err"
  fi
}
stopped() {
  gate "$2" "$3" "$4"
  if [ "$code" -eq 2 ] && grep -qF 'run /squad-save-state first' <<<"$err"; then
    pass "$1: /compact is stopped, exit 2, saying to run /squad-save-state first"
  else
    fail "$1: exit $code, stderr: $err"
  fi
}
passes "automatic, without /squad-save-state" auto-1 auto "$tr/not-saved.jsonl"
passes "manual, right after /squad-save-state and the agent's work" saved-1 manual "$tr/saved.jsonl"
stopped "manual, without /squad-save-state" none-1 manual "$tr/not-saved.jsonl"
stopped "manual, with a prompt from the CEO after /squad-save-state" prompt-1 manual "$tr/prompt-after.jsonl"
stopped "manual, with a message from another agent after /squad-save-state" peer-1 manual "$tr/peer-after.jsonl"
stopped "manual, after a message that only quotes the command's markup" quoting-1 manual "$tr/quoting-after.jsonl"
passes "manual, /squad-save-state after a stopped /compact" stopped-1 manual "$tr/stopped-then-saved.jsonl"
passes "manual, a stopped /compact's echo after /squad-save-state" echo-1 manual "$tr/saved-then-echo.jsonl"
passes "manual, the CLI's plain /compact entry after /squad-save-state" plain-1 manual "$tr/saved-then-plain.jsonl"
passes "manual, the plain entry with arguments after /squad-save-state" plain-2 manual "$tr/saved-then-plain-args.jsonl"
stopped "manual, the plain /compact entry without /squad-save-state" plain-3 manual "$tr/not-saved-then-plain.jsonl"
stopped "manual, a prompt that only starts like /compact" plain-4 manual "$tr/saved-then-look-alike.jsonl"
#    The escape hatch: stopped once, the same session's next /compact within ten minutes goes
#    through, and only once; another session's does not; one ten minutes and a second later does not.
stopped "the first /compact" hatch-1 manual "$tr/not-saved.jsonl"
passes "a second /compact within ten minutes of a stopped one" hatch-1 manual "$tr/not-saved.jsonl" "within 10 minutes"
stopped "the third, since the second went through" hatch-1 manual "$tr/not-saved.jsonl"
stopped "another session's /compact after it" hatch-2 manual "$tr/not-saved.jsonl"
echo "$(( $(date +%s) - 601 ))" > "$handoff_dir/hatch-1.blocked"
stopped "a second /compact ten minutes and a second after a stopped one" hatch-1 manual "$tr/not-saved.jsonl"
#    What the gate cannot read or understand lets the compaction through, and says it could not check.
passes "a transcript that does not exist" missing-1 manual "$tr/no-such.jsonl" "could not check"
passes "a transcript that is not JSON lines" broken-1 manual "$tr/broken.jsonl" "could not check"
transcript empty
passes "a transcript with nothing the user did" empty-1 manual "$tr/empty.jsonl" "could not check"
passes "a trigger that is neither manual nor auto" odd-1 sometimes "$tr/not-saved.jsonl" "could not check"
#    The snapshot is saved whatever the gate decides.
if [ -s "$handoff_dir/none-1.md" ] && [ -s "$handoff_dir/saved-1.md" ] && [ -s "$handoff_dir/auto-1.md" ]; then
  pass "the snapshot is saved whether the compaction is stopped, let through or automatic"
else
  fail "a snapshot is missing: $(find "$handoff_dir" -name '*.md' | tr '\n' ' ')"
fi

exit "$status"
