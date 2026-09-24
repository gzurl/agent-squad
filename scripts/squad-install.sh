#!/usr/bin/env bash
# Install, upgrade or check the squad in a project (agent-squad #23): the tag's playbook in
# <project>/.agent-squad/playbook/, the compaction hooks in .claude/settings.local.json, a pre-push
# shim that runs the playbook's gate, the GitHub templates the project lacks, and the DEV and QA
# worktrees. It never overwrites or deletes a file the project owns, prints one line per action
# taken or skipped, and ends with what is left to do by hand.
#
# Usage: squad-install.sh [--source <dir>] <project main checkout> <tag>
#        squad-install.sh --check <project main checkout>
#   --source <dir>  install the tree in <dir> (an extracted tarball, for tests) instead of
#                   downloading the tag from GitHub
#   --check         change nothing: print one status line per item of the installation, including
#                   whether the gate really refuses a failing check
# Exit: 0 installed; 1 installed except the steps marked NOT, which need a decision; 2 bad usage, a
#       missing prerequisite, or a download or extraction that failed: nothing outside
#       .agent-squad/ was touched and the installed playbook is unchanged.
#       With --check: 0 every item passes; 1 at least one failed; 2 bad usage.
set -u

upstream="gzurl/agent-squad"
shim_marker="agent-squad pre-push shim"

# `say <step> <message>` prints one action taken or skipped; `die <message>` stops before any step.
say() { printf 'install: %-10s %s\n' "$1" "$2"; }
die() { echo "squad-install: $1" >&2; exit 2; }

# Run from a hook, git's own variables would point every git command below at another repository.
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars 2>/dev/null)

