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
# The cases run side by side, in groups that each have a lab of their own (agent-squad #245).
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

# The labs go under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR. Each group
# of cases has one of its own (see the end of this script); the first, base, holds what they all copy:
# the stubs and the two trees.
labs="${TMPDIR:-/tmp}"
labs="$(mktemp -d "${labs%/}/squad-check-install.XXXXXX")" || exit 2
# `stop_groups` ends the process group of each group of cases still running.
stop_groups() {
  local job
  for job in $(jobs -p); do kill -- "-$job" 2>/dev/null; done
}
trap 'stop_groups; rm -rf "$labs"' EXIT
base="$labs/base"
lab="$base"
mkdir "$base" || exit 2
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
# `next_steps <quoted name>` prints the lines a first install ends with (agent-squad #262), the
# project's name as the installer quotes it for the shell.
next_steps() {
  printf '%s\n' "Next steps:" \
    "- Start three Claude Code sessions in your project's folder, each in its own terminal:" \
    "    claude -n \"CTO:$1\"" "    claude -n \"DEV:$1\"" "    claude -n \"QA:$1\"" \
    "  If you like, give each session its colour on the squad board: /color yellow in the CTO's," \
    "  /color blue in DEV's and /color green in QA's." \
    "- Tell the CTO: \"Follow .agent-squad/playbook/BOOTSTRAP.md.\""
}
# `ends_with_next_steps <output> <quoted name>` passes when the output's last lines, from "Next
# steps:" on, are exactly those.
ends_with_next_steps() { [ "$(sed -n '/^Next steps:$/,$p' <<<"$1")" = "$(next_steps "$2")" ]; }
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
item_hooks="the squad's hooks are in .claude/settings.local.json and point at the playbook"
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
item_excludes="the worktrees' copies of the project's instructions are left out of every session"
# The squad's entries of claudeMdExcludes, as the installer writes them (agent-squad #416).
squad_excludes='["**/.agent-squad/worktrees/*/CLAUDE.md", "**/.agent-squad/worktrees/*/.claude/CLAUDE.md", "**/.agent-squad/worktrees/*/.claude/rules/**"]'
# `check_reports [<item>...]` runs --check on the project and passes when the items that fail are
# exactly those given, with exit 1; with none given, when every item passes, with exit 0.
check_reports() {
  local out code failed
  out="$("$install" --check "$project" 2>&1)"
  code=$?
  failed="$(sed -n 's/^check: FAILED  \([^:]*\):.*/\1/p' <<<"$out" | LC_ALL=C sort)"
  if [ $# -eq 0 ]; then
    [ "$code" -eq 0 ] && [ -z "$failed" ] && [ "$(grep -c '^check: ok ' <<<"$out")" -eq 14 ]
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
# `path_without <command>` prints a directory of links to every other command on PATH, which stands
# for the PATH of a machine without that one.
path_without() {
  local dir="$lab/without-$1" entries entry command
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    IFS=: read -r -a entries <<<"$PATH"
    for entry in "${entries[@]}"; do
      for command in "$entry"/*; do
        [ "${command##*/}" != "$1" ] && [ -x "$command" ] && [ ! -e "$dir/${command##*/}" ] && ln -s "$command" "$dir/${command##*/}"
      done
    done
  fi
  echo "$dir"
}
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
# `no_leftovers <squad dir>`: no staging directory, tarball or Release download survived a run.
no_leftovers() {
  local entry
  for entry in "$1"/playbook.new.* "$1"/tarball.* "$1"/release.*; do [ ! -e "$entry" ] || return 1; done
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
# with the file named by GH_TARBALL when the tag is GH_TAG. `gh release download <tag> --repo
# gzurl/agent-squad --pattern <name>... --dir <dir>` copies into <dir> the files of the directory
# GH_RELEASE that the patterns name, when the tag is GH_TAG, and fails when it copies none, as gh
# does, or when GH_RELEASE is unset: the tag has no Release; it writes the patterns it was given to
# release-downloads.txt beside bin/. `gh api repos/gzurl/agent-squad/releases/tags/<tag> --jq <filter>`
# runs the filter on a Release whose assets are GH_RELEASE's files, each with its digest, the
# SHA-256 GitHub computes (agent-squad #330): none when GH_DIGEST is none, a wrong one when it is
# wrong; it fails when GH_RELEASE is unset or the tag is not GH_TAG. GH_HANG=tarball makes the
# tarball's download never answer, its PID in hung.pid beside bin/. Anything else fails.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
if [ "${1:-}" = api ] && [ "${2:-}" = "repos/gzurl/agent-squad/tarball/${GH_TAG:-}" ]; then
  if [ "${GH_HANG:-}" = tarball ]; then echo "$$" > "$(dirname "$0")/../hung.pid"; exec sleep 60; fi
  exec cat "$GH_TARBALL"
fi
if [ "${1:-}" = api ] && [ "${2:-}" = "repos/gzurl/agent-squad/releases/tags/${GH_TAG:-}" ] && [ "${3:-}" = --jq ]; then
  [ -n "${GH_RELEASE:-}" ] || exit 1
  for file in "$GH_RELEASE"/*; do
    [ -f "$file" ] || continue
    case "${GH_DIGEST:-}" in
      none) digest=null ;;
      wrong) digest="\"sha256:$(printf '%064d' 0)\"" ;;
      *) digest="\"sha256:$(if command -v sha256sum >/dev/null; then sha256sum "$file"; else shasum -a 256 "$file"; fi | cut -d' ' -f1)\"" ;;
    esac
    printf '{"name": "%s", "digest": %s}\n' "${file##*/}" "$digest"
  done | jq -s '{assets: .}' | jq -r "$4"
  exit
fi
if [ "${1:-} ${2:-}" = "release download" ] && [ -n "${GH_RELEASE:-}" ] && [ "${3:-}" = "${GH_TAG:-}" ]; then
  shift 3
  repo="" dir="" patterns=() copied=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="$2" ;;
      --dir) dir="$2" ;;
      --pattern) patterns+=("$2") ;;
    esac
    shift 2
  done
  [ "$repo" = gzurl/agent-squad ] && [ -d "$dir" ] || exit 1
  printf '%s\n' "${patterns[*]}" >> "$(dirname "$0")/../release-downloads.txt"
  for pattern in ${patterns[@]+"${patterns[@]}"}; do
    [ ! -f "$GH_RELEASE/$pattern" ] || { cp "$GH_RELEASE/$pattern" "$dir/" && copied=$((copied + 1)); }
  done
  [ "$copied" -gt 0 ]
  exit
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

# `same_commands <project>` passes when each of the playbook's commands is in .claude/commands/, byte
# for byte, and there is at least one: it walks the playbook's own list, not one kept here.
same_commands() {
  local file count=0
  for file in "$1/.agent-squad/playbook/commands"/squad-*.md; do
    [ -f "$file" ] || return 1
    cmp -s "$file" "$1/.claude/commands/$(basename "$file")" || return 1
    count=$((count + 1))
  done
  [ "$count" -ge 12 ]
}
# The squad's hook entries run the hooks' wrapper (agent-squad #269); `ours` lists their matchers.
ours='[.hooks[][] | select(any(.hooks[]; .command | contains("/.agent-squad/squad-hook"))) | .matcher]'
# `hook_commands` lists each squad entry's event, matcher and command, in the installer's order.
hook_commands='[.hooks | to_entries[] | .key as $e | .value[] | .matcher as $m | .hooks[]
  | select(.command | contains("squad-hook") or contains("squad-handoff.sh")) | "\($e) \($m) \(.command)"]'
# `wrapper_commands <project>` is what they are, as the installer writes them for that project: its
# wrapper, by its physical absolute path in single quotes (agent-squad #319), and the event, nothing
# else. The turn's end has no matcher (agent-squad #302), and /clear runs startup's command (#336).
wrapper_commands() {
  jq -nc --arg w "'$(cd "$1" && pwd -P)/.agent-squad/squad-hook'" '[
    "PreCompact manual \($w) save", "PreCompact auto \($w) save", "SessionStart compact \($w) restore",
    "SessionStart startup \($w) startup", "SessionStart clear \($w) startup", "SessionStart resume \($w) resume",
    "Stop  \($w) turn"]'
}
squad_hooks="$ours == [\"manual\", \"auto\", \"compact\", \"startup\", \"clear\", \"resume\", \"\"]"
# `broken <file>` keeps a copy of a file about to be broken; `mended <file>` puts it back.
broken() { cp -p "$1" "$lab/mend.me"; }
mended() { cp -p "$lab/mend.me" "$1"; }
# `in_lab <group>` gives a group a lab of its own, with a copy of the stubs and of the two trees, and
# points lab, PATH and the stub gh's tarball at it.
in_lab() {
  lab="$labs/$1"
  mkdir "$lab" && cp -pR "$base/bin" "$base/va" "$base/vb" "$base/va.tgz" "$lab/" || return 1
  export PATH="$lab/bin:$PATH" GH_TARBALL="$lab/va.tgz"
}
# `complete_project <name>` makes a project with the squad installed and set up, AGENTS.md importing
# the charter and CLAUDE.md linked to it, on which --check passes every item, and points project,
# squad, dev, settings and hooks at it. Each part of case 14 breaks a project of its own.
complete_project() {
  project="$(new_project "$1")" && "$install" "$project" "$tag_a" >/dev/null 2>&1 || return 1
  printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$project/AGENTS.md"
  ln -s AGENTS.md "$project/CLAUDE.md"
  squad="$project/.agent-squad" dev="$project/.agent-squad/worktrees/dev"
  settings="$project/.claude/settings.local.json" hooks="$project/.git/hooks"
}
# `command_breakages <1|0>` breaks the playbook's commands one at a time, every other one from the
# first (1) or from the second (0): case 14's commands, in two halves that run side by side. It walks
# the playbook's own list, and fails when its half is empty.
command_breakages() {
  local place=0 walked=0 command_file name
  for command_file in "$squad/playbook/commands"/squad-*.md; do
    place=$((place + 1))
    [ $((place % 2)) -eq "$1" ] || continue
    walked=$((walked + 1))
      name="$(basename "$command_file" .md)"
      command_file="$project/.claude/commands/$name.md"
      broken "$command_file"
      echo "An edit." >> "$command_file"
      check "a modified /$name fails the commands item" check_reports "$item_command"
      rm "$command_file"
      check "a missing /$name fails it too" check_reports "$item_command"
      mended "$command_file"
  done
  [ "$walked" -gt 0 ] || fail "case 14 broke no command in its half $1 of the playbook's list"
}

