#!/usr/bin/env bash
# Find the squad's stalls (agent-squad #174): work that waits on an agent whose session is idle,
# which no message will wake. For each open pull request and each issue in progress it works out,
# from GitHub alone, who owns the next step:
# - a PR whose head has no verdict, or one bound to an earlier commit: its reviewer, QA, or DEV on
#   a PR that QA authors (SQUAD.md §4), to review the head;
# - a PR whose verdict on its head asks for changes: its author, to answer them;
# - a PR approved on its head: its author, to merge it; but while a review it requests on GitHub is
#   pending, the reviewer it was requested from, whom the watch never pings (agent-squad #306);
# - a draft: its author, to finish it;
# - an issue in progress: the role of its owner label, to carry on; with none, the CTO;
# - an issue or a PR opened from outside the squad and not triaged yet, labelled needs-triage or
#   with no owner label: the CTO, to triage it (agent-squad #281).
# Outside means an author whose association GitHub reports as neither the repository's owner, nor
# a member of its organization, nor a collaborator (§3): the account decides, never a signature.
# So the next steps above follow an issue or a PR from inside only. Inside, a PR's author is the
# signature on the first line of its description (§6), and only reviews by inside accounts count
# (§4.9). An outside item counts as quiet from the moment it was opened. An item
# whose wait is already declared is left out, and nothing is reported about it: one labelled
# needs-ceo, the CEO's inbox, or status:blocked, whose reason is in its last comment (§3), and a PR
# whose closing issue is (agent-squad #174, PR #193).
#
# An item has stalled when GitHub shows no activity on it (its updatedAt) for 30 minutes and its
# owner's session is idle: the owner is to be pinged, once. When the same stall is still there an
# hour after that, the CEO is to be told, once. A PR that waits for a reviewer requested on GitHub,
# often a person outside the squad's sessions, is told to the CEO, once, when it has been quiet for
# an hour, since only the CEO can reach that reviewer. A session that waits on the CEO in its own
# terminal, or that is not open, is reported to the CEO at once and never pinged; a busy one is
# working, and nothing is reported for it. The session states come from the CTO, who reads them
# with ListAgents, which a script cannot. What was reported is kept in .agent-squad/watch.tsv of
# the main checkout, which git ignores, so that each finding is reported once; an item with new
# activity starts afresh.
#
# Usage: squad-stalls.sh [--session <role>=<state>]...
#   <role> is CTO, DEV or QA, and <state> idle, busy or waiting; a role not given has no session.
# Output: one line per finding, tab-separated: what to do ("ping" the role, or tell the "ceo"),
#   the role, or the requested reviewers, the item ("PR #12" or "#34"), its URL, the next step, since when it has been quiet
#   (local time), and, for the CEO, why. Nothing when there is nothing to report.
# Exit: 0 checked; 1 GitHub could not be read, so nothing was checked; 2 bad usage, or not run from
#   a checkout of a project the squad is installed in.
set -u
# jq on Windows ends each line with CRLF, and the shell keeps the CR in what it reads, as in an id
# sent to GitHub, which then refuses it (agent-squad #405): every jq of this script drops it here.
jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }

usage() { sed -n 's/^# Usage: /usage: /p' "$0" >&2; exit 2; }
die() { echo "squad-stalls: $*; nothing was checked" >&2; exit 1; }

