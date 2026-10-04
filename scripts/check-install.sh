#!/usr/bin/env bash
# Check that scripts/squad-install.sh behaves as agent-squad #35 and #36 say, in throw-away
# repositories: a fresh install from a tag's tarball, a second run that changes nothing, a project's
# own settings, pre-push and pre-commit kept working, the pre-push gate refusing a failing check
# through the shim and refusing every push when the playbook is missing, the hook commands warning
# when it is missing, an upgrade that replaces the playbook and nothing else, a failed download that
# leaves it as it was, the steps that need a decision, and --check passing on a good installation
# and failing on the right line for each item broken on purpose, the remote's default branch
# recorded and protected whatever its name (agent-squad #72), and an interrupted --check that leaves
# no sandbox behind (agent-squad #71). GitHub is replaced by a `gh` that serves a tarball built here
# with `git archive`, as GitHub builds it; this script never touches the repository it is run from.
# shellcheck disable=SC2016,SC2317,SC2329 # jq programs use jq variables; the predicates run through check
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
install="$root/scripts/squad-install.sh"
# The files of this checkout as they are, committed or not, ignored files aside.
files="$(cd "$root" && git ls-files -co --exclude-standard \
  | while IFS= read -r f; do [ -e "$f" ] && echo "$f"; done)"
# This script builds repositories of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)
# Nor may the machine's git configuration (a global core.hooksPath, for one) change the outcome.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Install check" GIT_AUTHOR_EMAIL=install@example.com
export GIT_COMMITTER_NAME="Install check" GIT_COMMITTER_EMAIL=install@example.com

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-install.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }
# `check <description> <command...>` passes when the command succeeds.
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}

# Predicates for check. `refused` inverts a command; `contains` and `lacks` look for a fixed
# string in a text, `has_line` for a whole line, `matches_none` for an extended regular expression.
refused() { ! "$@"; }
contains() { grep -qF -- "$2" <<<"$1"; }
has_line() { grep -qxF -- "$2" <<<"$1"; }
lacks() { ! contains "$@"; }
matches_none() { ! grep -Eq -- "$2" <<<"$1"; }
# `prints <string> <command...>` and `prints_nothing <command...>` look at what a command writes
# on stdout, and pass only when it also exits 0.
prints() {
  local string="$1" out
  shift
  out="$("$@")" && contains "$out" "$string"
}
prints_nothing() {
  local out
  out="$("$@")" && [ -z "$out" ]
}
# `absent <dir> <path...>` and `present <dir> <path...>` test paths under a directory.
absent() {
  local dir="$1" path
  shift
  for path; do [ ! -e "$dir/$path" ] || return 1; done
}
present() {
  local dir="$1" path
  shift
  for path; do [ -e "$dir/$path" ] || return 1; done
}
# `has_lines <file> <line...>` passes when each line is in the file, whole.
has_lines() {
  local file="$1" line
  shift
  for line; do grep -qxF -- "$line" "$file" || return 1; done
}
# `jq_holds <program> <file>` passes when the jq program answers true for the file.
jq_holds() { jq -e "$1" "$2" >/dev/null; }

# The items of --check, as it names them.
item_playbook="playbook/ is complete and unmodified"
item_hooks="the five hooks are in .claude/settings.local.json and point at the playbook"
item_ignore=".gitignore ignores .agent-squad/, .claude/settings.local.json and .claude/commands/squad-*.md"
item_command="the squad's commands in .claude/commands/ are the playbook's"
item_shim="the pre-push shim is installed and core.hooksPath is unset"
item_gate="the gate refuses a failing check and lets a passing one through"
item_list=".agent-squad-checks exists and is tracked"
item_worktrees=".agent-squad/worktrees/dev and qa are worktrees of this repository"
item_import="CLAUDE.md links to AGENTS.md, which imports the charter"
item_branch="git knows the remote's default branch, the one the gate protects"
item_lfs="Git LFS's pre-push runs from hooks/pre-push.local"
item_mods="the squad's mods are enabled from the playbook"
# `check_reports [<item>...]` runs --check on the project and passes when the items that fail are
# exactly those given, with exit 1; with none given, when every item passes, with exit 0.
check_reports() {
  local out code failed
  out="$("$install" --check "$project" 2>&1)"
  code=$?
  failed="$(sed -n 's/^check: FAILED  \([^:]*\):.*/\1/p' <<<"$out" | LC_ALL=C sort)"
  if [ $# -eq 0 ]; then
    [ "$code" -eq 0 ] && [ -z "$failed" ] && [ "$(grep -c '^check: ok ' <<<"$out")" -eq 12 ]
  else
    [ "$code" -eq 1 ] && [ "$failed" = "$(printf '%s\n' "$@" | LC_ALL=C sort)" ]
  fi
}

# `check_reason <item> <text>` runs --check on the project and passes when that item fails with a
# reason that contains the text.
check_reason() {
  local out
  out="$("$install" --check "$project" 2>&1)"
  grep -F "check: FAILED  $1: " <<<"$out" | grep -qF -- "$2"
}

# `tree_state <dir>` lists every file under <dir> with a checksum, git metadata and install.log
# aside: two equal listings mean nothing was added, removed or changed.
tree_state() {
  (cd "$1" && find . \( -name .git -o -path ./.agent-squad/install.log \) -prune -o \
    \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r path; do
    if [ -L "$path" ]; then
      echo "link $(readlink "$path") $path"
    else
      echo "$(cksum < "$path") $path"
    fi
  done)
}
same_tree() { [ "$(tree_state "$1")" = "$(tree_state "$2")" ]; }
# `project_state <project>` adds the git hooks, which live in the common git directory.
project_state() { tree_state "$1"; tree_state "$1/.git/hooks"; }
# `log_lines <project>` counts the lines of the install log; `log_ends_with <project> <text>`
# looks at its last one.
log_lines() { wc -l < "$1/.agent-squad/install.log" | tr -d ' '; }
log_ends_with() { tail -1 "$1/.agent-squad/install.log" | grep -q -- " $2\$"; }
# `detached_at <project> <worktree> <branch>`: a linked worktree, detached, at origin/<branch>.
detached_at() {
  [ -f "$2/.git" ] \
    && [ "$(git -C "$2" rev-parse HEAD)" = "$(git -C "$1" rev-parse "origin/$3")" ] \
    && ! git -C "$2" symbolic-ref -q HEAD >/dev/null
}
# `no_leftovers <squad dir>`: no staging directory or tarball survived a run.
no_leftovers() {
  local entry
  for entry in "$1"/playbook.new.* "$1"/tarball.*; do [ ! -e "$entry" ] || return 1; done
}
# `ran <what>` tells whether a recording hook or check wrote <what> since the last `forget`.
ran() { grep -qx -- "$1" "$lab/ran.txt" 2>/dev/null; }
forget() { rm -f "$lab/ran.txt"; }
# `push_from <dir> <branch>` makes a commit there and pushes it, quietly.
push_from() {
  echo "$2" >> "$1/pushed.txt"
  git -C "$1" add -A && git -C "$1" commit -qm "$2" \
    && git -C "$1" push -q origin "HEAD:refs/heads/$2" 2>/dev/null
}

# GitHub, as far as the installer is concerned: `gh api repos/<upstream>/tarball/<tag>` answers
# with the file named by GH_TARBALL when the tag is GH_TAG; anything else fails.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
if [ "${1:-}" = api ] && [ "${2:-}" = "repos/gzurl/agent-squad/tarball/${GH_TAG:-}" ]; then
  exec cat "$GH_TARBALL"
fi
exit 1
GH
chmod +x "$lab/bin/gh"
# Claude Code, as far as the installer is concerned: `claude --version` answers CLAUDE_STUB_VERSION,
# 2.1.289 when it is unset, and nothing when it is "none"; every call is recorded in
# claude-calls.txt.
cat > "$lab/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/../claude-calls.txt"
[ "${CLAUDE_STUB_VERSION:-}" != none ] || exit 1
echo "${CLAUDE_STUB_VERSION:-2.1.289} (Claude Code)"
CLAUDE
chmod +x "$lab/bin/claude"
export PATH="$lab/bin:$PATH"

# The upstream: this checkout's files, committed in a repository of their own, with a template of
# AGENTS.md whose Squad section this test knows. Its tarball is what GitHub would serve for a tag.
upstream="$lab/upstream"
mkdir -p "$upstream"
printf '%s\n' "$files" | (cd "$root" && tar -cf - -T -) | tar -xf - -C "$upstream" || exit 2
cat > "$upstream/templates/AGENTS.md" <<'TEMPLATE'
# AGENTS.md — <project>

## Squad
The squad section this test expects, first line.

@.agent-squad/playbook/SQUAD.md

## Language
Not part of the section.
TEMPLATE
git -C "$upstream" init -q -b main && git -C "$upstream" add -A \
  && git -C "$upstream" commit -qm upstream || exit 2
git -C "$upstream" archive --prefix=gzurl-agent-squad-0123456/ HEAD | gzip > "$lab/va.tgz" || exit 2
mkdir -p "$lab/va" && tar -xzf "$lab/va.tgz" -C "$lab/va" --strip-components=1 || exit 2
# The tags are named after the version their tree's charter carries, vN for Version N, as real tags
# are: --check compares that version with the last line of install.log.
version_a="$(grep -o '^> \*\*Version:\*\* [0-9]*' "$lab/va/SQUAD.md" | grep -o '[0-9]*$')"
[ -n "$version_a" ] || exit 2
tag_a="v$version_a" tag_b="v$((version_a + 1))"
export GH_TAG="$tag_a" GH_TARBALL="$lab/va.tgz"
# Tree B, the next version: one file changed (its charter, whose version goes up), one removed, one
# added.
mkdir -p "$lab/vb" && cp -pR "$lab/va/." "$lab/vb/" || exit 2
sed -i.orig "s/^> \*\*Version:\*\* $version_a /> **Version:** ${tag_b#v} /" "$lab/vb/SQUAD.md" \
  && rm "$lab/vb/SQUAD.md.orig" && grep -q "^> \*\*Version:\*\* ${tag_b#v} " "$lab/vb/SQUAD.md" || exit 2
echo "Changed in vb." >> "$lab/vb/SQUAD.md"
rm "$lab/vb/BOOTSTRAP.md"
echo "Added in vb." > "$lab/vb/ADDED-IN-VB.md"

# `new_project <name>` makes a project with a remote, whose main branch has a checks list with a
# recording check and a PR template of its own, and prints its main checkout's path.
new_project() {
  local seed="$lab/$1-seed" remote="$lab/$1.git"
  git init -q --bare -b main "$remote" && git init -q -b main "$seed" || return 1
  printf '#!/bin/sh\necho check >> "%s/ran.txt"\n' "$lab" > "$seed/records.sh"
  chmod +x "$seed/records.sh"
  printf '# the sandbox checks\n./records.sh\n' > "$seed/.agent-squad-checks"
  mkdir -p "$seed/.github" && echo "The project's own PR template." > "$seed/.github/PULL_REQUEST_TEMPLATE.md"
  git -C "$seed" add -A && git -C "$seed" commit -qm seed \
    && git -C "$seed" push -q "$remote" main || return 1
  git clone -q "$remote" "$lab/$1" && echo "$lab/$1"
}

# A project that already has its own local settings, pre-push and pre-commit. Its settings carry
# an entry of an older squad, which the installer replaces.
project="$(new_project project)" || exit 2
mkdir -p "$project/.claude"
cat > "$project/.claude/settings.local.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "echo own hook" }] }
    ],
    "PreCompact": [
      { "matcher": "manual", "hooks": [{ "type": "command", "command": "scripts/squad-handoff.sh save" }] }
    ]
  }
}
JSON
hooks="$project/.git/hooks"
printf '#!/bin/sh\necho local >> "%s/ran.txt"\n[ ! -e "%s/refuse-local" ]\n' "$lab" "$lab" > "$hooks/pre-push"
printf '#!/bin/sh\necho pre-commit >> "%s/ran.txt"\n' "$lab" > "$hooks/pre-commit"
chmod +x "$hooks/pre-push" "$hooks/pre-commit"
cp "$hooks/pre-push" "$lab/project-pre-push"
squad="$project/.agent-squad"
dev="$squad/worktrees/dev"
settings="$project/.claude/settings.local.json"