# Cases 1 to 8, 10, and the start and end of 14, on one project that each case takes on from the
# one before.
cases_main_project() {
  # A project that already has its own local settings, pre-push and pre-commit. Its settings carry
  # an entry of an older squad, which the installer replaces.
  project="$(new_project project)" || exit 2
  mkdir -p "$project/.claude"
  cat > "$project/.claude/settings.local.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(ls:*)"] },
  "claudeMdExcludes": ["**/vendor/CLAUDE.md", "**/.agent-squad/worktrees/*/OLD.md"],
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
  check "the squad's commands are in .claude/commands/, as the playbook has them" same_commands "$project"
  check "the missing issue template was created from the playbook" \
    cmp -s "$squad/playbook/.github/ISSUE_TEMPLATE/task.md" "$project/.github/ISSUE_TEMPLATE/task.md"
  check "the project's own PR template was kept" \
    has_lines "$project/.github/PULL_REQUEST_TEMPLATE.md" "The project's own PR template."
  for agent in dev qa; do
    check "worktrees/$agent is a linked worktree detached at origin/main" \
      detached_at "$project" "$squad/worktrees/$agent" main
  done
  # The output (agent-squad #262): one line per step, and a first install that ends with the README's
  # next steps.
  commands_count="$(find "$squad/playbook/commands" -name 'squad-*.md' | wc -l | tr -d ' ')"
  check "the $commands_count commands are said in one line, with their number" \
    bash -c '[ "$(grep -c "^install: command " <<<"$1")" -eq 1 ] && grep -qxF "install: command    wrote the $2 squad commands into .claude/commands/" <<<"$1"' \
    _ "$out" "$commands_count"
  check ".gitignore, the templates and the worktrees take one line each" \
    bash -c 'for step in .gitignore templates worktrees; do [ "$(grep -cF "install: $step " <<<"$1")" -eq 1 ] || exit 1; done' _ "$out"
  # A first install, the squad not set up yet, prints no By hand list, nor any line about it: what is
  # left, --check says to the CTO who follows BOOTSTRAP.md (agent-squad #267, #271).
  check "a first install prints no By hand list" lacks "$out" "By hand"
  check "nor the Squad section's text" lacks "$out" "The squad section this test expects, first line."
  check "and ends with the next steps, the project's name in the sessions' names" \
    ends_with_next_steps "$out" project
  check "--check after a fresh install fails only on what is left by hand, AGENTS.md" check_reports "$item_import"

  # 2. The project's local settings are kept; only the squad's entries change.
  check "settings.local.json keeps the project's permissions" \
    jq_holds '.permissions.allow == ["Bash(ls:*)"]' "$settings"
  check "and the project's own hook" \
    jq_holds '.hooks.PreToolUse[0].hooks[0].command == "echo own hook"' "$settings"
  check "and has the squad's hooks once each, the older entry replaced" \
    jq_holds "$squad_hooks" "$settings"
  # Each runs the wrapper with its event, the shortest command that keeps the guard for a missing
  # playbook (#269): Claude Code shows it in brackets on every line about the hook. The wrapper is
  # named by its absolute path, so that a session whose $CLAUDE_PROJECT_DIR is elsewhere reaches it.
  check "each squad hook runs .agent-squad/squad-hook, by its absolute path, with its event, and no other command is the squad's" \
    jq_holds "$hook_commands == $(wrapper_commands "$project")" "$settings"
  check "and the wrapper is in .agent-squad/, executable" [ -x "$squad/squad-hook" ]
  # The worktrees' copies of the project's instructions are left out (agent-squad #416): the
  # project's own exclude first, then the squad's, the older squad entry gone.
  check "claudeMdExcludes keeps the project's own entry, then has the squad's, the older one replaced" \
    jq_holds ".claudeMdExcludes == [\"**/vendor/CLAUDE.md\"] + $squad_excludes" "$settings"
  check "which the install says in one line" \
    has_line "$out" "install: excludes   wrote claudeMdExcludes into .claude/settings.local.json, other settings kept: every session leaves out the worktrees' copies of the project's instructions"

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
  # The squad is not set up yet, AGENTS.md not importing the charter: the run ends as a first install
  # does (agent-squad #271).
  check "a second run before the setup ends with the next steps again" ends_with_next_steps "$out" project
  check "and prints no By hand list" lacks "$out" "By hand"
  check "and says .gitignore, the commands, the templates and the worktrees in one line each" \
    bash -c 'for step in .gitignore command templates worktrees; do [ "$(grep -cF "install: $step " <<<"$1")" -eq 1 ] || exit 1; done' _ "$out"

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
  # `run_hook <matcher> [<project directory> [<directory>]]` runs the command installed for that
  # matcher as Claude Code would, its $CLAUDE_PROJECT_DIR the directory given, the main checkout when
  # none is, from the last directory given, the main checkout when none is, and passes when it exits
  # 0. "" for the project directory leaves the variable unset.
  run_hook() {
    local program command
    program='[.hooks[][] | select(.matcher == $m) | .hooks[] | .command | select(contains("/.agent-squad/squad-hook"))][0]'
    command="$(jq -r --arg m "$1" "$program" "$settings")"
    if [ "${2-$project}" = "" ]; then
      (cd "${3:-$project}" && echo '{"session_id":"x"}' | env -u CLAUDE_PROJECT_DIR sh -c "$command")
    else
      (cd "${3:-$project}" && echo '{"session_id":"x"}' | CLAUDE_PROJECT_DIR="${2-$project}" sh -c "$command")
    fi
  }
  mv "$squad/playbook" "$lab/playbook-aside"
  check "the shim refuses a push when the playbook is missing" refused push_from "$dev" no-playbook
  for matcher in startup clear compact resume; do
    check "the $matcher hook warns that the charter is not installed" \
      prints "charter is not installed" run_hook "$matcher"
  done
  check "the save hook does nothing and exits 0" prints_nothing run_hook manual
  mv "$lab/playbook-aside" "$squad/playbook"
  check "with the playbook back, the startup hook prints nothing" prints_nothing run_hook startup
  check "and the compact hook re-orients the session" prints "Context was compacted" run_hook compact
  check "and the resume hook says where the shell is" prints "Squad: this session was resumed" run_hook resume

  # 6b. A session whose $CLAUDE_PROJECT_DIR is not the main checkout, as one started or resumed from a
  #     subdirectory (agent-squad #319), reaches the wrapper all the same, and is told so at its
  #     start, its resume and each compaction, naming both directories; then the event runs as for
  #     any session. It is never told that the charter is not installed while it is. Each exits 0.
  mkdir -p "$project/harness"
  checkout_p="$(cd "$project" && pwd -P)"
  misplaced="Squad: this session belongs to $project/harness, not to $checkout_p: it was started or resumed from there, so its memory directory is not the squad's (SQUAD.md §2.1). Exit it, start a new session from $checkout_p without --resume, and tell the CTO."
  # `told_misplaced <matcher>` passes when that hook, run for the subdirectory, exits 0 and prints
  # the message, and nothing about the charter.
  told_misplaced() {
    local out
    out="$(run_hook "$1" "$project/harness")" && grep -qxF -- "$misplaced" <<<"$out" && lacks "$out" "charter is not installed"
  }
  # `saves_quietly`: the save hook, run for the subdirectory, exits 0, prints nothing, and saves.
  saves_quietly() {
    local out
    rm -f "$squad/handoff/x.md"
    out="$(run_hook manual "$project/harness")" && [ -z "$out" ] && [ -s "$squad/handoff/x.md" ]
  }
  # `told_both`: with the playbook missing, the startup hook prints the message, then the charter's.
  told_both() {
    local out
    out="$(run_hook startup "$project/harness")" && grep -qxF -- "$misplaced" <<<"$out" \
      && contains "$out" "charter is not installed ($checkout_p/.agent-squad/playbook/scripts/squad-handoff.sh is missing)"
  }
  for matcher in startup clear compact resume; do
    check "a session started in a subdirectory gets, from its $matcher hook, the message that names both directories" \
      told_misplaced "$matcher"
  done
  check "and after it, the compact hook still re-orients the session" prints "Context was compacted" run_hook compact "$project/harness"
  check "and the resume hook still says where the shell is" prints "Squad: this session was resumed" run_hook resume "$project/harness"
  check "its save hook still saves the snapshot, and says nothing" saves_quietly
  check "and its turn's end says nothing" prints_nothing run_hook "" "$project/harness"
  mv "$squad/playbook" "$lab/playbook-aside"
  check "with the playbook missing too, it is told both, the charter's path named" told_both
  mv "$lab/playbook-aside" "$squad/playbook"
  #    The same directory under another name, and no $CLAUDE_PROJECT_DIR at all, are no misplaced session.
  ln -s "$project" "$lab/linked-checkout"
  check "a \$CLAUDE_PROJECT_DIR that is a symbolic link to the checkout gets no warning" prints_nothing run_hook startup "$lab/linked-checkout"
  check "and neither does a hook run with no \$CLAUDE_PROJECT_DIR, from a subdirectory" \
    prints_nothing run_hook startup "" "$project/harness"

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
  check "an upgrade before the setup ends with the next steps" ends_with_next_steps "$out" project
  check "and prints no By hand list" lacks "$out" "By hand"
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
  for missing in SQUAD.md scripts/squad-install.sh scripts/squad-latest.sh scripts/squad-timeout.sh templates/AGENTS.md \
    $commands_in_tree; do
    rm -rf "$lab/incomplete" && mkdir -p "$lab/incomplete" && cp -pR "$lab/vb/." "$lab/incomplete/"
    rm "$lab/incomplete/$missing"
    out="$("$install" --source "$lab/incomplete" "$project" vd 2>&1)"
    code=$?
    check "a tree without $missing exits 2, saying so" \
      bash -c '[ "$1" -eq 2 ] && grep -qF "has no $2" <<<"$3"' _ "$code" "$missing" "$out"
    check "and leaves the playbook as it was" same_tree "$squad/playbook" "$lab/vb"
  done
  check "and no failure wrote to install.log" matches_none "$(cat "$squad/install.log")" " -> (vc|vd)$"

  # 10. Only the main checkout is accepted.
  out="$("$install" "$dev" "$tag_a" 2>&1)"
  code=$?
  check "a linked worktree is refused with exit 2" [ "$code" -eq 2 ]
  check "and nothing is created in it" absent "$dev" .agent-squad

  # 14. --check passes on a complete installation, changes nothing, and fails on the right line for
  #     each item broken on purpose; each breakage is undone before the next.
  printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$project/AGENTS.md"
  ln -s AGENTS.md "$project/CLAUDE.md"
  before="$(project_state "$project")$(cat "$squad/install.log")"
  check "--check passes on a complete installation, every item ok" check_reports
  check "and changes nothing, the install log included" \
    [ "$before" = "$(project_state "$project")$(cat "$squad/install.log")" ]

  # 14b. Once the squad is set up, AGENTS.md importing the charter, a run prints the By hand list, for
  #      the CTO, and no next steps (agent-squad #271).
  out="$("$squad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$project" "$tag_b" 2>&1)"
  code=$?
  check "a run once the squad is set up exits 0" [ "$code" -eq 0 ]
  check "and prints the By hand list, which says it is the CTO's" \
    has_line "$out" "By hand, for the CTO, who does it while following BOOTSTRAP.md or /squad-upgrade:"
  check "which ends the output, with an item or nothing" \
    bash -c 'tail -n 1 <<<"$1" | grep -qE "^  ([0-9]+\. |nothing$)"' _ "$out"
  check "and shows no next steps" lacks "$out" "Next steps:"
}

# Cases 7c to 7f: an upgrade without a reader, and the commands and .gitignore rewritten.
cases_upgrade_output() {
  # 7h. The hooks as releases before v49 wrote them, each command guarding the playbook's script
  #     itself, become the wrapper's on the next install, once each (#269); a wrapper changed since
  #     is rewritten, saying so.
  target="$(new_project old-hooks)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  old='f="$CLAUDE_PROJECT_DIR"/.agent-squad/playbook/scripts/squad-handoff.sh; if [ -x "$f" ]; then "$f" '
  jq --arg old "$old" '.hooks = {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "echo own hook"}]}],
    PreCompact: [{matcher: "manual", hooks: [{type: "command", command: ($old + "save; fi")}]},
                 {matcher: "auto", hooks: [{type: "command", command: ($old + "save; fi")}]}],
    SessionStart: ([["compact", "restore"], ["startup", "startup"], ["resume", "resume"]]
      | map({matcher: .[0], hooks: [{type: "command", command: ($old + .[1] + "; else echo missing; fi")}]}))}' \
    "$target/.claude/settings.local.json" > "$lab/old-hooks.json" && cp "$lab/old-hooks.json" "$target/.claude/settings.local.json"
  echo "# an edit" >> "$target/.agent-squad/squad-hook"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  check "hooks written before v49 become the wrapper's, once each, and the project's own hook stays" \
    jq_holds "$hook_commands == $(wrapper_commands "$target") and .hooks.PreToolUse[0].hooks[0].command == \"echo own hook\"" "$target/.claude/settings.local.json"
  check "and a wrapper changed since is rewritten, saying so" \
    bash -c 'grep -qF "wrote the squad'"'"'s hooks into .claude/settings.local.json, other settings kept, and rewrote their wrapper .agent-squad/squad-hook" <<<"$1" \
      && ! grep -qF "# an edit" "$2"' _ "$out" "$target/.agent-squad/squad-hook"

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
  # With every command changed but one, the summary names the rewritten ones and says the other one
  # was already there (agent-squad #267).
  for file in "$target"/.claude/commands/squad-*.md; do
    [ "$(basename "$file")" = squad-save-state.md ] || echo "An edit." >> "$file"
  done
  out="$("$install" "$target" "$tag_a" 2>&1)"
  check "when one command was already there, the summary says the other one was" \
    bash -c 'grep "^install: command " <<<"$1" | grep -q "rewrote /.*; the other one was already there\$"' _ "$out"

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
  others=$(($(find "$target/.agent-squad/playbook/commands" -name 'squad-*.md' | wc -l) - 1))
  check "and says it wrote the other $others, not that the squad has $others commands" \
    contains "$out" "install: command    wrote the other $others squad commands into .claude/commands/"
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
    has_line "$out" "install: .gitignore already ignored: .agent-squad/, .claude/settings.local.json, .claude/commands/squad-*.md"
}