# The options: each role's session state, as ListAgents shows it.
sessions='{}'
while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      [ $# -ge 2 ] || usage
      [[ "$2" =~ ^(CTO|DEV|QA)=(idle|busy|waiting)$ ]] || usage
      sessions="$(jq -c --arg role "${2%%=*}" --arg state "${2#*=}" '.[$role] = $state' <<<"$sessions")"
      shift 2 ;;
    *) usage ;;
  esac
done

# The main checkout, reached through the git directory every worktree shares, keeps what was
# reported.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || { echo "squad-stalls: run it from a checkout of a project the squad is installed in" >&2; exit 2; }
squad="$(dirname "$common")/.agent-squad"
[ -d "$squad" ] || { echo "squad-stalls: $(dirname "$common") has no .agent-squad/: the squad is not installed there" >&2; exit 2; }
state="$squad/watch.tsv"
# A record that cannot be kept would report the same findings on every pass: the run fails first.
cannot_keep() { echo "squad-stalls: cannot keep its records in $state${1:+: $1}" >&2; exit 1; }
[ ! -e "$state" ] || [ -f "$state" ] || cannot_keep "it is not a file"
now="${SQUAD_NOW:-$(date +%s)}"

# 1. What GitHub holds: the open PRs, the latest verdict on each by the squad's accounts, the open
#    issues, and who opened each. A call that fails stops the run: an unread GitHub must not read as
#    no stall. Each list goes to a file of a work directory, and from there to jq, never as an
#    argument: with their bodies, a project's open PRs and reviews run past what one command's
#    arguments may hold (agent-squad #281).
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || die "cannot read the repository from GitHub"
[ -n "$repo" ] || die "cannot read the repository from GitHub"
work="${TMPDIR:-/tmp}"
work="$(mktemp -d "${work%/}/squad-stalls.XXXXXX")" || die "cannot make a work directory"
trap 'rm -rf "$work"' EXIT
gh pr list --state open --limit 1000 --json number,title,isDraft,headRefOid,body,updatedAt,url,labels,closingIssuesReferences,reviewRequests \
  > "$work/prs.json" 2>/dev/null || die "cannot read the open pull requests"
gh issue list --state open --limit 1000 --json number,title,labels,updatedAt,url > "$work/issues.json" 2>/dev/null \
  || die "cannot read the open issues"
# Who opened each open issue and PR, which only the REST API reports: one array per page, cut down
# to what the steps use.
gh api --paginate --slurp "repos/$repo/issues?state=open&per_page=100" > "$work/opened.pages" 2>/dev/null \
  || die "cannot read who opened the open issues and pull requests"
jq -ce 'add // [] | map({number, html_url, created_at, author_association, user: {login: .user.login},
    labels: [.labels[] | {name}], pull_request: (if .pull_request then {} else null end)})' \
  "$work/opened.pages" > "$work/opened.json" 2>/dev/null || die "cannot read who opened the open issues and pull requests"
# Each PR's latest verdict by the squad's accounts, one object per PR, merged into one.
: > "$work/verdicts.jsonl"
for number in $(jq -r '.[] | select(.isDraft | not) | .number' "$work/prs.json"); do
  gh api --paginate --slurp "repos/$repo/pulls/$number/reviews" > "$work/reviews.json" 2>/dev/null \
    || die "cannot read the reviews of PR #$number"
  jq -c -L "$(dirname "$0")" --arg n "$number" 'include "squad-steps"; {($n): latest_verdict}' \
    "$work/reviews.json" >> "$work/verdicts.jsonl" || die "cannot read the reviews of PR #$number"
done
jq -sc 'add // {}' "$work/verdicts.jsonl" > "$work/verdicts.json" || exit 1

# 2. Who owns each item's next step, which items are quiet, and what to report given the sessions
#    and what was reported before. The new record replaces the old one: an item no longer stalled,
#    or with new activity, is forgotten.
{ [ -f "$state" ] && jq -Rc 'split("\t") | {key: .[0], at: (.[1] | tonumber), told: (.[2] == "1")}' "$state" | jq -sc . \
  || echo '[]'; } > "$work/reported.json"
