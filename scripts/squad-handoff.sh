#!/usr/bin/env bash
# Squad handoff for context compaction (SQUAD.md, "How rules reach the agents").
#
#   save     PreCompact hook: snapshot the objective state of the project into a per-session file.
#   restore  SessionStart(compact) hook: print that snapshot plus re-orientation instructions, so
#            that it is re-injected into the compacted session's context.
#   startup  SessionStart(startup) hook: print a one-line warning when the charter is not installed,
#            and nothing otherwise.
#
# save and restore read the hook's JSON payload on stdin and key the file by session_id, so the
# script works for any role without knowing which session it runs in. Snapshots live in the main
# checkout's .agent-squad/handoff/, the same directory from every linked worktree. It never fails
# the hook: on any error it prints what it has and exits 0.
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
  prs="$(gh pr list --json number,title,headRefName,headRefOid,labels 2>/dev/null || true)"
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
  fi
  echo
  echo "## Issues in progress, in review or blocked"
  gh issue list --json number,title,labels \
    --jq '.[] | select([.labels[].name] | any(startswith("🚧") or startswith("👀") or startswith("⛔"))) | "- #\(.number) \(.title) labels: \([.labels[].name] | join(", "))"' 2>/dev/null \
    || echo "(gh unavailable)"
  echo
  echo "## main"
  git log origin/main --oneline -3 2>/dev/null || git log --oneline -3 2>/dev/null || true
}

case "$action" in
  save)
    [ -n "$session_id" ] || exit 0
    mkdir -p "$handoff_dir" 2>/dev/null || exit 0
    snapshot > "$handoff_file" 2>/dev/null || true
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