# Arguments: the tag names a path in the download URL, so it is validated before use.
usage="usage: $0 [--source <dir>] <project main checkout> <tag> | --check <project main checkout>"
mode=install
source_dir=""
if [ "${1:-}" = "--check" ]; then
  mode=check
  shift
  [ $# -eq 1 ] || die "$usage"
else
  if [ "${1:-}" = "--source" ]; then
    [ $# -ge 2 ] || die "--source needs a directory"
    source_dir="$2"
    shift 2
  fi
  [ $# -eq 2 ] || die "$usage"
  tag="$2"
  case "$tag" in
    ''|*[!A-Za-z0-9._-]*) die "'$tag' is not a tag name" ;;
  esac
fi
for tool in git jq tar awk; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done
if [ "$mode" = install ] && [ -z "$source_dir" ]; then
  command -v gh >/dev/null 2>&1 || die "gh is required to download the tag"
fi

# The project is named by its main checkout, the one directory every worktree shares (D7).
project="$(CDPATH='' cd -- "$1" 2>/dev/null && pwd -P)" || die "$1 is not a directory"
common_dir="$(git -C "$project" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || die "$project is not a git checkout (or git is older than 2.31)"
main_checkout="$(CDPATH='' cd -- "$(dirname "$common_dir")" && pwd -P)"
top_level="$(git -C "$project" rev-parse --show-toplevel 2>/dev/null)"
top_level="$(CDPATH='' cd -- "$top_level" 2>/dev/null && pwd -P)"
if [ "$project" != "$main_checkout" ] || [ "$top_level" != "$main_checkout" ]; then
  die "$project is not the project's main checkout; pass $main_checkout"
fi

squad="$project/.agent-squad"
playbook="$squad/playbook"
manifest_file="$squad/playbook.manifest"
log="$squad/install.log"
settings="$project/.claude/settings.local.json"
needs_decision=0
tracked_changes=()

# `manifest <dir>` lists every file of a tree with its kind and content hash, so that two trees
# compare equal only when they are the same byte for byte, executable bits and symlinks included.
manifest() {
  (cd "$1" && find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r path; do
    if [ -L "$path" ]; then
      echo "link $(readlink "$path") $path"
    elif [ -x "$path" ]; then
      echo "exec $(git hash-object --no-filters "$path") $path"
    else
      echo "file $(git hash-object --no-filters "$path") $path"
    fi
  done)
}

# The four compaction hooks as the installer writes them (D5, D10). Each command checks that the
# playbook's script exists, so that a missing playbook is reported to the session instead of
# failing it.
# shellcheck disable=SC2016 # expanded by the shell that runs the hook, not here
handoff='"$CLAUDE_PROJECT_DIR"/.agent-squad/playbook/scripts/squad-handoff.sh'
# shellcheck disable=SC2016 # same
missing='echo "Squad: the charter is not installed ($f is missing). Stop and tell the CTO before doing anything else."'
save_command="f=$handoff; if [ -x \"\$f\" ]; then \"\$f\" save; fi"
restore_command="f=$handoff; if [ -x \"\$f\" ]; then \"\$f\" restore; else $missing; fi"
startup_command="f=$handoff; if [ -x \"\$f\" ]; then \"\$f\" startup; else $missing; fi"

# The pre-push shim (D8), written into the common git directory so that every worktree runs it.
hooks_dir="$common_dir/hooks"
shim="$(cat <<'SHIM'
#!/usr/bin/env bash
# agent-squad pre-push shim, written by squad-install.sh, which rewrites it on every install.
# Runs the project's own pre-push (pre-push.local), if any, then the squad's gate from the main
# checkout's .agent-squad/playbook/. When the gate cannot be found, the push is refused.
set -u
hooks_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
refs="$(cat)"

# The project's own hook first, with the arguments and the input git gave this one.
if [ -x "$hooks_dir/pre-push.local" ]; then
  "$hooks_dir/pre-push.local" "$@" <<<"$refs" || exit
fi

# Then the gate, from the main checkout whichever worktree pushes; never a silent pass without it.
common_dir="$(git rev-parse --path-format=absolute --git-common-dir)" || exit 1
gate="$(dirname "$common_dir")/.agent-squad/playbook/.githooks/pre-push"
if [ ! -x "$gate" ]; then
  echo "pre-push: the squad's gate $gate is missing, so the push is refused. Reinstall the squad with squad-install.sh, or push with --no-verify and say so in the PR" >&2
  exit 1
fi
exec "$gate" "$@" <<<"$refs"
SHIM
)"

# --check: one status line per item of the installation (#36); it changes nothing in the project.
# `verdict <item> <why>` prints the item as ok when <why> is empty, as FAILED with <why> otherwise.
failed_items=0
verdict() {
  if [ -z "$2" ]; then
    printf 'check: ok      %s\n' "$1"
  else
    printf 'check: FAILED  %s: %s\n' "$1" "$2"
    failed_items=$((failed_items + 1))
  fi
}
# `join` turns lines into one comma-separated line.
join() { awk 'NR > 1 { printf ", " } { printf "%s", $0 }'; }
# `real_path <dir>` resolves symlinks, so that two spellings of one directory compare equal.
real_path() { (CDPATH='' cd -- "$1" 2>/dev/null && pwd -P); }

# `gate_refusal` proves that the playbook's gate runs, not only that it exists: in a throw-away
# repository whose hooks are the playbook's, a failing check must refuse the push and a passing one
# must let it through. It prints why when that is not so, and nothing otherwise.
gate_refusal() {
  local lab code
  lab="$(mktemp -d)" || { echo "cannot create a temporary directory"; return; }
  (
    # The machine's own git configuration (signing, templates, hooks) stays out of the test.
    export HOME="$lab" XDG_CONFIG_HOME="$lab" GIT_CONFIG_NOSYSTEM=1
    work="$lab/work"
    git init -q --bare -b main "$lab/remote.git" && git init -q -b main "$work" || exit 3
    git -C "$work" config core.hooksPath "$playbook/.githooks"
    git -C "$work" config user.name "Squad check" && git -C "$work" config user.email check@example.com
    git -C "$work" remote add origin "$lab/remote.git"
    # `push_with <check>` commits a list with that one check and pushes it.
    push_with() {
      printf '%s\n' "$1" > "$work/.agent-squad-checks"
      git -C "$work" add -A && git -C "$work" commit -qm "$1" \
        && git -C "$work" push -q origin HEAD:refs/heads/main >/dev/null 2>&1
    }
    push_with false && exit 4
    push_with true || exit 5
    exit 0
  )
  code=$?
  rm -rf "$lab"
  case "$code" in
    0) ;;
    3) echo "cannot build a throw-away repository" ;;
    4) echo "the playbook's gate let a push through with a failing check" ;;
    *) echo "the playbook's gate refused a push whose check passes" ;;
  esac
}