# 1. A fresh install from the tag's tarball.
out="$("$install" "$project" "$tag_a" 2>&1)"
code=$?
check "a fresh install exits 0" [ "$code" -eq 0 ]
check "the playbook is the tag's tree, file for file" same_tree "$squad/playbook" "$lab/va"
check "the playbook leaves out agent-squad's own AGENTS.md, CLAUDE.md, checks, CI and tests" \
  absent "$squad/playbook" AGENTS.md CLAUDE.md .agent-squad-checks .github/workflows \
  scripts/check-install.sh
check "install.log has one line" [ "$(log_lines "$project")" -eq 1 ]
check "which says none -> $tag_a" log_ends_with "$project" "none -> $tag_a"
check ".gitignore has .agent-squad/, .claude/settings.local.json and the command" \
  has_lines "$project/.gitignore" ".agent-squad/" ".claude/settings.local.json" \
  ".claude/commands/squad-*.md"
# `same_commands <project>` passes when each of the playbook's commands is in .claude/commands/, byte
# for byte, and there is at least one: it walks the playbook's own list, not one kept here.
same_commands() {
  local file count=0
  for file in "$1/.agent-squad/playbook/commands"/squad-*.md; do
    [ -f "$file" ] || return 1
    cmp -s "$file" "$1/.claude/commands/$(basename "$file")" || return 1
    count=$((count + 1))
  done
  [ "$count" -ge 11 ]
}
check "the squad's eleven commands are in .claude/commands/, as the playbook has them" same_commands "$project"
check "the missing issue template was created from the playbook" \
  cmp -s "$squad/playbook/.github/ISSUE_TEMPLATE/task.md" "$project/.github/ISSUE_TEMPLATE/task.md"
check "the project's own PR template was kept" \
  has_lines "$project/.github/PULL_REQUEST_TEMPLATE.md" "The project's own PR template."
for agent in dev qa; do
  check "worktrees/$agent is a linked worktree detached at origin/main" \
    detached_at "$project" "$squad/worktrees/$agent" main
done
check "the Squad section of the playbook's templates/AGENTS.md is printed" \
  contains "$out" "The squad section this test expects, first line."
check "unindented, so that the import works once pasted" has_line "$out" "@.agent-squad/playbook/SQUAD.md"
check "between markers" has_line "$out" "----- begin Squad section -----"
check "and nothing after the section" lacks "$out" "Not part of the section."
check "--check after a fresh install fails only on what is left by hand, AGENTS.md" check_reports "$item_import"

# 2. The project's local settings are kept; only the entries that run squad-handoff.sh change.
ours='[.hooks[][] | select(any(.hooks[]; .command | contains("squad-handoff.sh"))) | .matcher]'
check "settings.local.json keeps the project's permissions" \
  jq_holds '.permissions.allow == ["Bash(ls:*)"]' "$settings"
check "and the project's own hook" \
  jq_holds '.hooks.PreToolUse[0].hooks[0].command == "echo own hook"' "$settings"
check "and has the five squad hooks once each, the older entry replaced" \
  jq_holds "$ours == [\"manual\", \"auto\", \"compact\", \"startup\", \"resume\"]" "$settings"

# 3. A second run changes nothing but the log, which gains one line.
before="$(project_state "$project")"
lines_before="$(log_lines "$project")"
out="$("$install" "$project" "$tag_a" 2>&1)"
code=$?
check "a second run exits 0" [ "$code" -eq 0 ]
check "a second run changes no file, the git hooks included" [ "$before" = "$(project_state "$project")" ]
check "a second run adds one line to install.log" [ "$(log_lines "$project")" -eq $((lines_before + 1)) ]
check "which says $tag_a -> $tag_a" log_ends_with "$project" "$tag_a -> $tag_a"
check "a second run reports every step as already done" \
  matches_none "$out" "^install: [^ ]+ +(installed|added|wrote|rewrote|created|recorded|kept the project)"

# 4. The project's pre-push is chained: kept as pre-push.local, run first, and still able to refuse.
check "the project's pre-push is kept as pre-push.local" cmp -s "$lab/project-pre-push" "$hooks/pre-push.local"
forget
check "a push from worktrees/dev goes through" push_from "$dev" first
check "and ran the project's pre-push" ran local
check "and the squad's checks" ran check
touch "$lab/refuse-local"
check "the project's pre-push still refuses a push" refused push_from "$dev" refused-by-local
rm -f "$lab/refuse-local"
# The project's other hooks are left alone.
check "the project's pre-commit still runs" ran pre-commit

# 5. Through the shim, the gate refuses a failing check.
printf 'false\n' > "$dev/.agent-squad-checks"
check "a failing check refuses the push through the shim" refused push_from "$dev" failing-check
printf './records.sh\n' > "$dev/.agent-squad-checks"