# Case 7g: Git LFS.
cases_lfs() {
  # 7g. Git LFS (#121). Its own pre-push hook cannot go where the shim is, so a project that routes
  #     files through LFS runs it from hooks/pre-push.local, which the shim runs first. --check shows
  #     an item for it only when a .gitattributes of the project has filter=lfs: failing without an
  #     executable pre-push.local that runs git lfs pre-push, passing with one. LFS's own hook, there
  #     before the install, is kept as pre-push.local and passes as it is. No git-lfs is needed: the
  #     item reads files.
  lfs_hook="$(printf '%s\n' '#!/bin/sh' \
    'command -v git-lfs >/dev/null 2>&1 || { echo "git-lfs was not found on your path" >&2; exit 2; }' \
    'git lfs pre-push "$@"')"
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
}

# Cases 9, 11, 12 and 13: the steps that need a decision.
cases_decisions() {
  # 9. With core.hooksPath set, the shim is not installed, the reason is printed and the exit is 1.
  other="$(new_project other)" || exit 2
  git -C "$other" config core.hooksPath .githooks
  out="$("$install" "$other" "$tag_a" 2>&1)"
  code=$?
  check "with core.hooksPath set the installer exits 1" [ "$code" -eq 1 ]
  check "and says why" contains "$out" "pre-push   NOT INSTALLED: core.hooksPath is set"
  check "and writes no shim" absent "$other" .git/hooks/pre-push
  check "while the other steps are done" present "$other" .agent-squad/playbook/SQUAD.md

  # 11. Blank settings count as none; settings that are not one JSON object are left as they are.
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
    check "and gets the squad's hooks" jq_holds "$squad_hooks" "$target/.claude/settings.local.json"
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
    check "and so does the excludes step" contains "$out" "excludes   NOT INSTALLED: .claude/settings.local.json is not one JSON object"
    check "and is left byte for byte" cmp -s "$lab/settings-before" "$target/.claude/settings.local.json"
  done
  target="$(new_project settings-excludes-string)" || exit 2
  mkdir -p "$target/.claude" && echo '{"claudeMdExcludes": "CLAUDE.md"}' > "$target/.claude/settings.local.json"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "a claudeMdExcludes that is not a list exits 1" [ "$code" -eq 1 ]
  check "and says why" contains "$out" "excludes   NOT INSTALLED: .claude/settings.local.json is not one JSON object whose claudeMdExcludes is a list; it is left as it is: fix it and run again"
  check "and keeps it as it was, the hooks written beside it" \
    jq_holds ".claudeMdExcludes == \"CLAUDE.md\" and ($squad_hooks)" "$target/.claude/settings.local.json"

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
}

# Case 14, in five parts on five complete projects: the playbook, the hooks, .gitignore, the shim.
cases_check_settings() {
  complete_project complete || exit 2

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
  broken "$settings"
  jq '.hooks.SessionStart |= map(select(.matcher != "clear"))' "$lab/mend.me" > "$settings"
  check "so does a missing clear hook, which a /clear runs (agent-squad #336), naming it" \
    contains "$("$install" --check "$project" 2>&1)" "$item_hooks: missing: clear; unexpected: none"
  mended "$settings"
  broken "$settings"
  echo 'not json' > "$settings"
  check "a settings file that is not JSON fails the hooks, the mods and the excludes items" \
    check_reports "$item_hooks" "$item_mods" "$item_excludes"
  check "the hooks item saying it cannot read the file" check_reason "$item_hooks" "cannot read .claude/settings.local.json"
  check "and so does the mods item" check_reason "$item_mods" "cannot read .claude/settings.local.json"
  check "and the excludes item" check_reason "$item_excludes" "cannot read claudeMdExcludes in .claude/settings.local.json"
  mended "$settings"
  # The worktrees' copies of the project's instructions (agent-squad #416): each of the squad's
  # entries is required, an earlier release's is not, and the project's own are its business.
  broken "$settings"
  jq '.claudeMdExcludes |= map(select(endswith("/rules/**") | not))' "$lab/mend.me" > "$settings"
  check "a missing exclude fails the excludes item, naming it" \
    check_reason "$item_excludes" "missing: **/.agent-squad/worktrees/*/.claude/rules/**; unexpected: none; install again"
  mended "$settings"
  broken "$settings"
  jq '.claudeMdExcludes += ["**/.agent-squad/worktrees/*/OLD.md"]' "$lab/mend.me" > "$settings"
  check "an earlier release's exclude fails it too, naming it" \
    check_reason "$item_excludes" "missing: none; unexpected: **/.agent-squad/worktrees/*/OLD.md; install again"
  mended "$settings"
  broken "$settings"
  jq '.claudeMdExcludes = "CLAUDE.md"' "$lab/mend.me" > "$settings"
  check "and so does a claudeMdExcludes that is not a list" \
    check_reason "$item_excludes" "cannot read claudeMdExcludes in .claude/settings.local.json"
  mended "$settings"
  broken "$settings"
  jq '.claudeMdExcludes = ["**/vendor/CLAUDE.md"] + .claudeMdExcludes' "$lab/mend.me" > "$settings"
  check "while the project's own exclude beside the squad's fails nothing" check_reports
  mended "$settings"
  # The hooks' wrapper (#269), which --check requires as the installer writes it.
  broken "$squad/squad-hook"
  echo "# an edit" >> "$squad/squad-hook"
  check "an edited hooks' wrapper fails the hooks item" check_reports "$item_hooks"
  check "saying to install again" check_reason "$item_hooks" "their wrapper .agent-squad/squad-hook is not the one this installer writes; install again"
  mended "$squad/squad-hook"
  chmod -x "$squad/squad-hook"
  check "and so does one that cannot run" check_reports "$item_hooks"
  chmod +x "$squad/squad-hook"
  mv "$squad/squad-hook" "$lab/hook-aside"
  check "and a missing one, named" check_reason "$item_hooks" "their wrapper .agent-squad/squad-hook is missing; install again"
  mv "$lab/hook-aside" "$squad/squad-hook"

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

  check "with every breakage undone, --check passes again" check_reports
}

#   The commands, every other one, from the first.
cases_check_commands_odd() {
  complete_project complete || exit 2

  command_breakages 1

  check "with every breakage undone, --check passes again" check_reports
}

#   The commands, every other one, from the second.
cases_check_commands_even() {
  complete_project complete || exit 2

  command_breakages 0

  check "with every breakage undone, --check passes again" check_reports
}