check_installation() {
  local why version agent worktree changed expected actual path

  # 9 first, as the heading of the report: which version is installed, and since when.
  version="$(grep -o '^> \*\*Version:\*\* [0-9]*' "$playbook/SQUAD.md" 2>/dev/null | grep -o '[0-9]*$')"
  if [ -n "$version" ]; then
    verdict "installed version $version (install.log: $(tail -1 "$log" 2>/dev/null || echo none))" ""
  else
    verdict "installed version" "no Version line in .agent-squad/playbook/SQUAD.md"
  fi

  # 1. The playbook is the tree that was installed, byte for byte.
  why=""
  if [ ! -d "$playbook" ]; then
    why="there is no .agent-squad/playbook/"
  elif [ ! -f "$manifest_file" ]; then
    why="no checksums were recorded when it was installed; install again"
  else
    changed="$(diff "$manifest_file" <(manifest "$playbook") | awk '/^[<>]/ { sub(/^\.\//, "", $NF); print $NF }' | sort -u | join)"
    [ -z "$changed" ] || why="changed since it was installed: $changed"
  fi
  verdict "playbook/ is complete and unmodified" "$why"

  # 2. The four hooks, exactly as the installer writes them.
  why=""
  expected="$(jq -cn --arg save "$save_command" --arg restore "$restore_command" \
    --arg startup "$startup_command" \
    '[["PreCompact", "manual", $save], ["PreCompact", "auto", $save],
      ["SessionStart", "compact", $restore], ["SessionStart", "startup", $startup]] | sort')"
  if ! actual="$(jq -c '[(.hooks // {}) | to_entries[] | .key as $event | .value[] | .matcher as $matcher
      | .hooks[] | select((.command // "") | contains("squad-handoff.sh"))
      | [$event, $matcher, .command]] | sort' "$settings" 2>/dev/null)"; then
    why="cannot read .claude/settings.local.json"
  elif [ "$actual" != "$expected" ]; then
    why="$(jq -rn --argjson want "$expected" --argjson have "$actual" \
      '"missing: \([($want - $have)[] | .[1]] | join(", ") | if . == "" then "none" else . end); unexpected: \([($have - $want)[] | .[1]] | join(", ") | if . == "" then "none" else . end)"')"
  fi
  verdict "the four hooks are in .claude/settings.local.json and point at the playbook" "$why"

  # 3. Both paths are ignored, by a rule of the project's own .gitignore.
  why="$(for path in .agent-squad .claude/settings.local.json; do
    [ "$(git -C "$project" check-ignore -v --no-index "$path" 2>/dev/null | cut -d: -f1)" = .gitignore ] \
      || echo "$path is not ignored by .gitignore"
  done | join)"
  verdict ".gitignore ignores .agent-squad/ and .claude/settings.local.json" "$why"

  # 4. The shim is the installer's, where git runs it.
  why=""
  hooks_path="$(git -C "$project" config --get core.hooksPath || true)"
  if [ -n "$hooks_path" ]; then
    why="core.hooksPath is set to '$hooks_path', so git never runs $hooks_dir/pre-push"
  elif [ ! -f "$hooks_dir/pre-push" ]; then
    why="there is no $hooks_dir/pre-push"
  elif ! grep -q "$shim_marker" "$hooks_dir/pre-push"; then
    why="$hooks_dir/pre-push is not the squad's shim"
  elif [ "$(cat "$hooks_dir/pre-push")" != "$shim" ] || [ ! -x "$hooks_dir/pre-push" ]; then
    why="the shim is not the one this installer writes; install again"
  fi
  verdict "the pre-push shim is installed and core.hooksPath is unset" "$why"

  # 5. The gate runs.
  verdict "the gate refuses a failing check and lets a passing one through" "$(gate_refusal)"

  # 6. The project's list of checks is part of the project.
  why=""
  if [ ! -f "$project/.agent-squad-checks" ]; then
    why="there is no .agent-squad-checks"
  elif ! git -C "$project" ls-files --error-unmatch .agent-squad-checks >/dev/null 2>&1; then
    why=".agent-squad-checks is not tracked"
  fi
  verdict ".agent-squad-checks exists and is tracked" "$why"

  # 7. The DEV and QA worktrees belong to this repository.
  why="$(for agent in dev qa; do
    worktree="$squad/worktrees/$agent"
    if [ ! -d "$worktree" ]; then
      echo "$agent is missing"
    elif [ "$(real_path "$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")" \
        != "$(real_path "$common_dir")" ] \
      || [ "$(real_path "$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null)")" != "$(real_path "$worktree")" ]; then
      echo "$agent is not a worktree of this repository"
    fi
  done | join)"
  verdict ".agent-squad/worktrees/dev and qa are worktrees of this repository" "$why"

  # 8. Every session loads the charter.
  why="$({
    case "$(readlink "$project/CLAUDE.md" 2>/dev/null)" in
      AGENTS.md|./AGENTS.md) ;;
      *) echo "CLAUDE.md is not a symlink to AGENTS.md" ;;
    esac
    grep -qF '@.agent-squad/playbook/SQUAD.md' "$project/AGENTS.md" 2>/dev/null \
      || echo "AGENTS.md does not import @.agent-squad/playbook/SQUAD.md"
  } | join)"
  verdict "CLAUDE.md links to AGENTS.md, which imports the charter" "$why"

  [ "$failed_items" -eq 0 ]
}