# 6. Without the playbook, the shim refuses every push and the hooks warn the session.
# `run_hook <matcher>` runs the command installed for that matcher as Claude Code would.
run_hook() {
  local program command
  program='[.hooks[][] | select(.matcher == $m) | .hooks[] | .command | select(contains("squad-handoff.sh"))][0]'
  command="$(jq -r --arg m "$1" "$program" "$settings")"
  (cd "$project" && echo '{"session_id":"x"}' | CLAUDE_PROJECT_DIR="$project" sh -c "$command")
}
mv "$squad/playbook" "$lab/playbook-aside"
check "the shim refuses a push when the playbook is missing" refused push_from "$dev" no-playbook
for matcher in startup compact resume; do
  check "the $matcher hook warns that the charter is not installed" \
    prints "charter is not installed" run_hook "$matcher"
done
check "the save hook does nothing and exits 0" prints_nothing run_hook manual
mv "$lab/playbook-aside" "$squad/playbook"
check "with the playbook back, the startup hook prints nothing" prints_nothing run_hook startup
check "and the compact hook re-orients the session" prints "Context was compacted" run_hook compact
check "and the resume hook says where the shell is" prints "Squad: this session was resumed" run_hook resume

# 7. An upgrade replaces the playbook whole and leaves the rest of .agent-squad/ alone. It is run
#    as the README says, by the installed installer, which replaces the directory it runs from.
mkdir -p "$squad/handoff" "$squad/evidence/7"
echo snapshot > "$squad/handoff/x.md"
echo evidence > "$squad/evidence/7/screen.txt"
echo work > "$dev/work-in-progress.txt"
runtime_state() { tree_state "$squad/worktrees"; tree_state "$squad/handoff"; tree_state "$squad/evidence"; }
runtime_before="$(runtime_state)"
out="$("$squad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$project" "$tag_b" 2>&1)"
code=$?
check "an upgrade exits 0" [ "$code" -eq 0 ]
check "the playbook is now vb, file for file (one changed, one removed, one added)" \
  same_tree "$squad/playbook" "$lab/vb"
check "worktrees/, handoff/ and evidence/ are untouched" [ "$runtime_before" = "$(runtime_state)" ]
check "install.log ends with $tag_a -> $tag_b" log_ends_with "$project" "$tag_a -> $tag_b"

# 7b. --check's version item compares the playbook's version with the last line of install.log, the
#     line an upgrade cut short never writes (#96).
# `version_ok` passes when --check reports the version item as ok, whatever the other items say.
version_ok() {
  local out
  out="$("$install" --check "$project" 2>&1)"
  grep -qF "check: ok      installed version ${tag_b#v} (install.log: " <<<"$out"
}
check "with install.log's last line naming the installed version, the version item passes" version_ok
item_version="installed version ${tag_b#v}"
cp "$squad/install.log" "$lab/install.log.kept"
sed -i.orig '$d' "$squad/install.log" && rm "$squad/install.log.orig"
check "a log whose last line names an older tag fails the version item, saying which" \
  check_reason "$item_version" "install.log's last line records $tag_a, not $tag_b"
: > "$squad/install.log"
check "an empty log fails it, saying so" check_reason "$item_version" "install.log records no install"
rm "$squad/install.log"
check "and so does a missing one" check_reason "$item_version" "install.log records no install"
cp "$lab/install.log.kept" "$squad/install.log"
check "with the log back, the version item passes again" version_ok

# 7c. An upgrade whose output loses its reader, as when it is piped into head, still completes:
#     every step runs, install.log records it, and the exit status is what it would be (#96). The
#     output goes to a FIFO whose only reader is closed before the installer starts, so its first
#     write fails, every time. The shim and a worktree are removed first, so that the upgrade's
#     last steps have something to do.
target="$(new_project no-reader)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
rm "$target/.git/hooks/pre-push"
git -C "$target" worktree remove --force "$target/.agent-squad/worktrees/qa" || exit 2
mkfifo "$lab/no-reader.fifo" || exit 2
exec 5<>"$lab/no-reader.fifo"
exec 6>"$lab/no-reader.fifo"
exec 5<&-
"$install" --source "$lab/vb" "$target" "$tag_b" >&6 2>&6
code=$?
exec 6>&-
check "an upgrade whose output has no reader exits 0, as it would with one" [ "$code" -eq 0 ]
check "and records itself in install.log" log_ends_with "$target" "$tag_a -> $tag_b"
check "and runs its steps after the log: the shim and the QA worktree are back" \
  present "$target" .git/hooks/pre-push .agent-squad/worktrees/qa/.git

# 7d. The installer owns the /squad-save-state command as it owns the hooks: a changed one is
#     rewritten from the playbook on the next install (#100).
target="$(new_project command-rewrite)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
echo "An edit." >> "$target/.claude/commands/squad-save-state.md"
out="$("$install" "$target" "$tag_a" 2>&1)"
check "a changed /squad-save-state is rewritten on the next install, saying so" \
  contains "$out" "install: command    rewrote /squad-save-state into .claude/commands/"
check "and is the playbook's again" cmp -s "$target/.agent-squad/playbook/commands/squad-save-state.md" \
  "$target/.claude/commands/squad-save-state.md"

# 7e. A project that tracks a file of its own at that path keeps it: the install leaves it, says so
#     as a step marked NOT and exits 1, and --check fails the command item (#104).
target="$(new_project tracked-command)" || exit 2
mkdir -p "$target/.claude/commands" \
  && echo "The project's own command." > "$target/.claude/commands/squad-save-state.md" \
  && git -C "$target" add .claude/commands/squad-save-state.md \
  && git -C "$target" commit -qm "a command of the project's own" || exit 2
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "a tracked command of the project's own makes the install exit 1" [ "$code" -eq 1 ]
# Both messages say which way out fits which case: untracking a command of the project's own would
# have the next install overwrite it.
advice="if it is a command of the project's own, rename it; if it is the squad's command committed by mistake, untrack it with git rm --cached"
check "and the install says the file is the project's, and which way out fits which case" \
  contains "$out" "install: command    NOT INSTALLED: .claude/commands/squad-save-state.md is the project's own file, tracked by git; it is left as it is: $advice; then run again"
check "and leaves it byte for byte" \
  [ "$(cat "$target/.claude/commands/squad-save-state.md")" = "The project's own command." ]
out="$("$install" --check "$target" 2>&1)"
check "and --check fails the command item, saying that the project owns the file and which way out fits" \
  contains "$out" "check: FAILED  $item_command: .claude/commands/squad-save-state.md is tracked by git, so the project owns it: $advice; then install again"

# 7f. A project upgraded from v24 or v25 has one line for /squad-save-state: the install appends the
#     one rule for all the commands once, keeps that line, and a second run adds nothing (#101).
target="$(new_project one-rule)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
sed -i.orig 's|^\.claude/commands/squad-\*\.md$|.claude/commands/squad-save-state.md|' "$target/.gitignore" \
  && rm "$target/.gitignore.orig" || exit 2
out="$("$install" "$target" "$tag_a" 2>&1)"
check "with only v24's line, the install appends the commands' rule, saying so" \
  contains "$out" "install: .gitignore added .claude/commands/squad-*.md"
check "and keeps v24's line, with the rule once" \
  bash -c '[ "$(grep -cxF ".claude/commands/squad-*.md" "$1")" -eq 1 ] && grep -qxF .claude/commands/squad-save-state.md "$1"' _ "$target/.gitignore"
out="$("$install" "$target" "$tag_a" 2>&1)"
check "and a second run says the rule is already there" \
  contains "$out" "install: .gitignore .claude/commands/squad-*.md is already ignored"

# 7g. Git LFS (#121). Its own pre-push hook cannot go where the shim is, so a project that routes
#     files through LFS runs it from hooks/pre-push.local, which the shim runs first. --check shows
#     an item for it only when a .gitattributes of the project has filter=lfs: failing without an
#     executable pre-push.local that runs git lfs pre-push, passing with one. LFS's own hook, there
#     before the install, is kept as pre-push.local and passes as it is. No git-lfs is needed: the
#     item reads files.
lfs_hook='#!/bin/sh
command -v git-lfs >/dev/null 2>&1 || { echo "git-lfs was not found on your path" >&2; exit 2; }
git lfs pre-push "$@"'
# `lfs_line <project>` prints --check's line for the LFS item, or nothing when there is none.
lfs_line() { "$install" --check "$1" 2>&1 | grep -F "$item_lfs" || true; }
target="$(new_project lfs)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
check "without LFS, --check shows no LFS item" [ -z "$(lfs_line "$target")" ]
printf '# *.psd filter=lfs diff=lfs merge=lfs -text\n*.txt text\n' > "$target/.gitattributes"
check "nor with filter=lfs only in a comment of .gitattributes" [ -z "$(lfs_line "$target")" ]
printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > "$target/.gitattributes"
git -C "$target" add .gitattributes && git -C "$target" commit -qm "LFS for binaries" || exit 2
local_hook="$target/.git/hooks/pre-push.local"
# The installer names the hook by its resolved path, as it names the shim.
check "with LFS and no pre-push.local, the LFS item fails and says what to write" \
  contains "$(lfs_line "$target")" "check: FAILED  $item_lfs: the project uses Git LFS (.gitattributes has filter=lfs), and there is no executable $(cd "$target" && pwd -P)/.git/hooks/pre-push.local; write one that runs git lfs pre-push \"\$@\""
