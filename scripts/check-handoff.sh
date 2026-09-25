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

lab="$(mktemp -d)" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# `run <directory> <action> <payload>` runs the hook there as Claude Code does: payload on stdin.
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
  if run "$1" save "{\"session_id\":\"$2\"}" && [ -s "$handoff_dir/$2.md" ]; then
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
run "$beside" save '{"session_id":"../escape"}'
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
# `on_a_terminal <out> <command...>` runs the command with a pseudo-terminal as stdin that stays
# open for five seconds, its output in <out>, and passes when it returns well before that. script(1)
# comes in a util-linux form and a BSD one (macOS).
on_a_terminal() {
  local out="$1" start
  shift
  command -v script >/dev/null 2>&1 || return 1
  start="$(date +%s)"
  if script -q -c true /dev/null </dev/null >/dev/null 2>&1; then
    script -q -c "$(printf '%q ' "$@")" /dev/null > "$out" 2>&1 < <(sleep 5)
  else
    script -q /dev/null "$@" > "$out" 2>&1 < <(sleep 5)
  fi
  [ $(($(date +%s) - start)) -lt 3 ]
}
if (cd "$beside" && on_a_terminal "$lab/tty.out" "$handoff" restore) \
  && grep -q 'Context was compacted' "$lab/tty.out"; then
  pass "restore run by hand on a terminal does not wait for input"
else
  fail "restore run by hand on a terminal waited for input, or did not run"
fi

exit "$status"