if [ "$mode" = check ]; then
  check_installation
  exit
fi

# 1. Playbook (D2, D9): the new tree is built beside the current one and swapped in only once it
#    is complete, so a failed download or extraction leaves the installed playbook as it was.
mkdir -p "$squad" || die "cannot create $squad"
staging="$(mktemp -d "$squad/playbook.new.XXXXXX")" || die "cannot create a directory in $squad"
tarball=""
# shellcheck disable=SC2317,SC2329 # invoked by the trap below
cleanup() {
  rm -rf "$staging"
  [ -z "$tarball" ] || rm -f "$tarball"
}
trap cleanup EXIT

if [ -n "$source_dir" ]; then
  [ -d "$source_dir" ] || die "$source_dir is not a directory; the installed playbook is unchanged"
  cp -pR "$source_dir/." "$staging/" \
    || die "cannot copy $source_dir; the installed playbook is unchanged"
else
  tarball="$(mktemp "$squad/tarball.XXXXXX")" || die "cannot create a file in $squad"
  gh api "repos/$upstream/tarball/$tag" > "$tarball" \
    || die "cannot download $tag from $upstream; the installed playbook is unchanged"
  tar -xzf "$tarball" -C "$staging" --strip-components=1 \
    || die "cannot extract the tarball of $tag; the installed playbook is unchanged"
fi
for required in SQUAD.md .githooks/pre-push scripts/squad-checks.sh scripts/squad-handoff.sh; do
  [ -f "$staging/$required" ] \
    || die "the tree of $tag has no $required; the installed playbook is unchanged"
done

previous="none"
[ -s "$log" ] && previous="$(awk 'END { print $NF }' "$log")"
installed_manifest="$(manifest "$staging")"
if [ -d "$playbook" ] && [ "$installed_manifest" = "$(manifest "$playbook")" ]; then
  say playbook "$tag is already installed, unchanged"
else
  retired="$squad/playbook.old.$$"
  if [ -e "$playbook" ]; then
    mv "$playbook" "$retired" || die "cannot move the installed playbook aside; it is unchanged"
  fi
  if ! mv "$staging" "$playbook"; then
    [ ! -e "$retired" ] || mv "$retired" "$playbook"
    die "cannot move the new playbook in place; the installed one is unchanged"
  fi
  rm -rf "$retired"
  say playbook "installed $tag in .agent-squad/playbook/ (previously $previous)"
