#!/usr/bin/env bash
# Check that the squad's commands only the CEO types cannot be run by the model (agent-squad #325).
# Each carries `disable-model-invocation: true` in its frontmatter, which Claude Code honours in
# .claude/commands/ as in a skill: the model's Skill tool refuses such a command, and the CEO can
# still type it. The commands an agent runs itself, /squad-watch through /loop and the token
# reports, carry no such line. It walks the repository's real commands/, fails when it finds none,
# and fails on a command in neither list below, which has to be put in one of them.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# The commands only the CEO types, as the CEO decided on #325, and those the model may run.
ceo_only=(squad-uninstall squad-upgrade squad-pause squad-pause-all squad-autopilot squad-autopilot-all
  squad-resume squad-resume-all squad-save-state)
invocable=(squad-watch squad-usage squad-usage-all)

# `flag_of <file>` prints the value of disable-model-invocation in the file's frontmatter, the block
# between its first two `---` lines, or nothing when it has none.
flag_of() {
  awk 'NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^disable-model-invocation:/ { sub(/^disable-model-invocation:[ \t]*/, ""); print }' "$1"
}
# `listed <name> <names...>` passes when the name is among the names.
listed() {
  local name="$1"
  shift
  printf '%s\n' "$@" | grep -qxF -- "$name"
}

# Each command of the repository, as the installer copies it into a project's .claude/commands/.
count=0
for file in "$root"/commands/squad-*.md; do
  [ -f "$file" ] || continue
  count=$((count + 1))
  name="$(basename "$file" .md)"
  flag="$(flag_of "$file")"
  if listed "$name" "${ceo_only[@]}"; then
    if [ "$flag" = true ]; then
      pass "/$name is the CEO's to type: the model cannot run it"
    else
      fail "/$name is the CEO's to type, but its frontmatter has no disable-model-invocation: true"
    fi
  elif listed "$name" "${invocable[@]}"; then
    if [ -z "$flag" ]; then
      pass "/$name stays the model's to run"
    else
      fail "/$name must stay the model's to run, but its frontmatter says disable-model-invocation: $flag"
    fi
  else
    fail "/$name is in neither list of this check: say whether only the CEO types it"
  fi
done
if [ "$count" -gt 0 ]; then
  pass "it walked the $count commands in commands/"
else
  fail "it found no commands/squad-*.md"
fi
# Every command the lists name exists, so that neither list outlives a command it names.
for name in "${ceo_only[@]}" "${invocable[@]}"; do
  [ -f "$root/commands/$name.md" ] || fail "/$name is listed, but there is no commands/$name.md"
done

exit "$status"