printf '%s\n' "$lfs_hook" > "$local_hook"
check "with one that is not executable, it still fails" \
  contains "$(lfs_line "$target")" "check: FAILED  $item_lfs: the project uses Git LFS"
printf '#!/bin/sh\necho "a hook of the project'"'"'s own"\n' > "$local_hook" && chmod +x "$local_hook"
check "with an executable one that does not run git lfs pre-push, it fails, saying so" \
  contains "$(lfs_line "$target")" "does not run git lfs pre-push; add git lfs pre-push \"\$@\" to it"
printf '%s\n' "$lfs_hook" > "$local_hook"
check "with LFS's own hook there, the LFS item passes" [ "$(lfs_line "$target")" = "check: ok      $item_lfs" ]
target="$(new_project lfs-nested)" || exit 2
mkdir -p "$target/assets" && printf '*.png filter=lfs diff=lfs merge=lfs -text\n' > "$target/assets/.gitattributes"
git -C "$target" add assets/.gitattributes && git -C "$target" commit -qm "LFS for images" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
check "a tracked .gitattributes below the root counts too" \
  contains "$(lfs_line "$target")" "check: FAILED  $item_lfs"
target="$(new_project lfs-before)" || exit 2
printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > "$target/.gitattributes"
git -C "$target" add .gitattributes && git -C "$target" commit -qm "LFS for binaries" || exit 2
printf '%s\n' "$lfs_hook" > "$target/.git/hooks/pre-push" && chmod +x "$target/.git/hooks/pre-push"
"$install" "$target" "$tag_a" >/dev/null 2>&1
check "LFS's hook, there before the install, is kept as pre-push.local and passes the item" \
  [ "$(lfs_line "$target")" = "check: ok      $item_lfs" ]

# 8. A failed download or an incomplete tree leaves the installed playbook as it was.
echo "not a tarball" > "$lab/broken.tgz"
out="$(GH_TAG=vc GH_TARBALL="$lab/broken.tgz" "$install" "$project" vc 2>&1)"
code=$?
check "a download that is not a tarball exits 2" [ "$code" -eq 2 ]
check "and leaves the playbook as it was" same_tree "$squad/playbook" "$lab/vb"
check "with nothing left behind" no_leftovers "$squad"
# A tree without one of the files the installation relies on; without scripts/squad-install.sh,
# it is a tag older than the installer, such as v14, which would install without working. Every
# command the tree has counts too, walked from the tree: a command the installer does not require
# fails here.
commands_in_tree="$(cd "$lab/vb" && ls commands/squad-*.md)"
[ "$(wc -l <<<"$commands_in_tree")" -ge 8 ] || exit 2
for missing in SQUAD.md scripts/squad-install.sh templates/AGENTS.md $commands_in_tree; do
  rm -rf "$lab/incomplete" && mkdir -p "$lab/incomplete" && cp -pR "$lab/vb/." "$lab/incomplete/"
  rm "$lab/incomplete/$missing"
  out="$("$install" --source "$lab/incomplete" "$project" vd 2>&1)"
  code=$?
  check "a tree without $missing exits 2, saying so" \
    bash -c '[ "$1" -eq 2 ] && grep -qF "has no $2" <<<"$3"' _ "$code" "$missing" "$out"
  check "and leaves the playbook as it was" same_tree "$squad/playbook" "$lab/vb"
done
check "and no failure wrote to install.log" matches_none "$(cat "$squad/install.log")" " -> (vc|vd)$"

# 9. With core.hooksPath set, the shim is not installed, the reason is printed and the exit is 1.
other="$(new_project other)" || exit 2
git -C "$other" config core.hooksPath .githooks
out="$("$install" "$other" "$tag_a" 2>&1)"
code=$?
check "with core.hooksPath set the installer exits 1" [ "$code" -eq 1 ]
check "and says why" contains "$out" "pre-push   NOT INSTALLED: core.hooksPath is set"
check "and writes no shim" absent "$other" .git/hooks/pre-push
check "while the other steps are done" present "$other" .agent-squad/playbook/SQUAD.md

# 10. Only the main checkout is accepted.
out="$("$install" "$dev" "$tag_a" 2>&1)"
code=$?
check "a linked worktree is refused with exit 2" [ "$code" -eq 2 ]
check "and nothing is created in it" absent "$dev" .agent-squad

# 11. Blank settings count as none; settings that are not one JSON object are left as they are.
five_hooks="$ours == [\"manual\", \"auto\", \"compact\", \"startup\", \"resume\"]"
for kind in empty blank; do
  target="$(new_project "settings-$kind")" || exit 2
  mkdir -p "$target/.claude"
  case "$kind" in
    empty) : > "$target/.claude/settings.local.json" ;;
    blank) printf ' \n\t\n' > "$target/.claude/settings.local.json" ;;
  esac
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "an $kind settings.local.json exits 0" [ "$code" -eq 0 ]
  check "and gets the five hooks" jq_holds "$five_hooks" "$target/.claude/settings.local.json"
done
for kind in not-json two-objects; do
  target="$(new_project "settings-$kind")" || exit 2
  mkdir -p "$target/.claude"
  case "$kind" in
    not-json) echo '{"permissions": ' > "$target/.claude/settings.local.json" ;;
    two-objects) echo '{} {}' > "$target/.claude/settings.local.json" ;;
  esac
  cp -p "$target/.claude/settings.local.json" "$lab/settings-before"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "a settings.local.json that is $kind exits 1" [ "$code" -eq 1 ]
  check "and says why" contains "$out" "hooks      NOT INSTALLED: .claude/settings.local.json is not one JSON object"
  check "and is left byte for byte" cmp -s "$lab/settings-before" "$target/.claude/settings.local.json"
done

# 12. A negation in the project's .gitignore is not taken for an ignore rule.
target="$(new_project negations)" || exit 2
printf '.agent-squad/\n!.agent-squad/\n*.json\n!.claude/settings.local.json\n' > "$target/.gitignore"
out="$("$install" "$target" "$tag_a" 2>&1)"
check "a negated .agent-squad/ gets its ignore line, and is ignored in fact" \
  git -C "$target" check-ignore -q --no-index .agent-squad
check "a negated .claude/settings.local.json too" \
  git -C "$target" check-ignore -q --no-index .claude/settings.local.json
# A negation in a nested .gitignore outranks the root one: appending cannot help.
target="$(new_project nested-negation)" || exit 2
mkdir -p "$target/.claude" && echo '!settings.local.json' > "$target/.claude/.gitignore"
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "a nested negation of settings.local.json exits 1" [ "$code" -eq 1 ]
check "and says which rule wins" contains "$out" ".gitignore NOT IGNORED: .claude/settings.local.json would lose to .claude/.gitignore:1:!settings.local.json"
check "and appends nothing" refused grep -qxF .claude/settings.local.json "$target/.gitignore"
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "nor on a second run, which says the same" \
  bash -c '[ "$1" -eq 1 ] && ! grep -qxF .claude/settings.local.json "$2" && grep -qF "NOT IGNORED" <<<"$3"' \
  _ "$code" "$target/.gitignore" "$out"

# 13. The other steps that need a decision: nothing is overwritten, the step says NOT, the exit is 1.
target="$(new_project two-hooks)" || exit 2
printf '#!/bin/sh\necho the project pre-push\n' > "$target/.git/hooks/pre-push"
printf '#!/bin/sh\necho the project pre-push.local\n' > "$target/.git/hooks/pre-push.local"
chmod +x "$target/.git/hooks/pre-push" "$target/.git/hooks/pre-push.local"
hooks_before="$(tree_state "$target/.git/hooks")"
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "with pre-push and pre-push.local both the project's, the installer exits 1" [ "$code" -eq 1 ]
check "and says why" contains "$out" "pre-push   NOT INSTALLED: pre-push and pre-push.local both exist"
check "and leaves the git hooks as they were" [ "$hooks_before" = "$(tree_state "$target/.git/hooks")" ]
target="$(new_project worktree-hooks-path)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
git -C "$target" config extensions.worktreeConfig true
git -C "$target/.agent-squad/worktrees/dev" config --worktree core.hooksPath .githooks
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "core.hooksPath in a worktree's own configuration makes the installer exit 1" [ "$code" -eq 1 ]
check "and says where" contains "$out" "pre-push   NOT INSTALLED: core.hooksPath is set ('.githooks' in .agent-squad/worktrees/dev)"
target="$lab/no-origin"
git init -q -b main "$target" || exit 2
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "without origin/main the installer exits 1" [ "$code" -eq 1 ]
check "and says the worktrees were not created" contains "$out" "worktrees  NOT CREATED: .agent-squad/worktrees/dev"
check "and creates none" absent "$target" .agent-squad/worktrees/dev .agent-squad/worktrees/qa

