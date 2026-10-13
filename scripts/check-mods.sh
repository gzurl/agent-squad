#!/usr/bin/env bash
# Check the squad's mods (agent-squad #205). mods/ is a marketplace that Claude Code validates,
# and every plugin it lists passes `claude plugin validate` and its own `claude plugin test` cases,
# with at least one test. None calls what a squad mod never calls: the network ($.http), another
# session ($.session.send, $.prompt.submit), a tool, an agent or the model ($.tool.*, $.agent.*,
# $.model.*), or a host command, which can reach the network as well ($.process.*: since
# agent-squad #222 the board reads nothing from GitHub); none hooks tool.check, whose ask auto mode
# settles with no dialog (agent-squad #199). A test that fails is named, with the error under it,
# since the output's last lines may hold only passes: a copy of the first plugin, with one test that
# fails on purpose, proves it (agent-squad #373).
# Claude Code runs with a home of its own, so this check touches neither the user's settings nor
# ~/.claude.json, and with its non-essential traffic off. It needs Claude Code 2.1.287 or later,
# the first with mods.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
mods="$root/mods"

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-mods.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }
# `claude_run <args...>` runs Claude Code in the lab's home, its output on stdout.
claude_run() {
  HOME="$lab" DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude "$@" </dev/null 2>&1
}
# `failures <output>` prints the tests that failed in claude plugin test's output: each test's
# (fail) line and the error block indented under it. The output's last lines alone may hold only
# passes, as the coverage job's did (agent-squad #373).
failures() { awk '/^\(fail\) / { block = 1; print; next } block && /^ / { print; next } { block = 0 }' <<<"$1"; }

# Claude Code, with mods.
if ! command -v claude >/dev/null; then
  echo "check-mods: Claude Code (claude) is not installed; the mods need 2.1.287 or later" >&2
  exit 1
fi
version="$(claude_run --version | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
if [ -z "$version" ] || [ "$(printf '%s\n' 2.1.287 "$version" | sort -V | head -n 1)" != 2.1.287 ]; then
  echo "check-mods: Claude Code ${version:-of an unknown version} has no mods; they need 2.1.287 or later" >&2
  exit 1
fi

# 1. The marketplace validates.
if out="$(claude_run plugin validate "$mods")"; then
  pass "mods/ validates as a marketplace"
else
  fail "mods/ does not validate as a marketplace: $out"
fi

# 1b. The plugins the installer enables by default (mods/default-plugins, agent-squad #206) are
#     plugins of the marketplace.
defaults="$(grep -vE '^[[:space:]]*(#|$)' "$mods/default-plugins" 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
unknown="$(while IFS= read -r name; do
  [ -z "$name" ] || jq -e --arg name "$name" '.plugins | any(.name == $name)' "$mods/.claude-plugin/marketplace.json" >/dev/null 2>&1 \
    || echo "$name"
done <<<"$defaults" | tr '\n' ' ')"
if [ -z "$defaults" ]; then
  fail "mods/default-plugins lists no plugin"
elif [ -n "$unknown" ]; then
  fail "mods/default-plugins names what the marketplace does not list: $unknown"
else
  pass "mods/default-plugins names plugins of the marketplace: $(tr '\n' ' ' <<<"$defaults")"
fi

# 1c. The board tells a pause from the step-away command a prompt carries (agent-squad #222): typed,
#     the prompt starts with it; relayed, the relay names it in parentheses, then a colon and its
#     instruction, "(`/squad-pause`): ". Each step-away command's file names itself that way, and no
#     other, so that the relay it sends, and the command expanded, read as that command alone.
for name in pause pause-all resume resume-all autopilot autopilot-all; do
  file="$root/commands/squad-$name.md"
  # shellcheck disable=SC2016 # the backquotes are the relay's own, not a command
  named="$(grep -oE '\(`/squad-(pause|resume|autopilot)(-all)?`\):' "$file" 2>/dev/null | sort -u | paste -sd ' ' -)"
  if [ "$named" = "(\`/squad-$name\`):" ]; then
    pass "commands/squad-$name.md relays itself as (\`/squad-$name\`):, and no other step-away command"
  else
    fail "commands/squad-$name.md names ${named:-no step-away command} in parentheses with a colon, not (\`/squad-$name\`): alone: the board would not tell its pause"
  fi