#   An interrupted --check, the gate, the list, the default branch and the worktrees.
cases_check_gate() {
  complete_project complete || exit 2

  # Interrupted while the gate's sandbox exists, --check leaves no sandbox and touches nothing else in
  # TMPDIR (#71). The run gets its own process group, which is what a Ctrl-C signals, and is
  # interrupted at a state, not after a delay: as soon as the sandbox's directory exists, and once it
  # holds its repositories. Two wrappers make both states last: a mktemp that waits between creating a
  # directory and printing its name (the window in which a cleanup that learns the name from mktemp
  # has nothing to remove, or removes TMPDIR itself), and a git whose push waits half a minute, which
  # the interruption cuts short, so that a loaded machine finds the state in time (agent-squad #498).
  # The mktemp waits a second only: it holds every directory the run makes so, before the sandbox.
  real_mktemp="$(command -v mktemp)" real_git="$(command -v git)"
  mkdir -p "$lab/slow"
  printf '#!/usr/bin/env bash\ndir="$(%q "$@")" || exit\nsleep 1\necho "$dir"\n' "$real_mktemp" > "$lab/slow/mktemp"
  printf '#!/usr/bin/env bash\n[ "${3:-}" = push ] && sleep 30\nexec %q "$@"\n' "$real_git" > "$lab/slow/git"
  chmod +x "$lab/slow/mktemp" "$lab/slow/git"
  # `sandboxes` lists the gate's sandboxes in the test's TMPDIR.
  sandboxes() { find "$lab/tmp" -maxdepth 1 -name 'squad-check.*' 2>/dev/null; }
  # `interrupted_at <created|populated>` runs --check, interrupts it at that state, and passes when the
  # run was really interrupted (exit 130), no sandbox is left, and the file that is not the
  # installer's is still there. The state is awaited for 30 s at most, and the cleanup too, where
  # each takes well under a second on an idle machine; a case that fails says what it found.
  interrupted_at() {
    local pid code sandbox started=$SECONDS
    rm -rf "$lab/tmp" && mkdir -p "$lab/tmp" && echo "not the installer's" > "$lab/tmp/keep-me"
    set -m
    PATH="$lab/slow:$PATH" TMPDIR="$lab/tmp" "$install" --check "$project" >/dev/null 2>&1 &
    pid=$!
    set +m
    until sandbox="$(sandboxes | head -1)" && [ -n "$sandbox" ] \
      && { [ "$1" = created ] || [ -d "$sandbox/remote.git" ]; }; do
      if [ $((SECONDS - started)) -ge 30 ] || ! kill -0 "$pid" 2>/dev/null; then
        kill -INT -- "-$pid" 2>/dev/null
        echo "          its sandbox was not $1 within 30 s, or the run ended first" >&2
        return 1
      fi
      sleep 0.005
    done
    kill -INT -- "-$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    code=$?
    # What is left of the run gets a moment to finish its cleanup.
    started=$SECONDS
    while [ -n "$(sandboxes)" ] && [ $((SECONDS - started)) -lt 30 ]; do sleep 0.05; done
    [ "$code" -eq 130 ] && [ -z "$(sandboxes)" ] && [ -f "$lab/tmp/keep-me" ] && return 0
    echo "          exit $code, a sandbox left 30 s later: $([ -n "$(sandboxes)" ] && echo yes || echo no), the other file kept: $([ -f "$lab/tmp/keep-me" ] && echo yes || echo no)" >&2
    return 1
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

  check "with every breakage undone, --check passes again" check_reports
}

#   The import of the charter.
cases_check_import() {
  complete_project complete || exit 2

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
}

# Case 15.
cases_uncommitted() {
  # 15. By hand lists the squad's tracked files that are not committed yet, whatever run wrote them,
  #     and none once they are committed (#49).
  target="$(new_project uncommitted)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  # Set up, so that a run prints the list (agent-squad #271); AGENTS.md is not one of the files it lists.
  printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$target/AGENTS.md"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  commit_item="$(grep 'Commit these files' <<<"$out")"
  check "a second run still lists the files the first one wrote and nobody committed" \
    bash -c 'grep -qF ".gitignore" <<<"$1" && grep -qF ".github/ISSUE_TEMPLATE/task.md" <<<"$1"' _ "$commit_item"
  check "and not the project's own template, which it did not change" lacks "$commit_item" "PULL_REQUEST_TEMPLATE"
  git -C "$target" add .gitignore .github && git -C "$target" commit -qm "the squad's tracked files"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  check "once they are committed, it lists none" lacks "$out" "Commit these files"
}

# Case 15b.
cases_template_changes() {
  # 15b. The run that installs a release names, under By hand, each template the project keeps that
  #      the release changes, with a command that shows the change; none when the release leaves
  #      them as they were, and none for a template the project lacks, which it creates (#512).
  target="$(new_project templates)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$target/AGENTS.md"
  out="$("$install" --source "$lab/vb" "$target" "$tag_b" 2>&1)"
  check "an upgrade whose release leaves the templates as they were lists none of them" \
    lacks "$out" "change to the playbook's"
  # Tree T, the version after B: both templates changed. The project keeps its own PR template, and
  # has no task template, which the upgrade creates.
  tag_t="v$((version_a + 2))"
  mkdir -p "$lab/vt" && cp -pR "$lab/vb/." "$lab/vt/" || exit 2
  sed -i.orig "s/^> \*\*Version:\*\* ${tag_b#v} /> **Version:** ${tag_t#v} /" "$lab/vt/SQUAD.md" \
    && rm "$lab/vt/SQUAD.md.orig" || exit 2
  echo "Changed in vt." >> "$lab/vt/.github/PULL_REQUEST_TEMPLATE.md"
  echo "Changed in vt." >> "$lab/vt/.github/ISSUE_TEMPLATE/task.md"
  rm "$target/.github/ISSUE_TEMPLATE/task.md"
  out="$("$install" --source "$lab/vt" "$target" "$tag_t" 2>&1)"
  check "an upgrade whose release changes a template the project keeps names it under By hand, with a command that shows the change" \
    contains "$out" ". Bring $tag_t's change to the playbook's .github/PULL_REQUEST_TEMPLATE.md into the project's own, which the installer keeps: diff -u <(gh api -H 'Accept: application/vnd.github.raw' 'repos/gzurl/agent-squad/contents/.github/PULL_REQUEST_TEMPLATE.md?ref=$tag_b') .agent-squad/playbook/.github/PULL_REQUEST_TEMPLATE.md shows it"
  check "and keeps the project's own" [ "$(cat "$target/.github/PULL_REQUEST_TEMPLATE.md")" = "The project's own PR template." ]
  check "but not the template the project lacked, which it creates from the release" \
    bash -c 'grep -qF "change to the playbook'"'"'s .github/ISSUE_TEMPLATE" <<<"$1" && exit 1; cmp -s "$2" "$3"' _ \
    "$out" "$target/.github/ISSUE_TEMPLATE/task.md" "$lab/vt/.github/ISSUE_TEMPLATE/task.md"
}

# Case 16.
cases_default_branch() {
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
  check "and --check passes every item" reports_on "$lab/on-trunk"
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
}

# Case 16c.
cases_ssh_keepalive() {
  # 16c. A push keeps its ssh connection while its checks run (agent-squad #438): the installer sets
  #      core.sshCommand to a keepalive in the project's .git/config, and says so; a second run
  #      finds it there; --check fails without it. A core.sshCommand that the project or the
  #      machine set is left as it is, and passes --check, and so is a GIT_SSH, which
  #      core.sshCommand would override (QA's finding on PR #452). The uninstaller removes the
  #      squad's keepalive, and leaves the project's own.
  local keepalive="ssh -o ServerAliveInterval=30" target out code item
  item="core.sshCommand keeps a push's ssh connection alive, or the project's own ssh is used"
  target="$(new_project keepalive)" || exit 2
  out="$("$install" "$target" "$tag_a" 2>&1)"
  check "an install sets core.sshCommand to a keepalive in the project's .git/config, and says so" \
    bash -c '[ "$(git -C "$1" config --local --get core.sshCommand)" = "$2" ] \
      && grep -qF "install: ssh        set core.sshCommand to '\''$2'\'' in .git/config" <<<"$3"' _ "$target" "$keepalive" "$out"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  check "a second install finds it there" contains "$out" "install: ssh        core.sshCommand already keeps a push's ssh connection alive"
  out="$("$install" --check "$target" 2>&1)"
  check "and --check passes it" contains "$out" "check: ok      $item"
  git -C "$target" config --local --unset core.sshCommand
  out="$("$install" --check "$target" 2>&1)"
  check "without it, --check fails the item, saying to install again" \
    contains "$out" "check: FAILED  $item: core.sshCommand is not set, so a push whose checks take minutes can lose its connection; install again, which sets it"

  target="$(new_project own-ssh)" || exit 2
  git -C "$target" config --local core.sshCommand "ssh -i ~/.ssh/project_key"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  check "a project's own core.sshCommand is left as it is, saying so" \
    bash -c '[ "$(git -C "$1" config --local --get core.sshCommand)" = "ssh -i ~/.ssh/project_key" ] \
      && grep -qF "core.sshCommand is the project'\''s or this machine'\''s own (ssh -i ~/.ssh/project_key), so it is left as it is" <<<"$2"' _ "$target" "$out"
  out="$("$install" --check "$target" 2>&1)"
  check "and passes --check" contains "$out" "check: ok      $item"
  out="$("$target/.agent-squad/playbook/scripts/squad-uninstall.sh" "$target" 2>&1)"
  check "and the uninstaller leaves it" \
    bash -c '[ "$(git -C "$1" config --local --get core.sshCommand)" = "ssh -i ~/.ssh/project_key" ] && ! grep -q "keepalive" <<<"$2"' _ "$target" "$out"

  target="$(new_project machine-ssh)" || exit 2
  printf '[core]\n\tsshCommand = ssh -o ServerAliveInterval=60\n' > "$lab/machine-ssh.gitconfig"
  out="$(GIT_CONFIG_GLOBAL="$lab/machine-ssh.gitconfig" "$install" "$target" "$tag_a" 2>&1)"
  check "this machine's core.sshCommand is left as it is, and none is set in .git/config" \
    bash -c '! git -C "$1" config --local --get core.sshCommand >/dev/null && grep -qF "this machine'\''s own (ssh -o ServerAliveInterval=60)" <<<"$2"' _ "$target" "$out"

  target="$(new_project own-git-ssh)" || exit 2
  out="$(GIT_SSH=/usr/local/bin/plink "$install" "$target" "$tag_a" 2>&1)"
  check "with GIT_SSH set, no core.sshCommand is set, which would override it, saying so" \
    bash -c '! git -C "$1" config --get core.sshCommand >/dev/null \
      && grep -qF "GIT_SSH names this machine'\''s own program (/usr/local/bin/plink), which core.sshCommand would override, so none is set" <<<"$2"' _ "$target" "$out"
  out="$(GIT_SSH=/usr/local/bin/plink "$install" --check "$target" 2>&1)"
  check "and --check passes with it" contains "$out" "check: ok      $item"

  target="$(new_project locked-config)" || exit 2
  : > "$target/.git/config.lock"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  rm -f "$target/.git/config.lock"
  check "a .git/config that cannot be written makes the installer exit 1, saying so" \
    bash -c '[ "$1" -eq 1 ] && grep -qF "install: ssh        NOT INSTALLED: cannot write core.sshCommand in .git/config; fix it and run again" <<<"$2" \
      && ! git -C "$3" config --local --get core.sshCommand >/dev/null' _ "$code" "$out" "$target"

  target="$(new_project removable-keepalive)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  out="$("$target/.agent-squad/playbook/scripts/squad-uninstall.sh" "$target" 2>&1)"
  code=$?
  check "the uninstaller removes the squad's keepalive, saying so" \
    bash -c '[ "$1" -eq 0 ] && ! git -C "$2" config --local --get core.sshCommand >/dev/null \
      && grep -qF "uninstall: ssh        removed the keepalive from .git/config'\''s core.sshCommand" <<<"$3"' _ "$code" "$target" "$out"
}

# Case 16b.
cases_unanswered() {
  # 16b. A call to the remote that never answers stops after SQUAD_GH_TIMEOUT seconds of wall-clock
  #      time, through squad-timeout.sh beside the installer, and the installer says so
  #      (agent-squad #435): the tarball's download, and the remote asked for its default branch. An
  #      installer with no squad-timeout.sh beside it, as one copied alone, asks the remote as before.
  local target started
  # `gone <pid file>` passes when the process it names no longer runs.
  gone() { ! kill -0 "$(cat "$1")" 2>/dev/null; }
  target="$(new_project unanswered-download)" || exit 2
  started=$SECONDS
  out="$(GH_HANG=tarball SQUAD_GH_TIMEOUT=1 "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  # Within 30 s: well under its stub's 60 s, and over what CI's kcov takes (agent-squad #447).
  check "a download that never answers is stopped after the bound: exit 2, within 30 s" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" -le 30 ]' _ "$code" "$((SECONDS - started))"
  check "saying so, and that nothing was installed" \
    bash -c 'grep -qxF "squad-timeout: gh did not end within 1 s, so it was stopped" <<<"$1" \
      && grep -qF "cannot download $2 from gzurl/agent-squad; the installed playbook is unchanged" <<<"$1"' _ "$out" "$tag_a"
  check "and the download no longer runs" gone "$lab/hung.pid"
  check "and no playbook is installed" absent "$target" .agent-squad/playbook

  # git, as far as the installer's step 6 is concerned: `remote set-head` and `ls-remote` never
  # answer, their PIDs in hung-git.pid; every other command is git's own.
  mkdir -p "$lab/git-hang"
  printf '#!/usr/bin/env bash
case " $* " in *" set-head "*|*" ls-remote "*) echo "$$" >> %q; exec sleep 60 ;; esac
exec %q "$@"
' \
    "$lab/hung-git.pid" "$(type -P git)" > "$lab/git-hang/git"
  chmod +x "$lab/git-hang/git"
  target="$(new_project unanswered-remote)" || exit 2
  git -C "$target" symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null
  started=$SECONDS
  out="$(PATH="$lab/git-hang:$PATH" SQUAD_GH_TIMEOUT=1 "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  # Within 45 s: well under the two stubs' 60 s, and over what CI's kcov takes (#447).
  check "a remote that never says its default branch is stopped after the bound: exit 1, within 45 s" \
    bash -c '[ "$1" -eq 1 ] && [ "$2" -le 45 ]' _ "$code" "$((SECONDS - started))"
  check "and the installer says that it did not answer, instead of assuming main" \
    contains "$out" "branch     NOT KNOWN: origin/HEAD is not set and the remote did not answer within 1 s"
  check "and git no longer runs" bash -c 'while read -r pid; do ! kill -0 "$pid" 2>/dev/null || exit 1; done < "$1"' _ "$lab/hung-git.pid"

  mkdir -p "$lab/alone" && cp "$install" "$lab/alone/"
  target="$(new_project installer-alone)" || exit 2
  git -C "$target" symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null
  out="$("$lab/alone/squad-install.sh" "$target" "$tag_a" 2>&1)"
  code=$?
  check "an installer with no squad-timeout.sh beside it asks the remote as before, and exits 0" \
    bash -c '[ "$1" -eq 0 ] && grep -qF "recorded origin/HEAD -> origin/main" <<<"$2"' _ "$code" "$out"
}

# Case 17, in two: --check on an installed project broken one way at a time.
cases_failure_paths() {
  # 17. The failure paths the first coverage report found that no test ran (#184). Each needs a
  #     decision or stops the run, and says why.
  # --check on an installed project, broken one way at a time.
  target="$(new_project failures)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  # A tag name that is no tag's.
  for bad in '' 'v1;x'; do
    out="$("$install" "$target" "$bad" 2>&1)"
    code=$?
    check "the tag name '$bad' is refused with exit 2, saying so" \
      bash -c '[ "$1" -eq 2 ] && grep -qF "'"'"'$2'"'"' is not a tag name" <<<"$3"' _ "$code" "$bad" "$out"
  done
  # Without jq, the installer stops before it changes anything. It asks `type -P`, since `command -v`
  # would find the jq function that drops jq's CRs on Windows (#405).
  before="$(project_state "$target")"
  out="$(PATH="$(path_without jq)" "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "without jq the installer exits 2, saying jq is required, and changes nothing" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "squad-install: jq is required" ] && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$before" "$(project_state "$target")"
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
  # A mkdir that makes the directory but cannot set its mode, as on NTFS under Git Bash, where mkdir -m
  # then exits 1 (agent-squad #277): the gate check still runs, leaves no lab behind, and its lab is
  # closed to others as before. Its git writes down the mode of the lab each repository is made in.
  mkdir -p "$lab/no-mode" "$lab/mode-tmp"
  printf '%s\n' '#!/usr/bin/env bash' \
    '# mkdir as on NTFS under Git Bash: given a mode, it makes the directory and cannot set the mode.' \
    'args=() mode=""' \
    'while [ $# -gt 0 ]; do' \
    '  case "$1" in -m) mode=yes; shift 2 ;; -m*) mode=yes; shift ;; *) args+=("$1"); shift ;; esac' \
    'done' \
    "$(printf '%q' "$(command -v mkdir)")"' "${args[@]}" || exit' \
    '[ -z "$mode" ]' > "$lab/no-mode/mkdir"
  printf '#!/usr/bin/env bash\n[ "${1:-}" = init ] && ls -ld "$(dirname "${!#}")" | cut -c1-10 >> %q\nexec %q "$@"\n' \
    "$lab/lab-modes.txt" "$(command -v git)" > "$lab/no-mode/git"
  chmod +x "$lab/no-mode/mkdir" "$lab/no-mode/git"
  check "a mkdir that cannot set a mode, as on NTFS under Git Bash, does not fail the gate item" \
    contains "$(TMPDIR="$lab/mode-tmp" PATH="$lab/no-mode:$PATH" "$install" --check "$target" 2>&1)" "check: ok      $item_gate"
  check "and leaves no lab behind" [ -z "$(find "$lab/mode-tmp" -name 'squad-check.*')" ]
  check "and the lab it tests the gate in is closed to others, as before" \
    bash -c '[ -s "$1" ] && ! grep -vqxF "drwx------" "$1"' _ "$lab/lab-modes.txt"
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
}