# 14. --check passes on a complete installation, changes nothing, and fails on the right line for
#     each item broken on purpose; each breakage is undone before the next.
printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$project/AGENTS.md"
ln -s AGENTS.md "$project/CLAUDE.md"
before="$(project_state "$project")$(cat "$squad/install.log")"
check "--check passes on a complete installation, twelve items ok" check_reports
check "and changes nothing, the install log included" \
  [ "$before" = "$(project_state "$project")$(cat "$squad/install.log")" ]
# `broken <file>` keeps a copy of a file about to be broken; `mended <file>` puts it back.
broken() { cp -p "$1" "$lab/mend.me"; }
mended() { cp -p "$lab/mend.me" "$1"; }

broken "$squad/playbook/README.md"
echo "An edit." >> "$squad/playbook/README.md"
check "a modified playbook file fails the playbook item" check_reports "$item_playbook"
mended "$squad/playbook/README.md"

broken "$settings"
jq '.hooks.SessionStart |= map(select(.matcher != "startup"))' "$lab/mend.me" > "$settings"
check "a missing hook fails the hooks item" check_reports "$item_hooks"
mended "$settings"
broken "$settings"
jq '.hooks.SessionStart |= map(select(.matcher != "resume"))' "$lab/mend.me" > "$settings"
check "a missing resume hook fails the hooks item" check_reports "$item_hooks"
check "naming it" contains "$("$install" --check "$project" 2>&1)" "$item_hooks: missing: resume; unexpected: none"
mended "$settings"

broken "$project/.gitignore"
grep -vx ".claude/settings.local.json" "$lab/mend.me" > "$project/.gitignore"
check "a missing ignore line fails the .gitignore item" check_reports "$item_ignore"
mended "$project/.gitignore"

broken "$project/.gitignore"
grep -vx ".claude/commands/squad-\*.md" "$lab/mend.me" > "$project/.gitignore"
check "a missing ignore rule for the commands fails the .gitignore item" check_reports "$item_ignore"
mended "$project/.gitignore"

broken "$project/.gitignore"
echo '!.claude/commands/squad-autopilot.md' >> "$project/.gitignore"
check "a negation of one command fails the .gitignore item" check_reports "$item_ignore"
mended "$project/.gitignore"

for command_file in "$squad/playbook/commands"/squad-*.md; do
  name="$(basename "$command_file" .md)"
  command_file="$project/.claude/commands/$name.md"
  broken "$command_file"
  echo "An edit." >> "$command_file"
  check "a modified /$name fails the commands item" check_reports "$item_command"
  rm "$command_file"
  check "a missing /$name fails it too" check_reports "$item_command"
  mended "$command_file"
done

broken "$project/.gitignore"
echo '!.agent-squad/' >> "$project/.gitignore"
check "a negation after the ignore line fails the .gitignore item" check_reports "$item_ignore"
mended "$project/.gitignore"

git -C "$project" config core.hooksPath .githooks
check "a set core.hooksPath fails the shim item" check_reports "$item_shim"
git -C "$project" config --unset core.hooksPath

git -C "$project" config extensions.worktreeConfig true
git -C "$dev" config --worktree core.hooksPath .githooks
check "core.hooksPath in a worktree's own configuration fails the shim item" check_reports "$item_shim"
git -C "$dev" config --worktree --unset core.hooksPath
git -C "$project" config --unset extensions.worktreeConfig

# A machine whose git configuration signs every commit with a gpg that fails, and forbids local
# pushes: the gate's sandbox must not see it.
printf '[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = false\n[protocol "file"]\n\tallow = never\n' > "$lab/hostile.gitconfig"
with_hostile_git() { (export GIT_CONFIG_GLOBAL="$lab/hostile.gitconfig"; "$@"); }
check "a hostile global git configuration does not fail the gate item" with_hostile_git check_reports

mv "$squad/playbook" "$lab/playbook-aside"
check "without the playbook the gate item says so, and does not blame the gate" \
  check_reason "$item_gate" "the playbook has no executable .githooks/pre-push to test"
mv "$lab/playbook-aside" "$squad/playbook"

# Interrupted while the gate's sandbox exists, --check leaves no sandbox and touches nothing else in
# TMPDIR (#71). The run gets its own process group, which is what a Ctrl-C signals, and is
# interrupted at a state, not after a delay: as soon as the sandbox's directory exists, and once it
# holds its repositories. Two wrappers make both states last: a mktemp that waits between creating a
# directory and printing its name (the window in which a cleanup that learns the name from mktemp
# has nothing to remove, or removes TMPDIR itself), and a git whose push waits.
real_mktemp="$(command -v mktemp)" real_git="$(command -v git)"
mkdir -p "$lab/slow"
printf '#!/usr/bin/env bash\ndir="$(%q "$@")" || exit\nsleep 1\necho "$dir"\n' "$real_mktemp" > "$lab/slow/mktemp"
printf '#!/usr/bin/env bash\n[ "${3:-}" = push ] && sleep 1\nexec %q "$@"\n' "$real_git" > "$lab/slow/git"
chmod +x "$lab/slow/mktemp" "$lab/slow/git"
# `sandboxes` lists the gate's sandboxes in the test's TMPDIR.
sandboxes() { find "$lab/tmp" -maxdepth 1 -name 'squad-check.*' 2>/dev/null; }
# `interrupted_at <created|populated>` runs --check, interrupts it at that state, and passes when the
# run was really interrupted (exit 130), no sandbox is left, and the file that is not the
# installer's is still there.
interrupted_at() {
  local pid code sandbox tries=0
  rm -rf "$lab/tmp" && mkdir -p "$lab/tmp" && echo "not the installer's" > "$lab/tmp/keep-me"
  set -m
  PATH="$lab/slow:$PATH" TMPDIR="$lab/tmp" "$install" --check "$project" >/dev/null 2>&1 &
  pid=$!
  set +m
  until sandbox="$(sandboxes | head -1)" && [ -n "$sandbox" ] \
    && { [ "$1" = created ] || [ -d "$sandbox/remote.git" ]; }; do
    tries=$((tries + 1))
    if [ "$tries" -ge 2000 ] || ! kill -0 "$pid" 2>/dev/null; then
      kill -INT -- "-$pid" 2>/dev/null
      return 1
    fi
    sleep 0.005
  done
  kill -INT -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  code=$?
  # What is left of the run gets a moment to finish its cleanup.
  tries=0
  while [ -n "$(sandboxes)" ] && [ "$tries" -lt 100 ]; do sleep 0.05; tries=$((tries + 1)); done
  [ "$code" -eq 130 ] && [ -z "$(sandboxes)" ] && [ -f "$lab/tmp/keep-me" ]
}
check "an --check interrupted as soon as its sandbox exists leaves none, and nothing else goes" \
  interrupted_at created
check "an --check interrupted once its sandbox holds its repositories leaves none, and nothing else goes" \
  interrupted_at populated

broken "$squad/playbook/scripts/squad-checks.sh"
printf '#!/bin/sh\nexit 0\n' > "$squad/playbook/scripts/squad-checks.sh"
check "a gate that passes a failing check fails the gate item (and the playbook one)" \
  check_reports "$item_gate" "$item_playbook"
mended "$squad/playbook/scripts/squad-checks.sh"

chmod -x "$squad/playbook/scripts/squad-checks.sh"
check "a gate that refuses every push fails the gate item (and the playbook one)" \
  check_reports "$item_gate" "$item_playbook"
chmod +x "$squad/playbook/scripts/squad-checks.sh"

mv "$project/.agent-squad-checks" "$lab/list-aside"
check "a missing list fails the list item" check_reports "$item_list"
mv "$lab/list-aside" "$project/.agent-squad-checks"

broken "$project/.agent-squad-checks"
for content in '' '# only a comment' '  # an indented comment' '   ' $'# a CRLF comment\r\n\r'; do
  printf '%s\n' "$content" > "$project/.agent-squad-checks"
  # Shown with its carriage returns and newlines escaped, so that the report stays one line each.
  shown="${content//$'\r'/\\r}"
  check "a list with no command ('${shown//$'\n'/\\n}') fails the list item" check_reports "$item_list"
