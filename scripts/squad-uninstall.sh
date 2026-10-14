#!/usr/bin/env bash
# Remove agent-squad from a project (agent-squad #263): what the installer of this release, or of
# an earlier one, wrote outside git, and nothing else.
# - the squad's session hooks in .claude/settings.local.json, as the wrapper or, before v49,
#   squad-handoff.sh run them, and the board's marketplaces and plugins, by the installer's own
#   rule; every other setting is kept;
# - the squad's commands in .claude/commands/, apart from one the project tracks;
# - the pre-push shim, putting back the project's own pre-push, which the shim ran as
#   pre-push.local;
# - the worktrees under .agent-squad/worktrees/, and .agent-squad/ itself. The compaction snapshots
#   (handoff/), the review evidence (evidence/) and the token history (tokens.tsv) are records: they
#   are kept in .agent-squad/, unless --records is given.
# It never loses work: while a worktree holds changes that are not committed, or commits that no
# remote branch holds, it refuses, names them, and removes nothing. What a worktree holds that git
# ignores, such as a .env or a run's output, is moved aside into .agent-squad/kept/<worktree>/, a
# rename on the same disk, and kept like the records (agent-squad #263, QA's review of PR #288). It never touches a tracked
# file: it lists, for the CTO to remove through a PR, the tracked files the squad added. It runs
# from a copy of itself, so that removing the playbook it lives in does not cut it short, and a
# second run finds nothing left to remove.
#
# Usage: squad-uninstall.sh [--dry-run] [--records] <project main checkout>
#   --dry-run says what it would do, and changes nothing. --records removes the records too.
# Output: one line per step, "uninstall: <step> <what it did>", then what is left for the CTO.
# Exit: 0 done, or nothing to do; 1 refused, so nothing was removed, or a step needs a decision;
#   2 bad usage, or not a project's main checkout.
set -u
# jq on Windows ends each line with CRLF, and the shell keeps the CR in what it reads, as in an id
# sent to GitHub, which then refuses it (agent-squad #405): every jq of this script drops it here.
# Whether jq is installed is therefore asked of `type -P`, which ignores this function.
jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }

usage() { sed -n 's/^# Usage: /usage: /p' "$0" >&2; exit 2; }
die() { echo "squad-uninstall: $*" >&2; exit 2; }

# 0. Run from a copy, named as this script is, in a directory of its own, removed at the end.
if [ -z "${SQUAD_UNINSTALL_COPY:-}" ]; then
  copy_dir="${TMPDIR:-/tmp}"
  copy_dir="$(mktemp -d "${copy_dir%/}/squad-uninstall.XXXXXX")" || die "cannot copy itself to a temporary directory"
  cp "$0" "$copy_dir/squad-uninstall.sh" || { rm -rf "$copy_dir"; die "cannot copy itself to a temporary directory"; }
  SQUAD_UNINSTALL_COPY="$copy_dir" exec bash "$copy_dir/squad-uninstall.sh" "$@"
fi
trap 'rm -rf "$SQUAD_UNINSTALL_COPY"' EXIT

dry_run=false records=false
while [ $# -gt 1 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --records) records=true ;;
    *) usage ;;
  esac
  shift