fi
# The checksums of what was installed, which --check compares the playbook against.
if [ "$(cat "$manifest_file" 2>/dev/null)" = "$installed_manifest" ]; then
  say manifest "the playbook's checksums are already recorded"
else
  printf '%s\n' "$installed_manifest" > "$manifest_file"
  say manifest "recorded the playbook's checksums in .agent-squad/playbook.manifest"
fi
printf '%s %s -> %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$previous" "$tag" >> "$log"
say log "appended '$previous -> $tag' to .agent-squad/install.log"

# 2. .gitignore: the squad's directory and Claude Code's local settings stay out of git. A line is
#    added only when the project's own .gitignore does not already ignore the path.
gitignore="$project/.gitignore"
for path in .agent-squad .claude/settings.local.json; do
  line="$path"
  [ "$path" = .agent-squad ] && line=".agent-squad/"
  source_of_rule="$(git -C "$project" check-ignore -v --no-index "$path" 2>/dev/null | cut -d: -f1)"
  if [ "$source_of_rule" = .gitignore ]; then
    say .gitignore "$line is already ignored"
    continue
  fi
  if [ -s "$gitignore" ] && [ -n "$(tail -c 1 "$gitignore")" ]; then
    echo >> "$gitignore"
  fi
  echo "$line" >> "$gitignore"
  say .gitignore "added $line"
  tracked_changes+=(".gitignore")
done