#   And installs that each fail one way.
cases_failure_installs() {
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
  # A hooks' wrapper it cannot write, because .agent-squad/squad-hook is a directory, leaves the
  # hooks as they are and that directory untouched, says so and needs a decision, and --check names
  # it; mv alone would move the wrapper into it and report success (agent-squad #356). A marketplace
  # it cannot write leaves the mods off. The rest of the install goes on (agent-squad #246).
  target="$(new_project no-wrapper)" || exit 2
  mkdir -p "$target/.agent-squad/squad-hook"
  for run in first second; do
    out="$("$install" "$target" "$tag_a" 2>&1)"
    code=$?
    check "a squad-hook that is a directory makes the $run install exit 1, saying so and what to do" \
      bash -c '[ "$1" -eq 1 ] && grep -qF "NOT INSTALLED: cannot write the hooks'"'"' wrapper .agent-squad/squad-hook, which is not a file: remove it, then run again; the hooks were left as they are" <<<"$2"' \
      _ "$code" "$out"
    check "and leaves nothing in that directory or beside it" \
      bash -c '[ -z "$(ls -A "$1/squad-hook")" ] && [ -z "$(find "$1" -maxdepth 1 -name "squad-hook.*")" ]' _ "$target/.agent-squad"
  done
  check "and writes none of the squad's hooks" \
    jq_holds '[.hooks // {} | .. | .command? // empty | select(contains("squad-hook"))] == []' "$target/.claude/settings.local.json"
  check "and --check names it" \
    contains "$("$install" --check "$target" 2>&1)" "their wrapper .agent-squad/squad-hook is not a file; remove it, then install again"
  target="$(new_project no-marketplace)" || exit 2
  mkdir -p "$target/.agent-squad" && echo "not a directory" > "$target/.agent-squad/.claude-plugin"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "a marketplace that cannot be written makes the installer exit 1, saying so" \
    bash -c '[ "$1" -eq 1 ] && grep -qE "mods +NOT ENABLED: cannot write .*/\.agent-squad/\.claude-plugin/marketplace\.json; fix it and run again" <<<"$2"' \
    _ "$code" "$out"
  check "and enables none of the squad's mods, its hooks installed" \
    jq_holds "(.extraKnownMarketplaces // {}) == {} and (.enabledPlugins // {}) == {} and $squad_hooks" "$target/.claude/settings.local.json"
  # A checks list with no command in it gets the CTO's item to write it, in the list a squad that
  # is set up gets: its AGENTS.md imports the charter.
  target="$(new_project no-checks)" || exit 2
  printf '# no command yet\n' > "$target/.agent-squad-checks"
  printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$target/AGENTS.md"
  git -C "$target" add AGENTS.md .agent-squad-checks && git -C "$target" commit -qm "no checks yet" || exit 2
  out="$("$install" "$target" "$tag_a" 2>&1)"
  check "a checks list with no command gets the CTO's item to write it" \
    contains "$out" "Write .agent-squad-checks: the commands the project's CI runs, one per line; until it lists one the gate refuses every push"
  target="$(new_project no-base)" || exit 2
  git -C "$target" update-ref -d refs/remotes/origin/main
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "a default branch the clone does not have yet makes the installer exit 1, asking for another run" \
    bash -c '[ "$1" -eq 1 ] && grep -qF "because origin/main does not exist yet; run again once it does" <<<"$2"' _ "$code" "$out"
  # A tree without the issue template.
  rm -rf "$lab/partial" && mkdir -p "$lab/partial" && cp -pR "$lab/vb/." "$lab/partial/"
  rm "$lab/partial/.github/ISSUE_TEMPLATE/task.md"
  target="$(new_project partial-tree)" || exit 2
  out="$("$install" --source "$lab/partial" "$target" "$tag_b" 2>&1)"
  check "a tree without the issue template skips it, saying so" \
    contains "$out" "templates  .github/ISSUE_TEMPLATE/task.md is not in the playbook, skipped"
}

# Case 1b (agent-squad #295): a tag with a GitHub Release. The installer downloads the Release's
# package and checks its SHA-256 before it extracts anything. A Release without the package, or no
# Release at all, takes the tag's tarball, as before. A checksum that is wrong or missing stops the
# install, with the installed playbook unchanged.
cases_release() {
  local asset="agent-squad-$tag_a.tar.gz" kind
  # `sha_of <file>` is the file's SHA-256; `release_with <kind>` writes a Release into
  # $lab/assets-<kind>: the package alone, as scripts/release.sh uploads it from v52 on (#330); the
  # package with its checksum right or wrong, as v50 and v51 carry it; another file alone; or the
  # checksum without its package (QA-R1, on PR #301). The stub gh gives each asset its digest.
  sha_of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
  release_with() {
    local dir="$lab/assets-$1"
    mkdir -p "$dir" || return 1
    if [ "$1" = other ]; then echo "notes" > "$dir/notes.md"; return; fi
    if [ "$1" = checksum ]; then printf '%s  %s\n' "$(printf '%064d' 0)" "$asset" > "$dir/$asset.sha256"; return; fi
    git -C "$base/upstream" archive --format=tar --prefix="agent-squad-$tag_a/" HEAD | gzip -n > "$dir/$asset" || return 1
    case "$1" in
      right) printf '%s  %s\n' "$(sha_of "$dir/$asset")" "$asset" > "$dir/$asset.sha256" ;;
      wrong) printf '%s  %s\n' "$(printf '%064d' 0)" "$asset" > "$dir/$asset.sha256" ;;
    esac
  }
  for kind in package right wrong other checksum; do release_with "$kind" || exit 2; done
  # `downloaded` is what the last release download asked for.
  downloaded() { tail -n 1 "$lab/release-downloads.txt" 2>/dev/null; }

  # The package alone, checked against GitHub's digest, with no tarball to fall back on: the
  # playbook is the tarball's, and only the package is downloaded, so an install counts once.
  from_tarball="$(new_project release-tarball)" || exit 2
  "$install" "$from_tarball" "$tag_a" >/dev/null 2>&1
  target="$(new_project release-package)" || exit 2
  out="$(GH_RELEASE="$lab/assets-package" GH_TARBALL="$lab/no-tarball.tgz" "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "a tag with a Release installs from its package, and exits 0" [ "$code" -eq 0 ]
  check "saying so, its SHA-256 checked against GitHub's digest" \
    contains "$out" "install: download   $asset, from the Release of $tag_a, its SHA-256 checked against GitHub's digest"
  check "and downloads the package alone" [ "$(downloaded)" = "$asset" ]
  check "and the playbook is the one the tag's tarball gives" \
    diff -r "$from_tarball/.agent-squad/playbook" "$target/.agent-squad/playbook"
  check "and nothing of the download is left" no_leftovers "$target/.agent-squad"
  #    A Release that carries a .sha256 too, as v50's and v51's do: the digest decides, and the
  #    .sha256 is not downloaded.
  target="$(new_project release-both)" || exit 2
  out="$(GH_RELEASE="$lab/assets-right" GH_TARBALL="$lab/no-tarball.tgz" "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "with a .sha256 beside the package, the digest decides, and the .sha256 is not downloaded" \
    bash -c '[ "$1" -eq 0 ] && grep -qF "its SHA-256 checked against GitHub'"'"'s digest" <<<"$2" && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$(downloaded)" "$asset"
  #    A package with no digest, uploaded before GitHub kept one: its .sha256 asset, as v50 and v51 have.
  target="$(new_project release-no-digest)" || exit 2
  out="$(GH_DIGEST=none GH_RELEASE="$lab/assets-right" GH_TARBALL="$lab/no-tarball.tgz" "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "a package with no digest is checked against its .sha256, and installs" \
    bash -c '[ "$1" -eq 0 ] && grep -qF "its SHA-256 checked against its $2.sha256" <<<"$3" && [ "$4" = "$2 $2.sha256" ]' \
    _ "$code" "$asset" "$out" "$(downloaded)"

  # No Release, or one without the package, its checksum alone included: the tag's tarball, as before.
  for kind in none other checksum; do
    target="$(new_project "release-$kind")" || exit 2
    if [ "$kind" = none ]; then
      out="$("$install" "$target" "$tag_a" 2>&1)"
    else
      out="$(GH_RELEASE="$lab/assets-$kind" "$install" "$target" "$tag_a" 2>&1)"
    fi
    code=$?
    case "$kind" in
      none) what="no Release" ;;
      other) what="a Release without its package" ;;
      checksum) what="a Release with the package's checksum alone" ;;
    esac
    check "a tag with $what installs from its tarball, and exits 0" \
      bash -c '[ "$1" -eq 0 ] && grep -qxF "install: download   the tarball of $2, since no Release package of it could be downloaded" <<<"$3"' \
      _ "$code" "$tag_a" "$out"
  done

  # A digest the package does not match; with no digest, a .sha256 it does not match, or none: the
  # install stops, the installed playbook unchanged.
  for kind in digest-wrong sha256-wrong neither; do
    target="$(new_project "release-$kind")" || exit 2
    "$install" "$target" "$tag_a" >/dev/null 2>&1
    before="$(tree_state "$target")"
    case "$kind" in
      digest-wrong) out="$(GH_DIGEST=wrong GH_RELEASE="$lab/assets-package" "$install" "$target" "$tag_a" 2>&1)" ;;
      sha256-wrong) out="$(GH_DIGEST=none GH_RELEASE="$lab/assets-wrong" "$install" "$target" "$tag_a" 2>&1)" ;;
      neither) out="$(GH_DIGEST=none GH_RELEASE="$lab/assets-package" "$install" "$target" "$tag_a" 2>&1)" ;;
    esac
    code=$?
    case "$kind" in
      neither) says="squad-install: the Release of $tag_a has no digest for $asset, and no $asset.sha256 to check it against; the installed playbook is unchanged" ;;
      *) says="squad-install: $asset, from the Release of $tag_a, does not match its SHA-256; the installed playbook is unchanged" ;;
    esac
    check "a package whose check is $kind stops the install with exit 2, saying so" \
      bash -c '[ "$1" -eq 2 ] && grep -qxF -- "$2" <<<"$3"' _ "$code" "$says" "$out"
    check "and changes nothing" [ "$before" = "$(tree_state "$target")" ]
    check "and leaves nothing of the download" no_leftovers "$target/.agent-squad"
  done

  # A machine with neither sha256sum nor shasum: the install stops before it downloads anything.
  mkdir -p "$lab/no-sha"
  local dir tool
  IFS=: read -r -a dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    for tool in "$dir"/*; do
      case "${tool##*/}" in sha256sum|shasum) continue ;; esac
      [ -x "$tool" ] && [ ! -e "$lab/no-sha/${tool##*/}" ] && ln -s "$tool" "$lab/no-sha/${tool##*/}"
    done
  done
  target="$(new_project release-no-sha)" || exit 2
  before="$(tree_state "$target")"
  out="$(PATH="$lab/no-sha" GH_RELEASE="$lab/assets-right" "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "without sha256sum or shasum the installer exits 2, saying so" \
    bash -c '[ "$1" -eq 2 ] && grep -qxF "squad-install: sha256sum or shasum is required to check the tag'"'"'s package" <<<"$2"' _ "$code" "$out"
  check "and changes nothing" [ "$before" = "$(tree_state "$target")" ]
}