done
printf '# the sandbox checks\r\n./records.sh\r\n' > "$project/.agent-squad-checks"
check "a CRLF list with a command passes the list item" check_reports
mended "$project/.agent-squad-checks"

git -C "$project" symbolic-ref --delete refs/remotes/origin/HEAD
check "a missing origin/HEAD fails the default-branch item" check_reports "$item_branch"
git -C "$project" remote set-head origin main >/dev/null

mv "$squad/worktrees/qa" "$lab/qa-aside"
check "a missing worktree fails the worktrees item" check_reports "$item_worktrees"
mv "$lab/qa-aside" "$squad/worktrees/qa"

broken "$project/AGENTS.md"
printf '# AGENTS.md\n' > "$project/AGENTS.md"
check "a missing import fails the import item" check_reports "$item_import"
# Imports that Claude Code does not evaluate: in a fence, indented, inline, commented out, or of
# another file.
import="@.agent-squad/playbook/SQUAD.md"
for inert in '```\n'"$import"'\n```' '~~~\n'"$import"'\n~~~' "    $import" "Read \`$import\`." \
  "<!-- $import -->" "<!--\n$import\n-->" "$import.bak"; do
  printf '# AGENTS.md\n\n%b\n' "$inert" > "$project/AGENTS.md"
  check "an import that is not evaluated fails the import item: $(head -c 24 <<<"$inert" | tr '\n' ' ')" \
    check_reports "$item_import"
done
printf '# AGENTS.md\n\n%s  \n' "$import" > "$project/AGENTS.md"
check "an import with trailing blanks still counts" check_reports
mended "$project/AGENTS.md"

check "with every breakage undone, --check passes again" check_reports

# 15. By hand lists the squad's tracked files that are not committed yet, whatever run wrote them,
#     and none once they are committed (#49).
target="$(new_project uncommitted)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
out="$("$install" "$target" "$tag_a" 2>&1)"
commit_item="$(grep 'Commit these files' <<<"$out")"
check "a second run still lists the files the first one wrote and nobody committed" \
  bash -c 'grep -qF ".gitignore" <<<"$1" && grep -qF ".github/ISSUE_TEMPLATE/task.md" <<<"$1"' _ "$commit_item"
check "and not the project's own template, which it did not change" lacks "$commit_item" "PULL_REQUEST_TEMPLATE"
git -C "$target" add .gitignore .github && git -C "$target" commit -qm "the squad's tracked files"
out="$("$install" "$target" "$tag_a" 2>&1)"
check "once they are committed, it lists none" lacks "$out" "Commit these files"

# 16. A remote whose default branch is not main (#72). A project on trunk, complete: the worktrees
#     are made at origin/trunk, --check passes, and the gate protects trunk. Without origin/HEAD,
#     the installer asks the remote and records it for the gate; when the remote cannot tell, it
#     says so, makes no worktree, and exits 1, instead of assuming main.
git init -q --bare -b trunk "$lab/trunk.git" && git init -q -b trunk "$lab/trunk-seed" || exit 2
printf '# the sandbox checks\ntrue\n' > "$lab/trunk-seed/.agent-squad-checks"
printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$lab/trunk-seed/AGENTS.md"
ln -s AGENTS.md "$lab/trunk-seed/CLAUDE.md"
git -C "$lab/trunk-seed" add -A && git -C "$lab/trunk-seed" commit -qm seed \
  && git -C "$lab/trunk-seed" push -q "$lab/trunk.git" trunk || exit 2
git clone -q "$lab/trunk.git" "$lab/on-trunk" || exit 2
out="$("$install" "$lab/on-trunk" "$tag_a" 2>&1)"
code=$?
check "on a project whose default branch is trunk, the installer exits 0" [ "$code" -eq 0 ]
for agent in dev qa; do
  check "and makes worktrees/$agent detached at origin/trunk" \
    detached_at "$lab/on-trunk" "$lab/on-trunk/.agent-squad/worktrees/$agent" trunk
done
# `reports_on <project> [<item>...]` is check_reports on another project.
reports_on() {
  local project="$1"
  shift
  check_reports "$@"
}
check "and --check passes its twelve items" reports_on "$lab/on-trunk"
echo "a change" >> "$lab/on-trunk/.agent-squad/worktrees/dev/.agent-squad-checks"
git -C "$lab/on-trunk/.agent-squad/worktrees/dev" commit -qam "a change"
errors="$(git -C "$lab/on-trunk/.agent-squad/worktrees/dev" push -q origin HEAD:refs/heads/trunk 2>&1)"
check "and a push to trunk is refused by the gate" contains "$errors" "which only a PR reviewed by QA may change"

git init -q -b main "$lab/no-head" && git -C "$lab/no-head" remote add origin "$lab/trunk.git" \
  && git -C "$lab/no-head" fetch -q origin || exit 2
# Recent git records origin/HEAD on fetch (followRemoteHEAD); older git does not. Either way, none.
git -C "$lab/no-head" symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null
check "a checkout fetched without origin/HEAD has none before the install" \
  refused git -C "$lab/no-head" symbolic-ref -q refs/remotes/origin/HEAD
out="$("$install" "$lab/no-head" "$tag_a" 2>&1)"
check "the installer asks the remote, records origin/HEAD and says so" \
  contains "$out" "recorded origin/HEAD -> origin/trunk"
check "so that the gate protects trunk there too" \
  has_line "$(git -C "$lab/no-head" symbolic-ref -q --short refs/remotes/origin/HEAD)" "origin/trunk"
check "and the worktrees are at origin/trunk" \
  detached_at "$lab/no-head" "$lab/no-head/.agent-squad/worktrees/dev" trunk

git init -q -b main "$lab/unknown" && git -C "$lab/unknown" remote add origin "$lab/no-such-remote.git" || exit 2
out="$("$install" "$lab/unknown" "$tag_a" 2>&1)"
code=$?
check "when the remote cannot tell its default branch, the installer exits 1" [ "$code" -eq 1 ]
check "and says it does not know it, instead of assuming main" contains "$out" "branch     NOT KNOWN"
check "and makes no worktree" absent "$lab/unknown" .agent-squad/worktrees/dev .agent-squad/worktrees/qa

# An empty remote, as every new project's first install has it (BOOTSTRAP installs before row 5):
# the remote answers, with no branch yet. The installer says so and asks for a second run, not for
# a set-head that would fail; after the bootstrap commit, pushed as the approved exception, the
# second run records origin/HEAD and makes the worktrees.
git init -q --bare -b main "$lab/empty.git" && git clone -q "$lab/empty.git" "$lab/new-project" 2>/dev/null || exit 2
out="$("$install" "$lab/new-project" "$tag_a" 2>&1)"
code=$?
check "with an empty remote, the installer exits 1" [ "$code" -eq 1 ]
check "and says the remote has no branch yet, to run it again after the first commit" \
  contains "$out" "branch     NOT YET: the remote has no branch yet"
check "and does not say the remote could not be asked" lacks "$out" "could not be asked"
check "and makes no worktree yet" absent "$lab/new-project" .agent-squad/worktrees/dev
printf '# the sandbox checks\ntrue\n' > "$lab/new-project/.agent-squad-checks"
git -C "$lab/new-project" add .agent-squad-checks && git -C "$lab/new-project" commit -qm "the bootstrap commit"
check "the bootstrap commit reaches main as the approved exception" \
  env SQUAD_MAIN_EXCEPTION='#1' git -C "$lab/new-project" push -q origin HEAD:refs/heads/main
out="$("$install" "$lab/new-project" "$tag_a" 2>&1)"
code=$?
check "then a second run exits 0 and records origin/HEAD" \
  bash -c '[ "$1" -eq 0 ] && grep -qF "recorded origin/HEAD -> origin/main" <<<"$2"' _ "$code" "$out"
check "and makes the worktrees at origin/main" \
  detached_at "$lab/new-project" "$lab/new-project/.agent-squad/worktrees/dev" main

# 17. The failure paths the first coverage report found that no test ran (#184). Each needs a
#     decision or stops the run, and says why.
# A tag name that is no tag's.
for bad in '' 'v1;x'; do
  out="$("$install" "$lab/new-project" "$bad" 2>&1)"
  code=$?
  check "the tag name '$bad' is refused with exit 2, saying so" \
    bash -c '[ "$1" -eq 2 ] && grep -qF "'"'"'$2'"'"' is not a tag name" <<<"$3"' _ "$code" "$bad" "$out"