# 3. Compaction hooks (D5, D10), merged into .claude/settings.local.json: every other key and hook
#    is kept, and only entries that run squad-handoff.sh are replaced.
current="{}"
[ -f "$settings" ] && current="$(cat "$settings")"
# shellcheck disable=SC2016 # $save, $restore and $startup are jq variables
if merged="$(printf '%s' "$current" | jq --arg save "$save_command" --arg restore "$restore_command" \
  --arg startup "$startup_command" '
  def ours: (.command // "") | contains("squad-handoff.sh");
  def entry($matcher; $command): {matcher: $matcher, hooks: [{type: "command", command: $command}]};
  .hooks = (.hooks // {})
  | .hooks |= with_entries(.value |= map(
      if any(.hooks[]?; ours) then (.hooks |= map(select(ours | not))) | select(.hooks | length > 0)
      else . end))
  | .hooks.PreCompact = (.hooks.PreCompact // []) + [entry("manual"; $save), entry("auto"; $save)]
  | .hooks.SessionStart = (.hooks.SessionStart // [])
      + [entry("compact"; $restore), entry("startup"; $startup)]')"; then
  if [ -f "$settings" ] && [ "$merged" = "$current" ]; then
    say hooks "the four hooks are already in .claude/settings.local.json"
  else
    mkdir -p "$project/.claude" && printf '%s\n' "$merged" > "$settings"
    say hooks "wrote the four hooks into .claude/settings.local.json, other settings kept"
  fi
else
  say hooks "NOT INSTALLED: .claude/settings.local.json is not a JSON object with a valid \"hooks\"; fix it and run again"
  needs_decision=1
fi

# 4. Pre-push shim (D8) in the common git directory, so that every worktree runs it. A project's
#    own pre-push is kept as pre-push.local and run first; other hooks are left alone.
hooks_path="$(git -C "$project" config --get core.hooksPath || true)"
if [ -n "$hooks_path" ]; then
  say pre-push "NOT INSTALLED: core.hooksPath is set to '$hooks_path', so git never runs $hooks_dir; decide with the CEO whether to unset it"
  needs_decision=1
elif [ -e "$hooks_dir/pre-push" ] && grep -q "$shim_marker" "$hooks_dir/pre-push" 2>/dev/null; then
  if [ "$(cat "$hooks_dir/pre-push")" = "$shim" ]; then
    say pre-push "the shim is already in place"
  else
    printf '%s\n' "$shim" > "$hooks_dir/pre-push" && chmod +x "$hooks_dir/pre-push"
    say pre-push "rewrote the shim"
  fi
elif [ -e "$hooks_dir/pre-push" ] || [ -L "$hooks_dir/pre-push" ]; then
  if [ -e "$hooks_dir/pre-push.local" ] || [ -L "$hooks_dir/pre-push.local" ]; then
    say pre-push "NOT INSTALLED: pre-push and pre-push.local both exist in $hooks_dir and neither is the shim; decide which one the shim runs"
    needs_decision=1
  else
    mv "$hooks_dir/pre-push" "$hooks_dir/pre-push.local"
    printf '%s\n' "$shim" > "$hooks_dir/pre-push" && chmod +x "$hooks_dir/pre-push"
    say pre-push "kept the project's pre-push as pre-push.local, run first; wrote the shim"
  fi
else
  mkdir -p "$hooks_dir"
  printf '%s\n' "$shim" > "$hooks_dir/pre-push" && chmod +x "$hooks_dir/pre-push"
  say pre-push "wrote the shim"
fi

# 5. GitHub templates, created from the playbook only when the project has none; the project owns
#    them afterwards.
for template in .github/ISSUE_TEMPLATE/task.md .github/PULL_REQUEST_TEMPLATE.md; do
  if [ -e "$project/$template" ]; then
    say templates "$template exists, kept"
  elif [ ! -f "$playbook/$template" ]; then
    say templates "$template is not in the playbook, skipped"
  else
    mkdir -p "$(dirname "$project/$template")" && cp "$playbook/$template" "$project/$template"
    say templates "created $template"
    tracked_changes+=("$template")
  fi
done

# 6. The DEV and QA worktrees (D3), detached at origin/main as it is locally: no fetch.
for agent in dev qa; do
  worktree="$squad/worktrees/$agent"
  if [ -e "$worktree" ]; then
    say worktrees ".agent-squad/worktrees/$agent exists, kept"
  elif ! git -C "$project" rev-parse -q --verify 'origin/main^{commit}' >/dev/null; then
    say worktrees "NOT CREATED: .agent-squad/worktrees/$agent, because origin/main does not exist yet; run again once it does"
    needs_decision=1
  elif error="$(git -C "$project" worktree add -q --detach "$worktree" origin/main 2>&1)"; then
    say worktrees "created .agent-squad/worktrees/$agent, detached at origin/main"
  else
    say worktrees "NOT CREATED: .agent-squad/worktrees/$agent: $error"
    needs_decision=1
  fi
done

# 7. What only the CTO can do: the project's own tracked files.
echo
echo "By hand:"
items=0
item() {
  items=$((items + 1))
  printf '  %d. %s\n' "$items" "$1"
}
if ! grep -qF '@.agent-squad/playbook/SQUAD.md' "$project/AGENTS.md" 2>/dev/null; then
  # The one source of the Squad section is the playbook's template of AGENTS.md.
  block="$(awk '/^## Squad[[:space:]]*$/ { inside = 1; print; next } inside && /^## / { exit } inside' \
    "$playbook/templates/AGENTS.md" 2>/dev/null)"
  if [ -n "$block" ]; then
    item "Add this section to AGENTS.md, which imports the charter into every session:"
    printf '%s\n' "$block" | sed 's/^/       /'
  else
    item "Add the Squad section of .agent-squad/playbook/templates/AGENTS.md to AGENTS.md"
  fi
fi
case "$(readlink "$project/CLAUDE.md" 2>/dev/null)" in
  AGENTS.md|./AGENTS.md) ;;
  *) item "Make CLAUDE.md a symlink to AGENTS.md (ln -s AGENTS.md CLAUDE.md), once its content is in AGENTS.md" ;;
esac
if [ ! -f "$project/.agent-squad-checks" ]; then
  item "Write .agent-squad-checks: the commands your CI runs, one per line; until it exists the gate refuses every push"
fi
if [ "${#tracked_changes[@]}" -gt 0 ]; then
  changed="$(printf '%s\n' "${tracked_changes[@]}" | sort -u | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
  item "Commit what this run changed in tracked files through a PR: $changed"
fi
[ "$items" -gt 0 ] || echo "  nothing"

if [ "$needs_decision" -ne 0 ]; then
  echo "squad-install: the steps marked NOT were not done; resolve them and run the installer again" >&2
fi
exit "$needs_decision"