done
if [ $# -ne 1 ] || [ "${1#-}" != "$1" ]; then usage; fi
for tool in git jq; do
  type -P "$tool" >/dev/null 2>&1 || die "$tool is required"
done

# The project is named by its main checkout, as the installer names it.
project="$(CDPATH='' cd -- "$1" 2>/dev/null && pwd -P)" || die "$1 is not a directory"
common_dir="$(git -C "$project" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || die "$project is not a git checkout"
main_checkout="$(CDPATH='' cd -- "$(dirname "$common_dir")" && pwd -P)"
top_level="$(git -C "$project" rev-parse --show-toplevel 2>/dev/null)"
top_level="$(CDPATH='' cd -- "$top_level" 2>/dev/null && pwd -P)"
if [ "$project" != "$main_checkout" ] || [ "$top_level" != "$main_checkout" ]; then
  die "$project is not the project's main checkout; pass $main_checkout"
fi
squad="$project/.agent-squad"
playbook="$squad/playbook"
settings="$project/.claude/settings.local.json"
commands_dir="$project/.claude/commands"
hooks_dir="$common_dir/hooks"
records_kept=(handoff evidence tokens.tsv kept)
needs_decision=0
# Whether any step found something of the squad's to remove.
found=false

# `say <step> <what>` reports a step; `act <command...>` runs it, unless this is a dry run.
say() { printf 'uninstall: %-10s %s\n' "$1" "$2"; }
act() { $dry_run || "$@"; }
# `did <done> <would>` picks the verb for a step: what it did, or what it would do.
did() { if $dry_run; then echo "$2"; else echo "$1"; fi; }
tracked_by_project() { git -C "$project" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }

# 1. The worktrees under .agent-squad/worktrees/, and the work each holds. Any change not
#    committed, untracked files included, and any commit that no remote branch holds stops the
#    run before anything is removed, as git worktree remove stops on the first.
worktrees=()
while IFS= read -r line; do
  case "$line" in
    "worktree $squad/worktrees/"*) worktrees+=("${line#worktree }") ;;
  esac
done < <(git -C "$project" worktree list --porcelain 2>/dev/null)
in_the_way=()
for worktree in ${worktrees[@]+"${worktrees[@]}"}; do
  [ -d "$worktree" ] || continue
  name="${worktree#"$squad/"}"
  changes="$(git -C "$worktree" status --porcelain 2>/dev/null | head -n 3 | cut -c4- | paste -sd, -)"
  [ -z "$changes" ] || in_the_way+=("$name has changes that are not committed: $changes")
  unpushed="$(git -C "$worktree" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)"
  [ "$unpushed" = 0 ] || in_the_way+=("$name has $unpushed commit(s) that no remote branch holds")
done
if [ "${#in_the_way[@]}" -gt 0 ]; then
  for reason in "${in_the_way[@]}"; do say refused "$reason"; done
  echo "squad-uninstall: nothing was removed; commit and push that work, or set it aside, then run again" >&2
  exit 1
fi

# 1b. What each worktree holds that git ignores, as git status collapses it (a wholly ignored
#     directory is one entry), and where it goes: .agent-squad/kept/<worktree>/, or, when an earlier
#     uninstall left one there, a name of its own beside it.
# `ignored_in <worktree>` prints those entries, one per line, relative to the worktree.
ignored_in() { git -C "$1" status --ignored --porcelain -z 2>/dev/null | tr '\0' '\n' | sed -n 's/^!! //p'; }
for worktree in ${worktrees[@]+"${worktrees[@]}"}; do
  [ -d "$worktree" ] || continue
  entries="$(ignored_in "$worktree")"
  [ -n "$entries" ] || continue
  name="$(basename "$worktree")" dest="$squad/kept/$(basename "$worktree")"
  [ ! -e "$dest" ] || dest="$dest.$(date +%Y%m%dT%H%M%S)"
  if ! $dry_run; then
    while IFS= read -r entry; do
      { mkdir -p "$dest/$(dirname "$entry")" && mv "$worktree/${entry%/}" "$dest/${entry%/}"; } \
        || { say kept "NOT MOVED: worktrees/$name/$entry; nothing more was removed"; exit 1; }
    done <<<"$entries"
  fi
  say kept "$(did moved "would move") what worktrees/$name holds that git ignores into ${dest#"$project/"}/: $(paste -sd, - <<<"$entries" | sed 's/,/, /g')"
done

# 2. What the CTO removes through a PR: the tracked files the squad added, read now, while the
#    playbook is there to compare the templates with.
left_for_cto=()
# .gitignore's lines of the squad's, listed once step 3 knows whether the settings file stays.
squad_rules=()
if [ -f "$project/.gitignore" ]; then
  for rule in .agent-squad/ .claude/settings.local.json ".claude/commands/squad-*.md"; do
    grep -qxF -- "$rule" "$project/.gitignore" && squad_rules+=("$rule")
  done