done
# --check on an installed project, broken one way at a time.
target="$(new_project failures)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
project="$target" squad="$target/.agent-squad" hooks="$target/.git/hooks"
mv "$squad/playbook.manifest" "$lab/manifest-aside"
check "a playbook installed without checksums fails the playbook item, saying to install again" \
  check_reason "$item_playbook" "no checksums were recorded when it was installed; install again"
mv "$lab/manifest-aside" "$squad/playbook.manifest"
mv "$squad/playbook/README.md" "$lab/readme-aside" && ln -s ../LICENSE "$squad/playbook/README.md"
check "a playbook file replaced by a symbolic link fails the playbook item, naming it" \
  check_reason "$item_playbook" "changed since it was installed: README.md"
rm "$squad/playbook/README.md" && mv "$lab/readme-aside" "$squad/playbook/README.md"
mv "$hooks/pre-push" "$lab/shim-aside"
check "a missing shim fails the shim item" check_reason "$item_shim" "there is no $(cd "$hooks" && pwd -P)/pre-push"
printf '#!/bin/sh\nexit 0\n' > "$hooks/pre-push"
check "a pre-push that is not the shim fails it" check_reason "$item_shim" "$hooks/pre-push is not the squad's shim"
cp -p "$lab/shim-aside" "$hooks/pre-push" && echo "# an edit" >> "$hooks/pre-push"
check "an edited shim fails it, saying to install again" \
  check_reason "$item_shim" "the shim is not the one this installer writes; install again"
out="$("$install" "$target" "$tag_a" 2>&1)"
check "and an install rewrites it" contains "$out" "pre-push   rewrote the shim"
check "as the installer writes it" cmp -s "$lab/shim-aside" "$hooks/pre-push"
git -C "$target" rm -q --cached .agent-squad-checks
check "an untracked list of checks fails the list item" check_reason "$item_list" ".agent-squad-checks is not tracked"
git -C "$target" add .agent-squad-checks
check "a gate check that cannot make its sandbox says so" \
  env TMPDIR="$lab/no-such-tmp" bash -c "$(declare -f check_reason); install=\"\$1\" project=\"\$2\"; check_reason \"\$3\" \"\$4\"" _ \
  "$install" "$target" "$item_gate" "cannot create a temporary directory"
check "and makes no directory there" absent "$lab" no-such-tmp
mkdir -p "$lab/no-init"
printf '#!/usr/bin/env bash\n[ "${1:-}" = init ] && exit 1\nexec %q "$@"\n' "$(command -v git)" > "$lab/no-init/git"
chmod +x "$lab/no-init/git"
check "a gate check whose sandbox git cannot make says so, and does not blame the gate" \
  env PATH="$lab/no-init:$PATH" bash -c "$(declare -f check_reason); install=\"\$1\" project=\"\$2\"; check_reason \"\$3\" \"\$4\"" _ \
  "$install" "$target" "$item_gate" "cannot build a throw-away repository to test the gate in"
# An upgrade whose new playbook cannot be moved in place keeps the installed one.
mkdir -p "$lab/no-mv"
printf '#!/usr/bin/env bash\ncase "${1:-}" in */playbook.new.*) exit 1 ;; esac\nexec %q "$@"\n' "$(command -v mv)" > "$lab/no-mv/mv"
chmod +x "$lab/no-mv/mv"
before="$(tree_state "$squad/playbook")"
out="$(PATH="$lab/no-mv:$PATH" "$install" --source "$lab/vb" "$target" "$tag_b" 2>&1)"
code=$?
check "an upgrade that cannot move its playbook in place exits 2, saying the installed one is unchanged" \
  bash -c '[ "$1" -eq 2 ] && grep -qF "cannot move the new playbook in place; the installed one is unchanged" <<<"$2"' _ "$code" "$out"
check "and the installed playbook is the one it had" [ "$before" = "$(tree_state "$squad/playbook")" ]
check "with nothing left behind" no_leftovers "$squad"
# A .gitignore whose last line has no newline gets one before the squad's lines.
target="$(new_project no-newline)" || exit 2
printf 'build' > "$target/.gitignore"
"$install" "$target" "$tag_a" >/dev/null 2>&1
check "a .gitignore without a final newline keeps its last line whole" has_lines "$target/.gitignore" build .agent-squad/
# A .gitignore that is a symbolic link, which git 2.32 and later do not read, gets nothing written
# through it (#186): its target may be outside the project, and shared. The step says what to do
# and needs a decision; the rest of the install goes on.
target="$(new_project linked-gitignore)" || exit 2
echo "shared" > "$lab/linked-gitignore.target" && ln -s "$lab/linked-gitignore.target" "$target/.gitignore"
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "a symbolic link for .gitignore makes the installer exit 1" [ "$code" -eq 1 ]
check "and say that the squad's paths are not ignored, and what to do" \
  contains "$out" "NOT IGNORED: .agent-squad/, because .gitignore is a symbolic link, which git 2.32 and later do not read and the installer does not write through; replace it with a file of its own, then run again"
check "and write nothing through the link" [ "$(cat "$lab/linked-gitignore.target")" = shared ]
check "which stays a link" [ -L "$target/.gitignore" ]
check "and add nothing it says it added" lacks "$out" ".gitignore added"
check "while the rest of the install goes on" detached_at "$target" "$target/.agent-squad/worktrees/dev" main
project="$target"
check "and --check says why its .gitignore item fails" \
  check_reason "$item_ignore" ".gitignore is a symbolic link, which git 2.32 and later do not read; replace it with a file of its own"
# Commands it cannot write, a worktree it cannot make, and a branch the remote does not have yet.
target="$(new_project no-commands)" || exit 2
mkdir -p "$target/.claude" && echo "not a directory" > "$target/.claude/commands"
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "commands that cannot be written make the installer exit 1, saying which" \
  bash -c '[ "$1" -eq 1 ] && grep -qF "NOT INSTALLED: cannot write .claude/commands/squad-save-state.md" <<<"$2"' _ "$code" "$out"
target="$(new_project no-worktrees)" || exit 2
mkdir -p "$target/.agent-squad" && echo "not a directory" > "$target/.agent-squad/worktrees"
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "a worktree git cannot make makes the installer exit 1, with git's reason" \
  bash -c '[ "$1" -eq 1 ] && grep -qF "worktrees  NOT CREATED: .agent-squad/worktrees/dev: " <<<"$2"' _ "$code" "$out"
target="$(new_project no-base)" || exit 2
git -C "$target" update-ref -d refs/remotes/origin/main
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "a default branch the clone does not have yet makes the installer exit 1, asking for another run" \
  bash -c '[ "$1" -eq 1 ] && grep -qF "because origin/main does not exist yet; run again once it does" <<<"$2"' _ "$code" "$out"
# A tree without the issue template, or whose template of AGENTS.md has no Squad section.
rm -rf "$lab/partial" && mkdir -p "$lab/partial" && cp -pR "$lab/vb/." "$lab/partial/"
rm "$lab/partial/.github/ISSUE_TEMPLATE/task.md"
printf '# AGENTS.md\n\nNo section of the squad here.\n' > "$lab/partial/templates/AGENTS.md"
target="$(new_project partial-tree)" || exit 2
out="$("$install" --source "$lab/partial" "$target" "$tag_b" 2>&1)"
check "a tree without the issue template skips it, saying so" \
  contains "$out" "templates  .github/ISSUE_TEMPLATE/task.md is not in the playbook, skipped"
check "and a template of AGENTS.md without a Squad section is named, not printed" \
  contains "$out" "Add the Squad section of .agent-squad/playbook/templates/AGENTS.md to AGENTS.md"

# 18. A squad command the playbook no longer has, as after a rename (#188), is removed on the next
#     install, saying so; one the project tracks is its own, and stays.
target="$(new_project leftover-commands)" || exit 2
"$install" "$target" "$tag_a" >/dev/null 2>&1
echo "an older release's command" > "$target/.claude/commands/squad-retired.md"
echo "the project's own command" > "$target/.claude/commands/squad-own.md"
git -C "$target" add -f .claude/commands/squad-own.md && git -C "$target" commit -qm "a command of the project's own"
out="$("$install" "$target" "$tag_a" 2>&1)"
code=$?
check "an install with a leftover squad command exits 0" [ "$code" -eq 0 ]
check "and removes it, saying so" \
  bash -c '[ ! -e "$1/.claude/commands/squad-retired.md" ] && grep -qF "removed /squad-retired, which this release does not have" <<<"$2"' _ "$target" "$out"