# Case 14b (agent-squad #296): this machine's own excludes, a global core.excludesFile or the
# project's .git/info/exclude, that ignore the .claude/ directory. Git then hides every rule below
# it, the project's own included, so the installer and --check read the project's rules alone.
cases_machine_excludes() {
  printf '.claude/\n' > "$lab/machine-excludes"
  printf '[core]\n\texcludesFile = %s\n' "$lab/machine-excludes" > "$lab/excludes.gitconfig"
  for kind in core.excludesFile info/exclude; do
    target="$(new_project "excludes-${kind//[.\/]/-}")" || exit 2
    # `with_machine <command...>` runs the command on this machine as the kind sets it.
    if [ "$kind" = core.excludesFile ]; then
      with_machine() { env GIT_CONFIG_GLOBAL="$lab/excludes.gitconfig" "$@"; }
    else
      printf '.claude/\n' >> "$target/.git/info/exclude"
      with_machine() { "$@"; }
    fi
    out="$(with_machine "$install" "$target" "$tag_a" 2>&1)"
    code=$?
    check "with $kind ignoring .claude/, an install exits 0" [ "$code" -eq 0 ]
    check "and adds the squad's lines, saying so" \
      contains "$out" ".gitignore added .agent-squad/, .claude/settings.local.json, .claude/commands/squad-*.md"
    check "with no NOT IGNORED" lacks "$out" "NOT IGNORED"
    cp "$target/.gitignore" "$lab/gitignore-first"
    out="$(with_machine "$install" "$target" "$tag_a" 2>&1)"
    code=$?
    check "and a second install exits 0 and adds nothing" \
      bash -c '[ "$1" -eq 0 ] && cmp -s "$2" "$3"' _ "$code" "$lab/gitignore-first" "$target/.gitignore"
    check "so each line is there once" has_lines "$target/.gitignore" .agent-squad/ .claude/settings.local.json ".claude/commands/squad-*.md"
    out="$(with_machine "$install" --check "$target" 2>&1)"
    check "and --check passes its .gitignore item" contains "$out" "check: ok      $item_ignore"
  done

  # A nested negation still decides below a directory the machine ignores: nothing is appended.
  target="$(new_project excludes-nested)" || exit 2
  mkdir -p "$target/.claude" && echo '!settings.local.json' > "$target/.claude/.gitignore"
  out="$(env GIT_CONFIG_GLOBAL="$lab/excludes.gitconfig" "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "with the machine ignoring .claude/, a nested negation of settings.local.json still exits 1" [ "$code" -eq 1 ]
  check "and says which rule wins" contains "$out" ".gitignore NOT IGNORED: .claude/settings.local.json would lose to .claude/.gitignore:1:!settings.local.json"
  check "and appends nothing" refused grep -qxF .claude/settings.local.json "$target/.gitignore"

  # A .gitignore that cannot be written says so, and claims nothing added.
  target="$(new_project readonly-gitignore)" || exit 2
  echo build > "$target/.gitignore" && chmod a-w "$target/.gitignore"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  chmod u+w "$target/.gitignore"
  check "a .gitignore that cannot be written makes the installer exit 1" [ "$code" -eq 1 ]
  check "and says so, for each line" \
    bash -c 'grep -qF "NOT IGNORED: .agent-squad/, because .gitignore cannot be written; fix it and run again" <<<"$1" \
      && grep -qF "NOT IGNORED: .claude/settings.local.json, because .gitignore cannot be written" <<<"$1"' _ "$out"
  check "and claims nothing added" lacks "$out" ".gitignore added"
  check "and leaves it as it was" [ "$(cat "$target/.gitignore")" = build ]

  # A .agent-squad that is a symbolic link: git takes it for a file, which .agent-squad/ does not
  # match, so the added line does not ignore it, and the step says so.
  target="$(new_project linked-squad)" || exit 2
  mkdir -p "$lab/linked-squad.target" && ln -s "$lab/linked-squad.target" "$target/.agent-squad"
  out="$("$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "a .agent-squad that is a symbolic link makes the installer exit 1" [ "$code" -eq 1 ]
  check "saying the line it added does not ignore it" \
    contains "$out" ".gitignore NOT IGNORED: .agent-squad/ was added, and still git does not ignore it; decide with the CEO"

  # Without a temporary directory for its empty git directory, the installer still sets aside a
  # global core.excludesFile, though not .git/info/exclude.
  target="$(new_project excludes-no-tmpdir)" || exit 2
  out="$(env GIT_CONFIG_GLOBAL="$lab/excludes.gitconfig" TMPDIR="$lab/no-such-directory" "$install" "$target" "$tag_a" 2>&1)"
  code=$?
  check "without a temporary directory, core.excludesFile ignoring .claude/ still lets an install exit 0" \
    bash -c '[ "$1" -eq 0 ] && ! grep -qF "NOT IGNORED" <<<"$2"' _ "$code" "$out"
  check "and makes no directory there" absent "$lab" no-such-directory
  target="$(new_project own-tmpdir)" || exit 2
  mkdir "$lab/own-tmpdir.tmp"
  TMPDIR="$lab/own-tmpdir.tmp" "$install" "$target" "$tag_a" >/dev/null 2>&1
  TMPDIR="$lab/own-tmpdir.tmp" "$install" --check "$target" >/dev/null 2>&1
  check "and an install or a --check leaves nothing in the temporary directory" \
    [ -z "$(ls -A "$lab/own-tmpdir.tmp")" ]
}

# Case 14c (agent-squad #319): a main checkout that moved. Its hooks still name the wrapper at the
# old path, so --check's hooks item says so and to install again, and an install from the new place
# rewrites them.
cases_moved_checkout() {
  target="$(new_project before-move)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  local old_p new_p
  old_p="$(cd "$target" && pwd -P)"
  mv "$target" "$lab/after-move" || exit 2
  target="$lab/after-move" new_p="$(cd "$lab/after-move" && pwd -P)"
  out="$("$install" --check "$target" 2>&1)"
  check "after the checkout moved, --check's hooks item says that the hooks run the old wrapper, and to install again" \
    contains "$out" "check: FAILED  $item_hooks: the hooks run '$old_p/.agent-squad/squad-hook', not this checkout's wrapper '$new_p/.agent-squad/squad-hook': the checkout moved, or another release wrote them; install again"
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  out="$("$install" --check "$target" 2>&1)"
  check "and an install from the new place rewrites them, so the hooks item passes again" contains "$out" "check: ok      $item_hooks"
  check "naming the wrapper where it is now" jq_holds "$hook_commands == $(wrapper_commands "$target")" "$target/.claude/settings.local.json"
}

# Case 18.
cases_leftover_commands() {
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
}

# Case 19.
cases_mods() {
  # 19. The squad's mods (#206, #215): enabled for the project alone, from the playbook, through a
  #     marketplace of the project's own in .agent-squad/, named after the project and a hash of its
  #     path, written into .claude/settings.local.json with nothing fetched and nothing written
  #     outside the project; a plugin the person turned off stays off; an upgrade keeps the name, so
  #     that the mods keep their store, and moves the names of releases before v39 (-v<N>) to it; a
  #     Claude Code without mods, or a release without them, gets none, and the install still
  #     succeeds.
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
  check "and names the project's marketplace after the project and a hash of its path, not the release" \
    bash -c '[[ "$1" =~ ^agent-squad-mods-[0-9a-f]{6}$ ]]' _ "$name_a"
  check "declares it at .agent-squad/ and enables the default plugin under it, and nothing else of the squad's" \
    jq_holds ".extraKnownMarketplaces == {\"$name_a\": {source: {source: \"directory\", path: \"$tsquad\"}}}
      and .enabledPlugins == {\"squad-board@$name_a\": true}" "$tsettings"
  check "and keeps the squad's hooks" jq_holds "$squad_hooks" "$tsettings"
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
  check "and the install says so, and how to turn it back on" contains "$out" "enabled for this project: none; turned off, as you left them: squad-board (marketplace $name_a, in .agent-squad/; claude plugin disable <plugin>@$name_a --scope local turns one off, and claude plugin enable <plugin>@$name_a --scope local turns one back on)"
  check "and --check passes, naming it" has_line "$(mods_items "$target")" "check: ok      $item_mods (squad-board turned off)"
  out="$("$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" 2>&1)"
  code=$?
  check "an upgrade exits 0" [ "$code" -eq 0 ]
  check "and keeps the marketplace's name, so the store too, the plugin still off" \
    jq_holds ".extraKnownMarketplaces == {\"$name_a\": {source: {source: \"directory\", path: \"$tsquad\"}}}
      and .enabledPlugins == {\"squad-board@$name_a\": false}" "$tsettings"
  check "with the new release's marketplace in .agent-squad/" \
    [ "$(jq -S . "$tsquad/.claude-plugin/marketplace.json")" = "$(release_marketplace "$lab/vb" "$name_a")" ]

  #     A project that a release before v39 installed has the names with -v<N>: an install moves them
  #     to the stable name, the plugin still off where it was turned off.
  jq --arg name "$name_a" --arg old "$name_a-v37" '.extraKnownMarketplaces = {($old): .extraKnownMarketplaces[$name]}
    | .enabledPlugins = {("squad-board@" + $old): false}' "$tsettings" > "$lab/mods-old" && cp "$lab/mods-old" "$tsettings"
  check "names with -v<N> fail the mods item, named" \
    contains "$(mods_items "$target")" "check: FAILED  $item_mods: missing: $name_a, squad-board@$name_a; unexpected: $name_a-v37, squad-board@$name_a-v37; install again"
  "$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" >/dev/null 2>&1
  check "an install moves them to the stable name, the plugin still off" \
    jq_holds ".extraKnownMarketplaces == {\"$name_a\": {source: {source: \"directory\", path: \"$tsquad\"}}}
      and .enabledPlugins == {\"squad-board@$name_a\": false}" "$tsettings"
  jq --arg key "squad-board@$name_a" '.enabledPlugins[$key] = true' "$tsettings" > "$lab/mods-on" && cp "$lab/mods-on" "$tsettings"
  check "turned on again, --check passes" has_line "$(mods_items "$target")" "check: ok      $item_mods"

  #     What --check catches, and an install mends: the squad's marketplaces that are not this
  #     project's, declared at the .agent-squad/ of an earlier release or of a checkout since moved,
  #     and the marketplace missing. The project's own marketplaces and plugins are left as they are,
  #     whatever their name, agent-squad-tools (#210), and agent-squad-ui-facade and
  #     agent-squad-x-202610, whose last part reads as a hash (PR #216); and whatever their path,
  #     shelf, at a folder that happens to be called .agent-squad.
  jq '.extraKnownMarketplaces["agent-squad-other-abcdef-v1"] = {source: {source: "directory", path: "/elsewhere/.agent-squad"}}
    | .extraKnownMarketplaces["agent-squad-moved-123abc"] = {source: {source: "directory", path: "/moved/.agent-squad"}}
    | .extraKnownMarketplaces["agent-squad-ui-facade"] = {source: {source: "directory", path: "/ui"}}
    | .enabledPlugins["ui@agent-squad-ui-facade"] = true
    | .extraKnownMarketplaces["agent-squad-x-202610"] = {source: {source: "directory", path: "/x"}}
    | .extraKnownMarketplaces["shelf"] = {source: {source: "directory", path: "/shelf/.agent-squad"}}
    | .enabledPlugins["squad-board@agent-squad-other-abcdef-v1"] = true
    | .extraKnownMarketplaces["team-tools"] = {source: {source: "directory", path: "/tools"}}
    | .enabledPlugins["lint@team-tools"] = true
    | .extraKnownMarketplaces["agent-squad-tools"] = {source: {source: "directory", path: "/more-tools"}}
    | .enabledPlugins["format@agent-squad-tools"] = true' "$lab/mods-on" > "$tsettings"
  check "the squad's names that are not this project's fail the mods item, named" \
    contains "$(mods_items "$target")" "check: FAILED  $item_mods: missing: none; unexpected: agent-squad-moved-123abc, agent-squad-other-abcdef-v1, squad-board@agent-squad-other-abcdef-v1; install again"
  "$tsquad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$target" "$tag_b" >/dev/null 2>&1
  check "an install removes them and keeps the project's own marketplaces and plugins" \
    jq_holds "(.extraKnownMarketplaces | keys) == [\"$name_a\", \"agent-squad-tools\", \"agent-squad-ui-facade\", \"agent-squad-x-202610\", \"shelf\", \"team-tools\"]
      and .enabledPlugins == {\"squad-board@$name_a\": true, \"lint@team-tools\": true, \"format@agent-squad-tools\": true, \"ui@agent-squad-ui-facade\": true}" "$tsettings"
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
      bash -c 'jq -e "(.extraKnownMarketplaces | keys) == [\"agent-squad-tools\", \"agent-squad-ui-facade\", \"agent-squad-x-202610\", \"shelf\", \"team-tools\"] and .enabledPlugins == {\"lint@team-tools\": true, \"format@agent-squad-tools\": true, \"ui@agent-squad-ui-facade\": true}" "$1" >/dev/null && [ ! -e "$2" ]' \
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
    jq_holds '(.extraKnownMarketplaces | keys) == ["agent-squad-tools", "agent-squad-ui-facade", "agent-squad-x-202610", "shelf", "team-tools"]
      and .enabledPlugins == {"lint@team-tools": true, "format@agent-squad-tools": true, "ui@agent-squad-ui-facade": true}' "$tsettings"
}

# Case 20: the uninstaller (#263), run as a project runs it, from its installed playbook.
cases_uninstall() {
  # 20. An install, then an uninstall, leaves the project as it was, but for the tracked files the
  #     squad added, which it lists for the CTO: the project's own settings, pre-push and tracked
  #     command stay, the records stay in .agent-squad/ unless --records, a dry run changes
  #     nothing, and a second run finds nothing left. It runs from a copy of itself, which it
  #     removes, so that removing the playbook it lives in does not cut it short.
  target="$(new_project removable)" || exit 2
  mkdir -p "$target/.claude/commands"
  jq -n '{permissions: {allow: ["Bash(ls:*)"]}, claudeMdExcludes: ["**/vendor/CLAUDE.md"],
    hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "echo own hook"}]}]},
    extraKnownMarketplaces: {"agent-squad-tools": {source: {source: "directory", path: "/more-tools"}}}}' \
    > "$target/.claude/settings.local.json"
  echo "the project's own command" > "$target/.claude/commands/squad-own.md"
  printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$target/AGENTS.md"
  git -C "$target" add -f .claude/commands/squad-own.md AGENTS.md && git -C "$target" commit -qm "a command of the project's own" || exit 2
  printf '#!/bin/sh\necho the project pre-push\n' > "$target/.git/hooks/pre-push" && chmod +x "$target/.git/hooks/pre-push"
  # `outside_squad <project>` lists its files as tree_state does, but for the squad's directory,
  # the settings, which installs rewrite as jq prints JSON, and the tracked files the squad adds.
  outside_squad() {
    tree_state "$1" | grep -vE ' \./(\.agent-squad/|\.claude/settings\.local\.json$|\.gitignore$|\.github/ISSUE_TEMPLATE/task\.md$)'
  }
  files_before="$(outside_squad "$target")" hooks_before="$(tree_state "$target/.git/hooks")"
  settings_before="$(jq -S . "$target/.claude/settings.local.json")"
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  mkdir -p "$target/.agent-squad/handoff" "$target/.agent-squad/evidence/7"
  echo snapshot > "$target/.agent-squad/handoff/x.md" && echo evidence > "$target/.agent-squad/evidence/7/a.txt"
  echo "a token record" > "$target/.agent-squad/tokens.tsv"
  cp "$target/.agent-squad/playbook/scripts/squad-uninstall.sh" "$lab/uninstall-copy.sh"
  mkdir -p "$lab/tmp-u"
  # `uninstall_state` is everything an uninstall may change: the project's files, its git hooks,
  # its worktrees and its settings.
  uninstall_state() { project_state "$target"; git -C "$target" worktree list; cat "$target/.claude/settings.local.json" 2>/dev/null; }
  state="$(uninstall_state)"
  out="$(TMPDIR="$lab/tmp-u" "$target/.agent-squad/playbook/scripts/squad-uninstall.sh" --dry-run "$target" 2>&1)"
  code=$?
  check "a dry run exits 0, says what it would remove, and changes nothing" \
    bash -c '[ "$1" -eq 0 ] && grep -qF "uninstall: squad      would remove .agent-squad/ but for the records" <<<"$2" && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$state" "$(uninstall_state)"
  #   It makes no copy of itself, which it would only need to remove the playbook (agent-squad
  #   #473): with a TMPDIR that does not exist, where no copy can go, it runs all the same.
  dry_out="$out"
  out="$(TMPDIR="$lab/no-such-tmp" "$target/.agent-squad/playbook/scripts/squad-uninstall.sh" --dry-run "$target" 2>&1)"
  code=$?
  check "and makes no copy of itself: with a TMPDIR that does not exist, it says the same" \
    bash -c '[ "$1" -eq 0 ] && [ "$2" = "$3" ]' _ "$code" "$out" "$dry_out"
  out="$(TMPDIR="$lab/tmp-u" "$target/.agent-squad/playbook/scripts/squad-uninstall.sh" "$target" 2>&1)"
  code=$?
  check "an uninstall run from the playbook it removes exits 0" [ "$code" -eq 0 ]
  check "and leaves the project's files as they were before the install, but for the tracked ones it lists" \
    [ "$(outside_squad "$target")" = "$files_before" ]
  check "and the project's own settings, its hook, its marketplace and its exclude, without the squad's hooks, mods and excludes" \
    [ "$(jq -S . "$target/.claude/settings.local.json")" = "$settings_before" ]
  check "and the project's own pre-push back in its place, the shim gone" [ "$(tree_state "$target/.git/hooks")" = "$hooks_before" ]
  check "and no worktree left" [ "$(git -C "$target" worktree list | wc -l | tr -d ' ')" -eq 1 ]
  check "and the command the project tracks, saying so" \
    bash -c '[ -f "$1/.claude/commands/squad-own.md" ] && grep -qF "kept /squad-own, which the project tracks" <<<"$2"' _ "$target" "$out"
  check "and of .agent-squad/ only the records" \
    [ "$(find "$target/.agent-squad" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ')" = "evidence handoff tokens.tsv " ]
  # The project's own settings stay, so the line that ignores them is kept (agent-squad #291).
  check "and it lists the tracked files for the CTO: .gitignore's lines but the settings', and the squad's issue template, not the project's own" \
    bash -c 'grep -qF ".gitignore'"'"'s lines .agent-squad/, .claude/commands/squad-*.md; keep .agent-squad/ while the records stay there; keep .claude/settings.local.json'"'"'s line, since the project'"'"'s own settings stay" <<<"$1" \
      && grep -qF ".github/ISSUE_TEMPLATE/task.md, the squad'"'"'s template" <<<"$1" && ! grep -qF PULL_REQUEST_TEMPLATE <<<"$1"' _ "$out"
  check "and the Squad section of AGENTS.md, which imports the charter" \
    contains "$out" "the Squad section of AGENTS.md, which imports the charter"
  check "and leaves no copy of itself behind" [ -z "$(ls -A "$lab/tmp-u")" ]
  state="$(uninstall_state)"
  out="$(TMPDIR="$lab/tmp-u" "$lab/uninstall-copy.sh" "$target" 2>&1)"
  code=$?
  check "a second run exits 0, finds nothing left to remove, and changes nothing" \
    bash -c '[ "$1" -eq 0 ] && grep -qF "nothing of the squad'"'"'s is left to remove here" <<<"$2" && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$state" "$(uninstall_state)"
  out="$(TMPDIR="$lab/tmp-u" "$lab/uninstall-copy.sh" --records "$target" 2>&1)"
  check "--records removes the records, and .agent-squad/ with them" \
    bash -c '[ ! -e "$1/.agent-squad" ] && grep -qF "uninstall: squad      removed .agent-squad/" <<<"$2"' _ "$target" "$out"
  #     Once the CTO's PR has removed the tracked files it listed, as /squad-uninstall orders it, a
  #     run finds nothing of the squad's, and nothing left for the CTO.
  sed -i.bak -e '/^\.agent-squad\/$/d' -e '/^\.claude\/commands\/squad-\*\.md$/d' "$target/.gitignore" && rm -f "$target/.gitignore.bak"
  sed -i.bak '/^@\.agent-squad\/playbook\/SQUAD\.md$/d' "$target/AGENTS.md" && rm -f "$target/AGENTS.md.bak"
  rm -f "$target/.github/ISSUE_TEMPLATE/task.md" "$target/.agent-squad-checks"
  out="$(TMPDIR="$lab/tmp-u" "$lab/uninstall-copy.sh" "$target" 2>&1)"
  code=$?
  check "after the CTO's PR, a run exits 0, finds nothing of the squad's, and leaves nothing for the CTO" \
    bash -c '[ "$1" -eq 0 ] && grep -qxF "uninstall: nothing    nothing of the squad'"'"'s is left to remove here" <<<"$2" \
      && [ "$(sed -n "/^By hand, for the CTO/,\$p" <<<"$2")" = "$(printf "By hand, for the CTO, through a PR: the tracked files the squad added\n  nothing")" ]' \
    _ "$code" "$out"

  # 20b. A worktree git refuses to remove, as a locked one, stays, and so does .agent-squad/, which
  #      would take it along; the run needs a decision. Then, with it unlocked, a settings file that
  #      is not one JSON object is left as it is, saying so, and needs one too.
  target="$(new_project stuck)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  git -C "$target" worktree lock "$target/.agent-squad/worktrees/dev" || exit 2
  out="$(TMPDIR="$lab/tmp-u" "$target/.agent-squad/playbook/scripts/squad-uninstall.sh" "$target" 2>&1)"
  code=$?
  check "a worktree git refuses to remove stays, and so does .agent-squad/, saying so, with exit 1" \
    bash -c '[ "$1" -eq 1 ] && grep -qF "NOT REMOVED: worktrees/dev: git refused it; .agent-squad/ is left as it is" <<<"$2" \
      && [ -d "$3/.agent-squad/worktrees/dev" ] && [ -f "$3/.agent-squad/playbook/SQUAD.md" ]' _ "$code" "$out" "$target"
  git -C "$target" worktree unlock "$target/.agent-squad/worktrees/dev" || exit 2
  #      That first run removed the settings, which held only the squad's: a broken one comes back.
  mkdir -p "$target/.claude" && printf '{"hooks": {}} {"hooks": {}}\n' > "$target/.claude/settings.local.json"
  cp "$target/.claude/settings.local.json" "$lab/stuck-settings"
  out="$(TMPDIR="$lab/tmp-u" "$target/.agent-squad/playbook/scripts/squad-uninstall.sh" "$target" 2>&1)"
  code=$?
  check "a settings file that is not one JSON object is left as it is, saying so, with exit 1" \
    bash -c '[ "$1" -eq 1 ] && grep -qF "NOT REMOVED: .claude/settings.local.json is not one JSON object; it is left as it is" <<<"$2" \
      && cmp -s "$3" "$4"' _ "$code" "$out" "$lab/stuck-settings" "$target/.claude/settings.local.json"
  check "and the rest is removed: no worktree is left" [ "$(git -C "$target" worktree list | wc -l | tr -d ' ')" -eq 1 ]
}

