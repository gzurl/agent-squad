#!/usr/bin/env bash
# Squad handoff for context compaction (SQUAD.md §7).
#
#   save     PreCompact hook: snapshot the objective state of the project into a per-session file,
#            then gate a manual /compact on /squad-save-state (agent-squad #100).
#   restore  SessionStart(compact) hook: print that snapshot plus re-orientation instructions, so
#            that it is re-injected into the compacted session's context.
#   startup  SessionStart(startup) hook: print a one-line warning when the charter is not installed,
#            and nothing otherwise.
#
# save and restore read the hook's JSON payload on stdin and key the file by session_id, so the
# script works for any role without knowing which session it runs in. Snapshots live in the main
# checkout's .agent-squad/handoff/, the same directory from every linked worktree. It never fails
# the hook: on any error it prints what it has and exits 0. The one exception is the gate, which
# stops a manual /compact on purpose with exit 2.
set -u

action="${1:-}"
# The hook's JSON payload. Run by hand on a terminal there is none, and reading would wait for ever.
payload=""
[ -t 0 ] || payload="$(cat 2>/dev/null || true)"
# jq is required to read the payload (BOOTSTRAP.md, row 10b). Without it, or without a usable id,
# nothing is written: a missing snapshot is harmless, a shared or mis-placed one is not.
session_id=""
if command -v jq >/dev/null 2>&1; then
  session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
# Validate the identifier before it becomes a path (SQUAD.md: validate the identifier, derive the rest).
case "$session_id" in
  *[!A-Za-z0-9_-]*|"") session_id="" ;;
esac

# The main checkout is the parent of the common git directory, whichever worktree the hook runs in.
common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$common_dir" ]; then
  main_checkout="$(dirname "$common_dir")"
else
  main_checkout="$(pwd)"
fi
handoff_dir="$main_checkout/.agent-squad/handoff"
handoff_file="$handoff_dir/$session_id.md"
charter="$main_checkout/.agent-squad/playbook/SQUAD.md"

# gh lists 30 items unless told otherwise, and a cut list reads as a complete one. Both listings
# ask for this many, and `limit_note <count> <what> <command>` says so, on a line of its own, when
# one of them reaches it.
limit=100
limit_note() {
  if [ "$1" -ge "$limit" ]; then
    echo "($1 $2 read, the limit of this snapshot; there may be more: $3)"
  fi
}