check "but keeps a squad-named command the project tracks, saying so" \
  bash -c '[ "$(cat "$1/.claude/commands/squad-own.md")" = "the project'"'"'s own command" ] && grep -qF "/squad-own is the project'"'"'s own file, tracked by git, and not the squad'"'"'s: left as it is" <<<"$2"' _ "$target" "$out"
check "and every command of the playbook is still there" same_commands "$target"

# 19. The squad's mods (#206): enabled for the project alone, from the playbook, through a
#     marketplace of the project's own in .agent-squad/, named after the project, a hash of its path
#     and the release, written into .claude/settings.local.json with nothing fetched and nothing
#     written outside the project; a plugin the person turned off stays off; an upgrade moves to the
#     new release and leaves nothing of the old one; a Claude Code without mods, or a release
#     without them, gets none, and the install still succeeds.
target="$(new_project mods)" || exit 2
tsquad="$(cd "$target" && pwd -P)/.agent-squad"
tsettings="$target/.claude/settings.local.json"
# `mods_items <project>` prints --check's lines about the mods.
mods_items() { "$install" --check "$1" 2>&1 | grep "the squad's mods"; }
# `release_marketplace <tree> <name>` prints what the project's marketplace must be for that tree.
release_marketplace() {
  jq -S --arg name "$2" '.name = $name | .plugins |= map(.source |= "./playbook/mods/" + ltrimstr("./"))' \
    "$1/mods/.claude-plugin/marketplace.json"
}
mkdir -p "$lab/home" && rm -f "$lab/claude-calls.txt"
out="$(HOME="$lab/home" "$install" "$target" "$tag_a" 2>&1)"
code=$?
name_a="$(jq -r '.extraKnownMarketplaces // {} | keys[0] // ""' "$tsettings")"
check "an install with Claude Code 2.1.289 exits 0" [ "$code" -eq 0 ]
check "and names the project's marketplace after the project, a hash of its path and the release" \
  bash -c '[[ "$1" =~ ^agent-squad-mods-[0-9a-f]{6}-v$2$ ]]' _ "$name_a" "$version_a"
check "declares it at .agent-squad/ and enables the default plugin under it, and nothing else of the squad's" \
  jq_holds ".extraKnownMarketplaces == {\"$name_a\": {source: {source: \"directory\", path: \"$tsquad\"}}}
    and .enabledPlugins == {\"squad-board@$name_a\": true}" "$tsettings"
check "and keeps the five hooks" jq_holds "$five_hooks" "$tsettings"
check "the marketplace in .agent-squad/ is the release's, renamed, its plugins the playbook's" \
  [ "$(jq -S . "$tsquad/.claude-plugin/marketplace.json")" = "$(release_marketplace "$lab/va" "$name_a")" ]
check "and the plugin it names is in the playbook" present "$tsquad/playbook/mods" squad-board/.claude-plugin/plugin.json
check "the install says what it enabled, and how to turn it off" \
  contains "$out" "mods       enabled for this project: squad-board (marketplace $name_a, in .agent-squad/; claude plugin disable <plugin>@$name_a --scope local turns one off)"
check "it asked Claude Code its version, nothing else" [ "$(sort -u "$lab/claude-calls.txt")" = "--version" ]
check "and wrote nothing in the user's home" [ -z "$(ls -A "$lab/home")" ]
check "--check reports the mods enabled" has_line "$(mods_items "$target")" "check: ok      $item_mods"
cp -p "$tsettings" "$lab/mods-before"
"$install" "$target" "$tag_a" >/dev/null 2>&1
check "a second install changes nothing in the settings" cmp -s "$lab/mods-before" "$tsettings"

#     Turned off, as claude plugin disable leaves it: it stays off, on reinstall and on upgrade.
jq --arg key "squad-board@$name_a" '.enabledPlugins[$key] = false' "$lab/mods-before" > "$tsettings"
out="$("$install" "$target" "$tag_a" 2>&1)"
check "a plugin turned off stays off on reinstall" jq_holds ".enabledPlugins == {\"squad-board@$name_a\": false}" "$tsettings"
check "and the install says so" contains "$out" "enabled for this project: none; turned off, as you left them: squad-board"
check "and --check passes, naming it" has_line "$(mods_items "$target")" "check: ok      $item_mods (squad-board turned off)"
out="$("$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" 2>&1)"
code=$?
name_b="${name_a%-v*}-v${tag_b#v}"
check "an upgrade exits 0" [ "$code" -eq 0 ]
check "and moves to the new release's marketplace, the plugin still off, nothing of the old one left" \
  jq_holds ".extraKnownMarketplaces == {\"$name_b\": {source: {source: \"directory\", path: \"$tsquad\"}}}
    and .enabledPlugins == {\"squad-board@$name_b\": false}" "$tsettings"
check "with the new release's marketplace in .agent-squad/" \
  [ "$(jq -S . "$tsquad/.claude-plugin/marketplace.json")" = "$(release_marketplace "$lab/vb" "$name_b")" ]
jq --arg key "squad-board@$name_b" '.enabledPlugins[$key] = true' "$tsettings" > "$lab/mods-on" && cp "$lab/mods-on" "$tsettings"
check "turned on again, --check passes" has_line "$(mods_items "$target")" "check: ok      $item_mods"

#     What --check catches, and an install mends: another release's entries, and the marketplace
#     missing. The project's own marketplace and plugin are left as they are.
jq '.extraKnownMarketplaces["agent-squad-other-abcdef-v1"] = {source: {source: "directory", path: "/elsewhere"}}
  | .enabledPlugins["squad-board@agent-squad-other-abcdef-v1"] = true
  | .extraKnownMarketplaces["team-tools"] = {source: {source: "directory", path: "/tools"}}
  | .enabledPlugins["lint@team-tools"] = true' "$lab/mods-on" > "$tsettings"
check "an earlier release's entries fail the mods item, named" \
  contains "$(mods_items "$target")" "check: FAILED  $item_mods: missing: none; unexpected: agent-squad-other-abcdef-v1, squad-board@agent-squad-other-abcdef-v1; install again"
"$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" >/dev/null 2>&1
check "an install removes them and keeps the project's own marketplace and plugin" \
  jq_holds "(.extraKnownMarketplaces | keys) == [\"$name_b\", \"team-tools\"]
    and .enabledPlugins == {\"squad-board@$name_b\": true, \"lint@team-tools\": true}" "$tsettings"
rm "$tsquad/.claude-plugin/marketplace.json"
check "a missing marketplace fails the mods item" \
  contains "$(mods_items "$target")" "check: FAILED  $item_mods: .agent-squad/.claude-plugin/marketplace.json is missing or not this release's"
"$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" >/dev/null 2>&1
check "and an install writes it again" present "$tsquad" .claude-plugin/marketplace.json

#     A Claude Code without mods, or none: no mod, nothing of the squad's left in the settings,
#     the install still a success, and --check content with it.
for stub in 2.1.200 none; do
  if [ "$stub" = none ]; then
    reason="Claude Code (claude) is not installed, or its version cannot be read"
  else
    reason="Claude Code 2.1.200 has no mods, which need 2.1.287 or later"
  fi
  out="$(CLAUDE_STUB_VERSION="$stub" "$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" 2>&1)"
  code=$?
  check "with Claude Code '$stub', the install exits 0" [ "$code" -eq 0 ]
  check "and says why no mod is enabled" contains "$out" "mods       SKIPPED: $reason; no mod of the squad is enabled"
  check "and leaves none of the squad's entries, and no marketplace" \
    bash -c 'jq -e "(.extraKnownMarketplaces | keys) == [\"team-tools\"] and .enabledPlugins == {\"lint@team-tools\": true}" "$1" >/dev/null && [ ! -e "$2" ]' \
    _ "$tsettings" "$tsquad/.claude-plugin/marketplace.json"
  check "and --check reports the mods skipped, as no failure" \
    has_line "$(CLAUDE_STUB_VERSION="$stub" "$install" --check "$target" 2>&1 | grep "the squad's mods")" \
    "check: ok      the squad's mods are skipped, since $reason"
done

#     A release with no mods (an older tag's tree): none enabled, and the entries of a release that
#     had them removed.
mkdir -p "$lab/vnomods" && cp -pR "$lab/vb/." "$lab/vnomods/" && rm -r "$lab/vnomods/mods"
"$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" >/dev/null 2>&1
out="$("$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vnomods" "$target" "$tag_b" 2>&1)"
check "a release with no mods says so" contains "$out" "mods       SKIPPED: this release has no mods; no mod of the squad is enabled"
check "and removes the entries of the release before it" \
  jq_holds '(.extraKnownMarketplaces | keys) == ["team-tools"] and .enabledPlugins == {"lint@team-tools": true}' "$tsettings"

exit "$status"