#   And what it refuses: work in a worktree, a place that is not the main checkout, bad usage. The
#   hooks as releases before v49 wrote them are the squad's too. What a worktree holds that git
#   ignores, such as a key in a .env, is moved aside into .agent-squad/kept/ and kept.
cases_uninstall_refusals() {
  target="$(new_project unremovable)" || exit 2
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  uninstall="$target/.agent-squad/playbook/scripts/squad-uninstall.sh"
  state() { project_state "$target"; git -C "$target" worktree list; cat "$target/.claude/settings.local.json" 2>/dev/null; }
  before="$(state)"
  echo "work in progress" > "$target/.agent-squad/worktrees/dev/notes.txt"
  before="$(state)"
  out="$("$uninstall" "$target" 2>&1)"
  code=$?
  check "a worktree with changes not committed stops the uninstall, exit 1, naming them, and nothing is removed" \
    bash -c '[ "$1" -eq 1 ] && grep -qF "uninstall: refused    worktrees/dev has changes that are not committed: notes.txt" <<<"$2" && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$before" "$(state)"
  #   A refusal and bad usage make no copy either (agent-squad #473): with a TMPDIR that does not
  #   exist, they say the same.
  refused_out="$out"
  out="$(TMPDIR="$lab/no-such-tmp" "$uninstall" "$target" 2>&1)"
  code=$?
  check "and makes no copy of itself: with a TMPDIR that does not exist, it refuses the same way" \
    bash -c '[ "$1" -eq 1 ] && [ "$2" = "$3" ]' _ "$code" "$out" "$refused_out"
  out="$(TMPDIR="$lab/no-such-tmp" "$uninstall" --bogus "$target" 2>&1)"
  code=$?
  check "and bad usage, which prints its usage, with exit 2" \
    bash -c '[ "$1" -eq 2 ] && [[ "$2" == "usage: squad-uninstall.sh "* ]]' _ "$code" "$out"
  rm "$target/.agent-squad/worktrees/dev/notes.txt"
  git -C "$target/.agent-squad/worktrees/qa" commit -q --allow-empty -m "a commit no remote holds"
  before="$(state)"
  out="$("$uninstall" "$target" 2>&1)"
  code=$?
  check "and so does one with a commit that no remote branch holds" \
    bash -c '[ "$1" -eq 1 ] && grep -qF "uninstall: refused    worktrees/qa has 1 commit(s) that no remote branch holds" <<<"$2" && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$before" "$(state)"
  git -C "$target/.agent-squad/worktrees/qa" switch -q --detach origin/main
  out="$("$uninstall" "$target/.agent-squad/worktrees/dev" 2>&1)"
  code=$?
  check "a linked worktree is not the main checkout: exit 2" \
    bash -c '[ "$1" -eq 2 ] && grep -qF "is not the project'"'"'s main checkout" <<<"$2"' _ "$code" "$out"
  for args in "" "--bogus $target" "--dry-run" "$target extra"; do
    # shellcheck disable=SC2086 # the arguments are split on purpose
    "$uninstall" $args >/dev/null 2>&1
    code=$?
    check "'$args' is bad usage, exit 2" [ "$code" -eq 2 ]
  done
  # Without jq, the uninstaller stops before it removes anything, as the installer does (#405).
  before="$(state)"
  out="$(PATH="$(path_without jq)" "$uninstall" "$target" 2>&1)"
  code=$?
  check "without jq the uninstaller exits 2, saying jq is required, and removes nothing" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "squad-uninstall: jq is required" ] && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$before" "$(state)"
  # What the dev worktree holds that git ignores, a .env with a key and a run's output: the dry run
  # names it, the run moves it into .agent-squad/kept/dev/ and keeps it (QA's review of PR #288),
  # and a second run leaves it there.
  printf '.env\nout/\n' >> "$target/.git/info/exclude"
  echo "SECRET=1" > "$target/.agent-squad/worktrees/dev/.env"
  mkdir -p "$target/.agent-squad/worktrees/dev/out" && echo "a result" > "$target/.agent-squad/worktrees/dev/out/results.txt"
  cp "$uninstall" "$lab/uninstall-again.sh"
  before="$(state)"
  out="$("$uninstall" --dry-run "$target" 2>&1)"
  code=$?
  check "a dry run names what a worktree holds that git ignores, and where it would go, and moves nothing" \
    bash -c '[ "$1" -eq 0 ] && grep -qF "uninstall: kept       would move what worktrees/dev holds that git ignores into .agent-squad/kept/dev/: .env, out/" <<<"$2" && [ "$3" = "$4" ]' \
    _ "$code" "$out" "$before" "$(state)"
  # The five hooks as v48 wrote them, beside nothing of the project's: the settings go entirely.
  old='f="$CLAUDE_PROJECT_DIR"/.agent-squad/playbook/scripts/squad-handoff.sh; if [ -x "$f" ]; then "$f" '
  jq --arg old "$old" '.hooks = {PreCompact: [{matcher: "manual", hooks: [{type: "command", command: ($old + "save; fi")}]},
    {matcher: "auto", hooks: [{type: "command", command: ($old + "save; fi")}]}],
    SessionStart: [{matcher: "startup", hooks: [{type: "command", command: ($old + "startup; else echo missing; fi")}]}]}' \
    "$target/.claude/settings.local.json" > "$lab/v48-settings.json" && cp "$lab/v48-settings.json" "$target/.claude/settings.local.json"
  # A dry run, which leaves the settings there, lists their line as the run that removes them does.
  out="$("$uninstall" --dry-run "$target" 2>&1)"
  check "a dry run whose settings would go lists their .gitignore line for the CTO, though the file is still there" \
    bash -c '[ -f "$1/.claude/settings.local.json" ] && grep -qF ".gitignore'"'"'s lines .agent-squad/, .claude/settings.local.json, .claude/commands/squad-*.md" <<<"$2"' _ "$target" "$out"
  out="$("$uninstall" "$target" 2>&1)"
  code=$?
  check "hooks as releases before v49 wrote them are the squad's too: with the mods, the settings go entirely" \
    bash -c '[ "$1" -eq 0 ] && [ ! -e "$2/.claude" ] && grep -qF "removed .claude/settings.local.json, which held only the squad'"'"'s hooks, mods and excludes" <<<"$3"' \
    _ "$code" "$target" "$out"
  check "and what the worktree held that git ignores is in .agent-squad/kept/dev/, the .env with its key" \
    bash -c '[ "$(cat "$1/.agent-squad/kept/dev/.env")" = SECRET=1 ] && [ "$(cat "$1/.agent-squad/kept/dev/out/results.txt")" = "a result" ] && [ ! -e "$1/.agent-squad/worktrees" ]' _ "$target"
  check "kept like the records, as the output says" \
    bash -c 'grep -qF "moved what worktrees/dev holds that git ignores into .agent-squad/kept/dev/: .env, out/" <<<"$1" && grep -qF "removed .agent-squad/ but for the records, kept" <<<"$1"' _ "$out"
  check "and with the settings gone, it lists their .gitignore line for the CTO too" \
    bash -c 'grep -qF ".gitignore'"'"'s lines .agent-squad/, .claude/settings.local.json, .claude/commands/squad-*.md; keep .agent-squad/ while the records stay there" <<<"$1" && ! grep -qF "since the project'"'"'s own settings stay" <<<"$1"' _ "$out"
  out="$("$lab/uninstall-again.sh" "$target" 2>&1)"
  code=$?
  check "and a second run finds nothing left to remove, and leaves the kept files where they are" \
    bash -c '[ "$1" -eq 0 ] && grep -qF "nothing of the squad'"'"'s is left to remove here; its records stay" <<<"$2" && [ "$(cat "$3/.agent-squad/kept/dev/.env")" = SECRET=1 ]' \
    _ "$code" "$out" "$target"
  # Installed again and removed again, with another .env: the first kept/dev/ stays as it was, and the
  # new one goes beside it, under a name of its own.
  "$install" "$target" "$tag_a" >/dev/null 2>&1
  echo "SECRET=2" > "$target/.agent-squad/worktrees/dev/.env"
  "$target/.agent-squad/playbook/scripts/squad-uninstall.sh" "$target" >/dev/null 2>&1
  check "a later uninstall keeps what an earlier one kept, and puts its own beside it" \
    bash -c '[ "$(cat "$1/.agent-squad/kept/dev/.env")" = SECRET=1 ] && [ "$(cat "$1"/.agent-squad/kept/dev.*/.env)" = SECRET=2 ]' _ "$target"
}