done
# 1d. /squad-upgrade's safe point relays /squad-pause the same way (agent-squad #320), so that the
#     board shows DEV and QA as paused until /squad-resume.
# shellcheck disable=SC2016 # the backquotes are the relay's own, not a command
named="$(grep -oE '\(`/squad-(pause|resume|autopilot)(-all)?`\):' "$root/commands/squad-upgrade.md" 2>/dev/null | sort -u | paste -sd ' ' -)"
if [ "$named" = "(\`/squad-pause\`):" ]; then
  pass "commands/squad-upgrade.md relays its safe point as (\`/squad-pause\`):, and no other step-away command"
else
  fail "commands/squad-upgrade.md names ${named:-no step-away command} in parentheses with a colon, not (\`/squad-pause\`): alone: the board would not show the upgrade's pause"
fi

# 2. Each plugin it lists, from the marketplace itself; a marketplace that lists none fails.
sources="$(jq -r '.plugins[].source' "$mods/.claude-plugin/marketplace.json" 2>/dev/null)"
[ -n "$sources" ] || fail "mods/.claude-plugin/marketplace.json lists no plugin"
forbidden='\$\.(http|tool|agent|model|process)\.|\$\.session\.send|\$\.prompt\.submit'
while IFS= read -r source; do
  [ -n "$source" ] || continue
  plugin="mods/${source#./}"
  if ! out="$(claude_run plugin validate "$root/$plugin")"; then
    fail "$plugin does not validate: $out"
    continue
  fi
  pass "$plugin validates"
  # What its hooks module calls and hooks, as the validator reads them.
  calls="$(grep -E '❯ .* calls: ' <<<"$out")"
  hooks="$(grep -E '❯ .* hooks: ' <<<"$out")"
  if [ -z "$calls" ] || [ -z "$hooks" ]; then
    fail "$plugin: the validator listed no calls or no hooks, so they could not be checked: $out"
  elif grep -qE "$forbidden" <<<"$calls"; then
    fail "$plugin calls what a squad mod never calls: $(grep -oE "${forbidden}[a-zA-Z]*" <<<"$calls" | sort -u | tr '\n' ' ')"
  elif grep -qE '(: |, )tool\.check' <<<"$hooks"; then
    fail "$plugin hooks tool.check"
  else
    pass "$plugin calls no network, session, tool, agent, model or host command, and hooks no tool.check"
  fi
  # Its own tests: they all pass, and there is at least one.
  out="$(claude_run plugin test "$root/$plugin")"
  code=$?
  ran="$(grep -oE '^Ran [0-9]+ test' <<<"$out" | grep -oE '[0-9]+')"
  if [ "$code" -eq 0 ] && [ "${ran:-0}" -gt 0 ] && grep -qE '^ 0 fail$' <<<"$out"; then
    pass "$plugin passes its $ran tests"
  else
    named="$(failures "$out")"
    fail "$plugin: claude plugin test exited $code. ${named:+The tests that failed:
$named
}Its last lines:
$(tail -n 10 <<<"$out")"
  fi
done <<<"$sources"

# 3. A test that fails is named, with its error (agent-squad #373): a copy of the first plugin, with
#    one more test, which fails on purpose.
first="mods/$(head -n 1 <<<"$sources" | sed 's|^\./||')"
cp -R "$root/$first" "$lab/broken" && cat > "$lab/broken/tests/zz-fails-on-purpose.test.ts" <<'TEST'
import { expect, test } from 'claude-code/testing'

test('a test that fails on purpose, for check-mods.sh', () => {
  expect('what it got').toBe('what it wanted')
})
TEST
out="$(claude_run plugin test "$lab/broken")"
named="$(failures "$out")"
if [[ "$(head -n 1 <<<"$named")" == "(fail) a test that fails on purpose, for check-mods.sh ["* ]] \
  && grep -qF 'Expected: "what it wanted"' <<<"$named" && [ "$(grep -c '^(fail) ' <<<"$named")" -eq 1 ]; then
  pass "a test that fails is named, with its error, and no other"
else
  fail "a test that fails on purpose in a copy of $first is not named with its error: ${named:-nothing named}"
fi

exit "$status"
