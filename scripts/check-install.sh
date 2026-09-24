#!/usr/bin/env bash
# Check that scripts/squad-install.sh behaves as agent-squad #35 and #36 say, in throw-away
# repositories:
# a fresh install from a tag's tarball, a second run that changes nothing, a project's own
# settings, pre-push and pre-commit kept working, the gate refusing a failing check through the
# shim and refusing every push when the playbook is missing, the hook commands warning when it is
# missing, an upgrade that replaces the playbook and nothing else, a failed download that leaves it
# as it was, the steps that need a decision, and --check passing on a good installation and failing
# on the right line for each item broken on purpose. GitHub is replaced by a `gh` that serves a tarball
# built here with `git archive`, as GitHub builds it; this script never touches the repository it
# is run from.
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

lab="$(mktemp -d)" || exit 2
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
# string in a text, `matches_none` for an extended regular expression.
refused() { ! "$@"; }
contains() { grep -qF -- "$2" <<<"$1"; }
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
item_hooks="the four hooks are in .claude/settings.local.json and point at the playbook"
item_ignore=".gitignore ignores .agent-squad/ and .claude/settings.local.json"
item_shim="the pre-push shim is installed and core.hooksPath is unset"
item_gate="the gate refuses a failing check and lets a passing one through"
item_list=".agent-squad-checks exists and is tracked"
item_worktrees=".agent-squad/worktrees/dev and qa are worktrees of this repository"
item_import="CLAUDE.md links to AGENTS.md, which imports the charter"
# `check_reports [<item>...]` runs --check on the project and passes when the items that fail are
# exactly those given, with exit 1; with none given, when every item passes, with exit 0.
check_reports() {
  local out code failed
  out="$("$install" --check "$project" 2>&1)"
  code=$?
  failed="$(sed -n 's/^check: FAILED  \([^:]*\):.*/\1/p' <<<"$out" | LC_ALL=C sort)"
  if [ $# -eq 0 ]; then
    [ "$code" -eq 0 ] && [ -z "$failed" ] && [ "$(grep -c '^check: ok ' <<<"$out")" -eq 9 ]
  else
    [ "$code" -eq 1 ] && [ "$failed" = "$(printf '%s\n' "$@" | LC_ALL=C sort)" ]
  fi
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
# `detached_at_origin_main <project> <worktree>`: a linked worktree, detached, at origin/main.
detached_at_origin_main() {
  [ -f "$2/.git" ] \
    && [ "$(git -C "$2" rev-parse HEAD)" = "$(git -C "$1" rev-parse origin/main)" ] \
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
export GH_TAG=va GH_TARBALL="$lab/va.tgz"
mkdir -p "$lab/va" && tar -xzf "$lab/va.tgz" -C "$lab/va" --strip-components=1 || exit 2
# Tree B, the next version: one file changed, one removed, one added.
mkdir -p "$lab/vb" && cp -pR "$lab/va/." "$lab/vb/" || exit 2
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
out="$("$install" "$project" va 2>&1)"
code=$?
check "a fresh install exits 0" [ "$code" -eq 0 ]
check "the playbook is the tag's tree, file for file" same_tree "$squad/playbook" "$lab/va"
check "the playbook leaves out agent-squad's own AGENTS.md, CLAUDE.md, checks, CI and tests" \
  absent "$squad/playbook" AGENTS.md CLAUDE.md .agent-squad-checks .github/workflows \
  scripts/check-install.sh
check "install.log has one line" [ "$(log_lines "$project")" -eq 1 ]
check "which says none -> va" log_ends_with "$project" "none -> va"
check ".gitignore has .agent-squad/ and .claude/settings.local.json" \
  has_lines "$project/.gitignore" ".agent-squad/" ".claude/settings.local.json"
check "the missing issue template was created from the playbook" \
  cmp -s "$squad/playbook/.github/ISSUE_TEMPLATE/task.md" "$project/.github/ISSUE_TEMPLATE/task.md"
check "the project's own PR template was kept" \
  has_lines "$project/.github/PULL_REQUEST_TEMPLATE.md" "The project's own PR template."
for agent in dev qa; do
  check "worktrees/$agent is a linked worktree detached at origin/main" \
    detached_at_origin_main "$project" "$squad/worktrees/$agent"
done
check "the Squad section of the playbook's templates/AGENTS.md is printed" \
  contains "$out" "The squad section this test expects, first line."
check "with its import line" contains "$out" "@.agent-squad/playbook/SQUAD.md"
check "and nothing after the section" lacks "$out" "Not part of the section."
check "--check after a fresh install fails only on what is left by hand, AGENTS.md" check_reports "$item_import"

# 2. The project's local settings are kept; only the entries that run squad-handoff.sh change.
ours='[.hooks[][] | select(any(.hooks[]; .command | contains("squad-handoff.sh"))) | .matcher]'
check "settings.local.json keeps the project's permissions" \
  jq_holds '.permissions.allow == ["Bash(ls:*)"]' "$settings"
check "and the project's own hook" \
  jq_holds '.hooks.PreToolUse[0].hooks[0].command == "echo own hook"' "$settings"
check "and has the four squad hooks once each, the older entry replaced" \
  jq_holds "$ours == [\"manual\", \"auto\", \"compact\", \"startup\"]" "$settings"

# 3. A second run changes nothing but the log, which gains one line.
before="$(project_state "$project")"
lines_before="$(log_lines "$project")"
out="$("$install" "$project" va 2>&1)"
code=$?
check "a second run exits 0" [ "$code" -eq 0 ]
check "a second run changes no file, the git hooks included" [ "$before" = "$(project_state "$project")" ]
check "a second run adds one line to install.log" [ "$(log_lines "$project")" -eq $((lines_before + 1)) ]
check "which says va -> va" log_ends_with "$project" "va -> va"
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
for matcher in startup compact; do
  check "the $matcher hook warns that the charter is not installed" \
    prints "charter is not installed" run_hook "$matcher"
done
check "the save hook does nothing and exits 0" prints_nothing run_hook manual
mv "$lab/playbook-aside" "$squad/playbook"
check "with the playbook back, the startup hook prints nothing" prints_nothing run_hook startup
check "and the compact hook re-orients the session" prints "Context was compacted" run_hook compact

# 7. An upgrade replaces the playbook whole and leaves the rest of .agent-squad/ alone. It is run
#    as the README says, by the installed installer, which replaces the directory it runs from.
mkdir -p "$squad/handoff" "$squad/evidence/7"
echo snapshot > "$squad/handoff/x.md"
echo evidence > "$squad/evidence/7/screen.txt"
echo work > "$dev/work-in-progress.txt"
runtime_state() { tree_state "$squad/worktrees"; tree_state "$squad/handoff"; tree_state "$squad/evidence"; }
runtime_before="$(runtime_state)"
out="$("$squad/playbook/scripts/squad-install.sh" --source "$lab/vb" "$project" vb 2>&1)"
code=$?
check "an upgrade exits 0" [ "$code" -eq 0 ]
check "the playbook is now vb, file for file (one changed, one removed, one added)" \
  same_tree "$squad/playbook" "$lab/vb"
check "worktrees/, handoff/ and evidence/ are untouched" [ "$runtime_before" = "$(runtime_state)" ]
check "install.log ends with va -> vb" log_ends_with "$project" "va -> vb"

# 8. A failed download or an incomplete tree leaves the installed playbook as it was.
echo "not a tarball" > "$lab/broken.tgz"
out="$(GH_TAG=vc GH_TARBALL="$lab/broken.tgz" "$install" "$project" vc 2>&1)"
code=$?
check "a download that is not a tarball exits 2" [ "$code" -eq 2 ]
check "and leaves the playbook as it was" same_tree "$squad/playbook" "$lab/vb"
check "with nothing left behind" no_leftovers "$squad"
mkdir -p "$lab/incomplete" && cp -pR "$lab/vb/." "$lab/incomplete/" && rm "$lab/incomplete/SQUAD.md"
out="$("$install" --source "$lab/incomplete" "$project" vd 2>&1)"
code=$?
check "a tree without SQUAD.md exits 2" [ "$code" -eq 2 ]
check "and leaves the playbook as it was" same_tree "$squad/playbook" "$lab/vb"
check "and neither failure wrote to install.log" matches_none "$(cat "$squad/install.log")" " -> (vc|vd)$"

# 9. With core.hooksPath set, the shim is not installed, the reason is printed and the exit is 1.
other="$(new_project other)" || exit 2
git -C "$other" config core.hooksPath .githooks
out="$("$install" "$other" va 2>&1)"
code=$?
check "with core.hooksPath set the installer exits 1" [ "$code" -eq 1 ]
check "and says why" contains "$out" "pre-push   NOT INSTALLED: core.hooksPath is set"
check "and writes no shim" absent "$other" .git/hooks/pre-push
check "while the other steps are done" present "$other" .agent-squad/playbook/SQUAD.md

# 10. Only the main checkout is accepted.
out="$("$install" "$dev" va 2>&1)"
code=$?
check "a linked worktree is refused with exit 2" [ "$code" -eq 2 ]
check "and nothing is created in it" absent "$dev" .agent-squad

# 11. --check passes on a complete installation, changes nothing, and fails on the right line for
#     each item broken on purpose; each breakage is undone before the next.
printf '# AGENTS.md\n\n## Squad\n@.agent-squad/playbook/SQUAD.md\n' > "$project/AGENTS.md"
ln -s AGENTS.md "$project/CLAUDE.md"
before="$(project_state "$project")$(cat "$squad/install.log")"
check "--check passes on a complete installation, nine items ok" check_reports
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

broken "$project/.gitignore"
grep -vx ".claude/settings.local.json" "$lab/mend.me" > "$project/.gitignore"
check "a missing ignore line fails the .gitignore item" check_reports "$item_ignore"
mended "$project/.gitignore"

git -C "$project" config core.hooksPath .githooks
check "a set core.hooksPath fails the shim item" check_reports "$item_shim"
git -C "$project" config --unset core.hooksPath

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

mv "$squad/worktrees/qa" "$lab/qa-aside"
check "a missing worktree fails the worktrees item" check_reports "$item_worktrees"
mv "$lab/qa-aside" "$squad/worktrees/qa"

broken "$project/AGENTS.md"
printf '# AGENTS.md\n' > "$project/AGENTS.md"
check "a missing import fails the import item" check_reports "$item_import"
mended "$project/AGENTS.md"

check "with every breakage undone, --check passes again" check_reports

exit "$status"