result="$(jq -nc -L "$(dirname "$0")" --slurpfile prs "$work/prs.json" --slurpfile issues "$work/issues.json" \
  --slurpfile verdicts "$work/verdicts.json" --slurpfile opened "$work/opened.json" \
  --slurpfile reported "$work/reported.json" --argjson sessions "$sessions" --argjson now "$now" '
  include "squad-steps";
  $prs[0] as $prs | $issues[0] as $issues | $verdicts[0] as $verdicts | $opened[0] as $opened
  | $reported[0] as $reported
  | def local: strflocaltime("%Y-%m-%d %H:%M");
  # The issues and PRs opened from outside the squad, by number.
  ($opened | map(select(.author_association | IN("OWNER", "MEMBER", "COLLABORATOR") | not))
   | map({key: (.number | tostring), value: .}) | from_entries) as $outside
  | def inside: $outside[.number | tostring] == null;
  # A declared wait: needs-ceo or status:blocked on the item, or on the issue a PR closes, as
  # GitHub names it or as the description says ("Closes #N").
  def declared: any((.labels // [])[].name; endswith("needs-ceo") or endswith("status:blocked"));
  ($issues | map({key: (.number | tostring), value: declared}) | from_entries) as $waits
  | def waits: declared or any(closes[]; $waits[tostring] // false);
  # An outside item waits for its triage while it carries needs-triage or no owner label.
  def untriaged: any(.labels[].name; endswith("needs-triage")) or (any(.labels[].name; test("owner:(cto|dev|qa)$")) | not);
  # Who owns each next step, and what it is: pr_step and issue_step, from squad-steps.jq, which
  # squad-plan.sh shares (agent-squad #370).
  ([$prs | sort_by(.number)[] | select(inside) | select(waits | not) | {item: "PR #\(.number)", url, updatedAt} + pr_step($verdicts)]
   + [$issues | sort_by(.number)[] | select(inside) | select(declared | not) | select(any(.labels[].name; endswith("status:in-progress")))
      | {item: "#\(.number)", url, updatedAt} + issue_step]
   + [$outside | to_entries | sort_by(.key | tonumber)[] | .value | select(declared | not) | select(untriaged)
      | {item: "\(if .pull_request then "PR " else "" end)#\(.number)", url: .html_url, updatedAt: .created_at,
         owner: "CTO", step: "triage it: \(.user.login) opened it from outside the squad (\(.author_association))"}])
  # A wait for a requested reviewer comes to the CEO once it is an hour quiet, whatever the
  # sessions, and no one is pinged for it.
  | map(select($now - (.updatedAt | fromdateiso8601) >= (if .owner == "requested" then 3600 else 1800 end))
        | . + {since: (.updatedAt | fromdateiso8601 | local), key: "\(.item)|\(.owner)|\(.step)|\(.updatedAt)",
               session: (if .owner == "requested" then "reviewer" else $sessions[.owner] // "none" end)}
        | select(.session != "busy")
        | (.key as $k | $reported | map(select(.key == $k)) | first) as $before
        | if .session == "reviewer" then
            if $before == null then
              . + {action: "ceo", record: {key, at: $now, told: true},
                   why: "a review is requested from \(.reviewers) on GitHub, whom only the CEO can reach"}
            else . + {record: $before} end
          elif .session == "idle" then
            if $before == null then . + {action: "ping", record: {key, at: $now, told: false}}
            elif ($before.told | not) and $now - $before.at >= 3600 then
              . + {action: "ceo", why: "pinged at \($before.at | local), and nothing since", record: ($before + {told: true})}
            else . + {record: $before} end
          elif $before == null then
            . + {action: "ceo", record: {key, at: $now, told: true},
                 why: (if .session == "waiting" then "its session waits on the CEO in its own terminal" else "it has no session open" end)}
          else . + {record: $before} end)
  | {findings: [.[] | select(.action) | [.action, (.reviewers // .owner), .item, .url, .step, .since, (.why // "")] | @tsv],
     records: [.[] | .record | [.key, (.at | tostring), (if .told then "1" else "0" end)] | @tsv]}')" || exit 1

# 3. Keep the records, then print the findings.
{ jq -r '.records[]' <<<"$result" > "$state.$$" && mv "$state.$$" "$state"; } 2>/dev/null \
  || { rm -f "$state.$$"; cannot_keep; }
jq -r '.findings[]' <<<"$result"