# Objective facts a compacted session needs to re-orient itself. Everything comes from git and
# GitHub, nothing from the conversation, so it is exact even if the summary is not.
snapshot() {
  echo "# Squad handoff — saved $(date '+%Y-%m-%d %H:%M %Z') before compaction (session $session_id)"
  echo
  echo "## Worktrees"
  git worktree list 2>/dev/null || echo "(git worktree list unavailable)"
  echo
  echo "## Open pull requests"
  # Per PR: head SHA, the latest verdict with the commit it was bound to (flagged STALE when that
  # commit is no longer the head, which is exactly the merge gate), and unresolved review threads.
  owner="$(gh repo view --json owner --jq .owner.login 2>/dev/null || true)"
  repo="$(gh repo view --json name --jq .name 2>/dev/null || true)"
  prs="$(gh pr list --state open --limit "$limit" --json number,title,headRefName,headRefOid,labels 2>/dev/null || true)"
  if [ -z "$prs" ]; then
    echo "(gh unavailable)"
  else
    printf '%s' "$prs" | jq -r '.[] | "\(.number)\t\(.headRefOid)\t\(.title) [\(.headRefName)] labels: \([.labels[].name] | join(", "))"' \
    | while IFS="$(printf '\t')" read -r n head rest; do
      echo "- PR #$n $rest"
      echo "  head ${head:0:7}"
      if reviews="$(gh api --paginate "repos/$owner/$repo/pulls/$n/reviews" 2>/dev/null)"; then
        verdict="$(printf '%s' "$reviews" | jq -r '[.[] | select(.body | test("QA-VERDICT: "))] | last | if . == null then "none yet" else "\(.commit_id[0:7]) \(.body | split("\n") | map(select(test("QA-VERDICT: "))) | last)" end' 2>/dev/null || echo "unreadable")"
        case "$verdict" in
          "none yet"|"unreadable") ;;
          "${head:0:7} "*) verdict="$verdict (current)" ;;
          *) verdict="$verdict (STALE: not the head)" ;;
        esac
      else
        verdict="API error"
      fi
      threads="$(gh api graphql -f query="{repository(owner:\"$owner\",name:\"$repo\"){pullRequest(number:$n){reviewThreads(first:100){nodes{isResolved}}}}}" \
        --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length' 2>/dev/null || echo "unknown")"
      echo "  verdict $verdict; unresolved threads $threads"
    done
    limit_note "$(printf '%s' "$prs" | jq length)" "open pull requests" "gh pr list --limit 1000"
  fi
  echo
  echo "## Issues in progress, in review or blocked"
  # Filtered here, on the labels' first character: gh's own --label filter silently finds nothing
  # for labels whose emoji is a ZWJ sequence (agent-squad #56).
  issues="$(gh issue list --state open --limit "$limit" --json number,title,labels 2>/dev/null || true)"
  if [ -z "$issues" ]; then
    echo "(gh unavailable)"
  else
    printf '%s' "$issues" \
      | jq -r '.[] | select([.labels[].name] | any(startswith("🚧") or startswith("👀") or startswith("⛔"))) | "- #\(.number) \(.title) labels: \([.labels[].name] | join(", "))"'
    limit_note "$(printf '%s' "$issues" | jq length)" "open issues" "gh issue list --limit 1000"
  fi
  echo
  # The remote's default branch, which need not be main (agent-squad #72); when git does not know
  # it, the local log, and the heading says so.
  if default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    echo "## Default branch: $default"
    git log "$default" --oneline -3 2>/dev/null || true
  else
    echo "## Default branch: unknown to git, so the local log"
    git log --oneline -3 2>/dev/null || true
  fi
}

# The pre-compact gate. A manual /compact goes through when the last thing the user or another
# agent did in this session was /squad-save-state, which has the agent write its state on GitHub
# first; otherwise it is stopped with exit 2 and a line on stderr, which Claude Code shows the
# user. An automatic compaction is never stopped. A second manual /compact within ten minutes of a
# stopped one goes through, so that the gate can always be passed. What it cannot read or
# understand lets the compaction through, saying so: a gate that locks the user out is worse than
# none. Claude Code gives the trigger in the hook's input, and the transcript's format is not
# documented as stable: the entries relied on are recorded on agent-squad #100.
hatch_seconds=600
# The last entry in which the user or another agent did something: a user entry that is not a tool
# result, not meta unless it is a message from another agent (command expansions, reminders and
# caveats are meta), not a local command's echo (a stopped /compact leaves one), not the /compact
# being typed (the interactive CLI writes it as plain text, then as markup, before the hook runs:
# agent-squad #134) and not a compaction summary. It prints that entry's text as a JSON string, one per line.
# shellcheck disable=SC2016 # a jq program: its $names are jq's
turn_filter='select(.type == "user" and (.isCompactSummary | not))
  | .message.content as $content
  | select(($content | type) == "string" or (($content | type) == "array" and ($content | any(.type != "tool_result"))))
  | select(.isMeta != true or .origin.kind == "peer")
  | (if ($content | type) == "string" then $content else [$content[] | select(.type == "text") | .text] | join("\n") end)
  | select((startswith("<local-command-") or test("<command-name>/compact</command-name>") or test("^/compact( |$)")) | not)'
# `unchecked <why>` lets the compaction through, saying why it was not checked.
unchecked() {
  echo "squad: could not check for /squad-save-state before this /compact ($1), so it goes ahead" >&2
  exit 0
}
compact_gate() {
  local trigger transcript turns last blocked_file blocked_at now
  command -v jq >/dev/null 2>&1 || unchecked "jq is missing"
  trigger="$(printf '%s' "$payload" | jq -r '.trigger // empty' 2>/dev/null)"
  case "$trigger" in
    auto) return 0 ;;
    manual) ;;
    *) unchecked "the hook's input says neither manual nor auto" ;;
  esac
  [ -n "$session_id" ] || unchecked "the hook's input names no session"
  transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
  if [ -z "$transcript" ] || [ ! -r "$transcript" ]; then
    unchecked "the transcript cannot be read"
  fi
  turns="$(jq -c "$turn_filter" "$transcript" 2>/dev/null)" || unchecked "the transcript cannot be understood"
  [ -n "$turns" ] || unchecked "the transcript shows nothing the user did"
  last="$(tail -n 1 <<<"$turns" | jq -r . 2>/dev/null)"
  blocked_file="$handoff_dir/$session_id.blocked"
  # The command's own entry starts with its markup; a message that only quotes it does not count.
  case "$last" in
    "<command-message>squad-save-state</command-message>"*|"<command-name>/squad-save-state</command-name>"*)
      rm -f "$blocked_file"
      return 0 ;;
  esac
  now="$(date +%s)"
  blocked_at="$(cat "$blocked_file" 2>/dev/null)"
  case "$blocked_at" in ''|*[!0-9]*) blocked_at="" ;; esac
  if [ -n "$blocked_at" ] && [ "$((now - blocked_at))" -le "$hatch_seconds" ]; then
    rm -f "$blocked_file"
    echo "squad: a second /compact within 10 minutes of a stopped one goes ahead without /squad-save-state" >&2
    return 0
  fi
  mkdir -p "$handoff_dir" 2>/dev/null && echo "$now" > "$blocked_file"
  echo "squad: run /squad-save-state first, so that this session writes its state on GitHub; then type /compact again. A second /compact within 10 minutes goes ahead without it." >&2
  exit 2
}

case "$action" in
  save)
    if [ -n "$session_id" ] && mkdir -p "$handoff_dir" 2>/dev/null; then
      snapshot > "$handoff_file" 2>/dev/null || true
    fi
    compact_gate
    ;;
  restore)
    echo "Context was compacted. Re-orient before doing anything else:"
    echo "1. Your role is your session name (CTO, DEV or QA); sign as SQUAD.md says."
    echo "2. Re-read AGENTS.md and the charter it imports (in a project, .agent-squad/playbook/SQUAD.md); then the issue you own that carries a status label, its last milestone comment, and any PR of yours: its latest review, verdict and open threads."
    echo "3. Anything you promised another agent by message may be missing from the summary; state on the issue or PR what you are about to do before doing it."
    echo
    if [ -n "$session_id" ] && [ -f "$handoff_file" ]; then
      cat "$handoff_file"
    else
      echo "(no handoff file was saved for this session; rely on GitHub and the repository)"
    fi
    ;;
  startup)
    # A session that cannot read the charter must not start working as if it could.
    if [ ! -f "$charter" ]; then
      echo "Squad: the charter is not installed ($charter is missing). Stop and tell the CTO before doing anything else."
    fi
    ;;
  *)
    echo "usage: $0 save|restore|startup" >&2
    ;;
esac
exit 0