fi
for template in .github/ISSUE_TEMPLATE/task.md .github/PULL_REQUEST_TEMPLATE.md; do
  if [ -f "$project/$template" ] && [ -f "$playbook/$template" ] && cmp -s "$project/$template" "$playbook/$template"; then
    left_for_cto+=("$template, the squad's template")
  fi
done
if [ -f "$project/AGENTS.md" ] && grep -q '^@\.agent-squad/playbook/SQUAD\.md' "$project/AGENTS.md"; then
  left_for_cto+=("the Squad section of AGENTS.md, which imports the charter")
fi
[ ! -f "$project/.agent-squad-checks" ] || left_for_cto+=(".agent-squad-checks, which only the squad's gate reads")

# 3. The session hooks and the board's mods in .claude/settings.local.json. A hook is the squad's
#    when it runs the wrapper or squad-handoff.sh; a marketplace, when the installer's own rule
#    says so (a name that starts with agent-squad-, declared at a .agent-squad/ folder), and a
#    plugin, when it is one of theirs. What is left empty goes, and a file left with nothing goes.
# shellcheck disable=SC2016 # the $ names are jq's
cleaned='def hook_ours: (.command // "") | (contains("squad-handoff.sh") or contains("/.agent-squad/squad-hook"));
  [(.extraKnownMarketplaces // {}) | to_entries[]
    | select((.key | startswith("agent-squad-")) and .value.source.source? == "directory"
        and ((.value.source.path? // "") | tostring | endswith("/.agent-squad")))
    | .key] as $markets
  | if .hooks then
      .hooks |= (with_entries(.value |= map(.hooks |= map(select(hook_ours | not)) | select(.hooks | length > 0))
        | select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end
  | if .extraKnownMarketplaces then
      .extraKnownMarketplaces |= with_entries(select(.key | IN($markets[]) | not))
      | if .extraKnownMarketplaces == {} then del(.extraKnownMarketplaces) else . end
    else . end
  | if .enabledPlugins then
      .enabledPlugins |= with_entries(select((.key | split("@")) as $p | $p | length == 2 and ($p[1] | IN($markets[])) | not))
      | if .enabledPlugins == {} then del(.enabledPlugins) else . end
    else . end'
settings_stays=false
if [ -f "$settings" ]; then
  settings_stays=true
  if ! after="$(jq -e -s 'length == 1 and (.[0] | type == "object")' "$settings" >/dev/null 2>&1 \
      && jq "$cleaned" "$settings" 2>/dev/null)"; then
    say hooks "NOT REMOVED: .claude/settings.local.json is not one JSON object; it is left as it is: remove the squad's hooks and mods by hand"
    needs_decision=1
  elif [ "$after" = "$(jq . "$settings")" ]; then
    say hooks "none of the squad's hooks or mods are in .claude/settings.local.json"
  elif [ "$after" = "{}" ]; then
    found=true
    settings_stays=false
    act rm -f "$settings"
    say hooks "$(did removed "would remove") .claude/settings.local.json, which held only the squad's hooks and mods"
  else
    found=true
    $dry_run || printf '%s\n' "$after" > "$settings"
    say hooks "$(did removed "would remove") the squad's hooks and mods from .claude/settings.local.json, other settings kept"
  fi
fi

# The .gitignore's lines for the CTO (agent-squad #291). The one for .claude/settings.local.json is
# listed only when that file goes: while the project's own settings stay, the line keeps them out
# of git, whoever wrote it.
lines=() note=""
for rule in ${squad_rules[@]+"${squad_rules[@]}"}; do
  if [ "$rule" = .claude/settings.local.json ] && $settings_stays; then
    note="; keep .claude/settings.local.json's line, since the project's own settings stay"
  else
    lines+=("$rule")
  fi
done
if [ "${#lines[@]}" -gt 0 ]; then
  item=".gitignore's lines $(printf '%s, ' "${lines[@]}" | sed 's/, $//')"
  $records || item="$item; keep .agent-squad/ while the records stay there"
  left_for_cto=("$item$note" ${left_for_cto[@]+"${left_for_cto[@]}"})
fi

# 4. The squad's commands, apart from one the project tracks: the project owns it.
removed=() kept=()
for file in "$commands_dir"/squad-*.md; do
  [ -f "$file" ] || continue
  if tracked_by_project ".claude/commands/$(basename "$file")"; then
    kept+=("/$(basename "$file" .md)")
  else
    act rm -f "$file"
    removed+=("/$(basename "$file" .md)")
  fi
done
[ "${#removed[@]}" -eq 0 ] || found=true
[ "${#removed[@]}" -eq 0 ] || say command "$(did removed "would remove") the ${#removed[@]} squad commands from .claude/commands/"
[ "${#kept[@]}" -eq 0 ] || say command "kept ${kept[*]}, which the project tracks"
# The directories the installer made, once empty.
if ! $dry_run; then
  rmdir "$commands_dir" 2>/dev/null
  [ -f "$settings" ] || rmdir "$project/.claude" 2>/dev/null
fi

# 5. The pre-push shim, and the project's own pre-push it ran, put back in its place.
if [ -f "$hooks_dir/pre-push" ] && grep -q "agent-squad pre-push shim" "$hooks_dir/pre-push"; then
  found=true
  if [ -e "$hooks_dir/pre-push.local" ]; then
    act mv "$hooks_dir/pre-push.local" "$hooks_dir/pre-push"
    say pre-push "$(did "removed the shim and put the project's pre-push back" "would remove the shim and put the project's pre-push back")"
  else
    act rm -f "$hooks_dir/pre-push"
    say pre-push "$(did "removed the shim" "would remove the shim")"
  fi
fi

# 6. The worktrees, then .agent-squad/, but for the records unless --records. A worktree git will
#    not remove keeps .agent-squad/ where it is, since removing the directory would take it along.
worktrees_left=false
for worktree in ${worktrees[@]+"${worktrees[@]}"}; do
  found=true
  if [ -d "$worktree" ] && ! act git -C "$project" worktree remove "$worktree"; then
    say worktrees "NOT REMOVED: ${worktree#"$squad/"}: git refused it; .agent-squad/ is left as it is"
    needs_decision=1 worktrees_left=true
  fi
done
act git -C "$project" worktree prune
[ "${#worktrees[@]}" -eq 0 ] || $worktrees_left \
  || say worktrees "$(did removed "would remove") $(printf '%s, ' "${worktrees[@]#"$squad/worktrees/"}" | sed 's/, $//') in .agent-squad/worktrees/"
if [ -d "$squad" ] && ! $worktrees_left; then
  kept=() gone=()
  for entry in "$squad"/* "$squad"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="$(basename "$entry")"
    if ! $records && [[ " ${records_kept[*]} " == *" $name "* ]]; then kept+=("$name"); else gone+=("$entry"); fi
  done
  if [ "${#gone[@]}" -gt 0 ] || [ "${#kept[@]}" -eq 0 ]; then
    found=true
    for entry in ${gone[@]+"${gone[@]}"}; do act rm -rf "$entry"; done
    if [ "${#kept[@]}" -eq 0 ]; then
      $dry_run || rmdir "$squad" 2>/dev/null
      say squad "$(did removed "would remove") .agent-squad/"
    else
      say squad "$(did removed "would remove") .agent-squad/ but for the records, ${kept[*]}; --records removes them too"
    fi
  fi
fi
if ! $found; then
  if [ -d "$squad" ]; then
    say nothing "nothing of the squad's is left to remove here; its records stay in .agent-squad/, which --records removes"
  else
    say nothing "nothing of the squad's is left to remove here"
  fi
fi

# 7. What is left, for the CTO, through a PR.
echo
echo "By hand, for the CTO, through a PR: the tracked files the squad added"
if [ "${#left_for_cto[@]}" -eq 0 ]; then
  echo "  nothing"
else
  n=0
  for item in "${left_for_cto[@]}"; do n=$((n + 1)); printf '  %d. %s\n' "$n" "$item"; done
fi
exit "$needs_decision"