# Cases 18 and 18b on names.
cases_quoted_names() {
  # 18. The next steps quote the project's name for the shell (agent-squad #262): a folder whose name
  #     holds a blank, double quotes, a dollar and a backquote gives sessions named after it, as the
  #     shell reads each printed line.
  odd='odd "one" $HOME `x`'
  target="$(new_project "$odd")" || exit 2
  out="$("$install" "$target" "$tag_a" 2>&1)"
  # `hook_reached <project>` runs its compact hook as Claude Code would, and passes when it reaches
  # the wrapper, whose path the command quotes for sh (agent-squad #319): it re-orients, and exits 0.
  hook_reached() {
    local command out
    command="$(jq -r '[.hooks.SessionStart[] | select(.matcher == "compact") | .hooks[].command][0]' "$1/.claude/settings.local.json")"
    out="$(cd "$1" && echo '{"session_id":"x"}' | CLAUDE_PROJECT_DIR="$1" sh -c "$command")" && contains "$out" "Context was compacted"
  }
  check "its hooks' command, the wrapper's path quoted for sh, reaches the wrapper" hook_reached "$target"
  check "a project whose name the shell would expand gets it quoted in the next steps" \
    ends_with_next_steps "$out" 'odd \"one\" \$HOME \`x\`'
  # `named_by <line>` runs a printed `claude -n` line with a claude that prints the name it is given;
  # `pasted_by <line>` runs it as a line pasted into an interactive bash, whose history expansion
  # reads a `!` even inside double quotes (agent-squad #267).
  named_by() { bash -c "claude() { printf '%s' \"\$2\"; }; $1"; }
  pasted_by() {
    local named_file="$lab/named.txt"
    rm -f "$named_file"
    { printf '%s\n' "claude() { printf '%s' \"\$2\" > '$named_file'; }"; printf '%s\n' "$1"; } \
      | bash --norc --noprofile -i >/dev/null 2>&1
    cat "$named_file" 2>/dev/null
  }
  dev_line="$(grep -F '    claude -n "DEV:' <<<"$out")"
  check "and each printed line, run by the shell, names the session after the project, as it is" \
    [ "$(named_by "$dev_line")" = "DEV:$odd" ]
  check "and so does the line pasted into an interactive bash" [ "$(pasted_by "$dev_line")" = "DEV:$odd" ]

  # 18b. A name with a `!` goes in single quotes, which an interactive shell does not expand, and an
  #      apostrophe in it is written '\'' (agent-squad #267). GitHub's repository names cannot hold a
  #      `!`; a renamed folder can.
  bang="it's a!b"
  target="$(new_project "$bang")" || exit 2
  out="$("$install" "$target" "$tag_a" 2>&1)"
  dev_line="$(grep -F '    claude -n ' <<<"$out" | grep -F 'DEV:')"
  check "its hooks' command, an apostrophe in the path written '\\'', reaches the wrapper" hook_reached "$target"
  check "a name with a ! is printed in single quotes" \
    [ "$dev_line" = "    claude -n 'DEV:it'\\''s a!b'" ]
  check "and the line pasted into an interactive bash names the session after the project, as it is" \
    [ "$(pasted_by "$dev_line")" = "DEV:$bang" ]
}

# The groups run side by side, each in its lab (agent-squad #245), and the slowest sets how long the
# check takes. Each group's lines are printed once it has ended, after a line that names it and gives
# its time, group after group in the order below. The check fails when a group does, when one stops
# before its end (exit 2), when one runs no check, and when a group is defined here but not run.
# They start under job control, each in a process group of its own, which the exit trap ends: without
# it, a command started in the background ignores SIGINT, and so would every --check case 14
# interrupts with it.
groups=(
  cases_main_project
  cases_release
  cases_upgrade_output
  cases_lfs
  cases_decisions
  cases_check_settings
  cases_check_commands_odd
  cases_check_commands_even
  cases_check_gate
  cases_check_import
  cases_uncommitted
  cases_template_changes
  cases_default_branch
  cases_ssh_keepalive
  cases_unanswered
  cases_failure_paths
  cases_failure_installs
  cases_machine_excludes
  cases_moved_checkout
  cases_leftover_commands
  cases_mods
  cases_uninstall
  cases_uninstall_refusals
  cases_quoted_names
)
pids=()
set -m
for group in "${groups[@]}"; do
  (
    in_lab "$group" || exit 2
    started=$SECONDS
    "$group"
    echo "$((SECONDS - started))" > "$lab.seconds"
    exit "$status"
  ) </dev/null >"$labs/$group.log" 2>&1 &
  pids+=("$!")
done
set +m
for i in "${!groups[@]}"; do
  group="${groups[$i]}"
  wait "${pids[$i]}"
  code=$?
  echo "check-install: $group ($(cat "$labs/$group.seconds" 2>/dev/null || echo "?") s)" >&2
  cat "$labs/$group.log" >&2
  grep -qE '^  (ok|FAILED)  ' "$labs/$group.log" || fail "$group ran no check"
  [ "$code" -le 1 ] || fail "$group stopped before its end, with exit $code"
  [ "$code" -le "$status" ] || status="$code"
done
for group in $(compgen -A function cases_); do
  [[ " ${groups[*]} " == *" $group "* ]] || fail "$group is a group of cases that no run starts"
done
exit "$status"
