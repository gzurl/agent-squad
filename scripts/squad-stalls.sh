#!/usr/bin/env bash
# Find the squad's stalls (agent-squad #174): work that waits on an agent whose session is idle,
# which no message will wake. For each open pull request and each issue in progress it works out,
# from GitHub alone, who owns the next step:
# - a PR whose head has no verdict, or one bound to an earlier commit: its reviewer, QA, or DEV on
#   a PR that QA authors (SQUAD.md §4), to review the head;
# - a PR whose verdict on its head asks for changes: its author, to answer them;
# - a PR approved on its head: its author, to merge it;
# - a draft: its author, to finish it;
# - an issue in progress: the role of its owner label, to carry on; with none, the CTO.
# The author is the signature on the first line of the PR's description (§6), and only reviews by
# the repository's owner, its organization's members and its collaborators count (§4.9). An item
# whose wait is already declared is left out, and nothing is reported about it: one labelled
# needs-ceo, the CEO's inbox, or status:blocked, whose reason is in its last comment (§3), and a PR
# whose closing issue is (agent-squad #174, PR #193).
#
# An item has stalled when GitHub shows no activity on it (its updatedAt) for 30 minutes and its
# owner's session is idle: the owner is to be pinged, once. When the same stall is still there an
# hour after that, the CEO is to be told, once. A session that waits on the CEO in its own
# terminal, or that is not open, is reported to the CEO at once and never pinged; a busy one is
# working, and nothing is reported for it. The session states come from the CTO, who reads them
# with ListAgents, which a script cannot. What was reported is kept in .agent-squad/watch.tsv of
# the main checkout, which git ignores, so that each finding is reported once; an item with new
# activity starts afresh.
#
# With --current it reports no stalls and keeps no records: it prints, for each role, the item it
# works on now (agent-squad #205, for the squad board). That is the item whose next step the role
# owns, by the same rules, and with the most recent activity; failing one, the PR it authored that
# waits on someone else. Declared waits count here, since the role still works on them.
#
# Usage: squad-stalls.sh [--session <role>=<state>]... | squad-stalls.sh --current
#   <role> is CTO, DEV or QA, and <state> idle, busy or waiting; a role not given has no session.
# Output: one line per finding, tab-separated: what to do ("ping" the role, or tell the "ceo"),
#   the role, the item ("PR #12" or "#34"), its URL, the next step, since when it has been quiet
#   (local time), and, for the CEO, why. Nothing when there is nothing to report.
#   With --current, one line per role that has an item, in the order CTO, DEV, QA, tab-separated:
#   the role, the item, its URL, and its next step.
# Exit: 0 checked; 1 GitHub could not be read, so nothing was checked; 2 bad usage, or not run from
#   a checkout of a project the squad is installed in.
set -u

usage() { sed -n 's/^# Usage: /usage: /p' "$0" >&2; exit 2; }
die() { echo "squad-stalls: $*; nothing was checked" >&2; exit 1; }

# The options: each role's session state, as ListAgents shows it; or the current items alone.
sessions='{}'
current=false
while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      [ $# -ge 2 ] || usage
      [[ "$2" =~ ^(CTO|DEV|QA)=(idle|busy|waiting)$ ]] || usage
      sessions="$(jq -c --arg role "${2%%=*}" --arg state "${2#*=}" '.[$role] = $state' <<<"$sessions")"
      shift 2 ;;
    --current) current=true; shift ;;
    *) usage ;;
  esac
done
# The current items take no session states: they are not a stall check.
if $current && [ "$sessions" != '{}' ]; then usage; fi

# The main checkout, reached through the git directory every worktree shares, keeps what was
# reported.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || { echo "squad-stalls: run it from a checkout of a project the squad is installed in" >&2; exit 2; }
squad="$(dirname "$common")/.agent-squad"
[ -d "$squad" ] || { echo "squad-stalls: $(dirname "$common") has no .agent-squad/: the squad is not installed there" >&2; exit 2; }
state="$squad/watch.tsv"
# A record that cannot be kept would report the same findings on every pass: the run fails first.
cannot_keep() { echo "squad-stalls: cannot keep its records in $state${1:+: $1}" >&2; exit 1; }
$current || [ ! -e "$state" ] || [ -f "$state" ] || cannot_keep "it is not a file"
now="${SQUAD_NOW:-$(date +%s)}"

# 1. What GitHub holds: the open PRs, the latest verdict on each by the squad's accounts, and the
#    open issues. A call that fails stops the run: an unread GitHub must not read as no stall.
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || die "cannot read the repository from GitHub"
[ -n "$repo" ] || die "cannot read the repository from GitHub"
prs="$(gh pr list --state open --limit 1000 --json number,title,isDraft,headRefOid,body,updatedAt,url,labels,closingIssuesReferences 2>/dev/null)" \
  || die "cannot read the open pull requests"
issues="$(gh issue list --state open --limit 1000 --json number,title,labels,updatedAt,url 2>/dev/null)" \
  || die "cannot read the open issues"
verdicts='{}'
for number in $(jq -r '.[] | select(.isDraft | not) | .number' <<<"$prs"); do
  reviews="$(gh api --paginate --slurp "repos/$repo/pulls/$number/reviews" 2>/dev/null)" \
    || die "cannot read the reviews of PR #$number"
  verdicts="$(jq -c --arg n "$number" --argjson reviews "$reviews" '.[$n] = ($reviews | add // []
    | map(select((.author_association | IN("OWNER", "MEMBER", "COLLABORATOR")) and (.body | test("QA-VERDICT: "))))
    | last | if . == null then null
      else {commit: .commit_id, verdict: (.body | split("\n") | map(select(test("QA-VERDICT: "))) | last | sub(".*QA-VERDICT: "; ""))} end)' \
    <<<"$verdicts")"
done

# 2. Who owns each item's next step, which items are quiet, and what to report given the sessions
#    and what was reported before. The new record replaces the old one: an item no longer stalled,
#    or with new activity, is forgotten.
reported="$( ! $current && [ -f "$state" ] && jq -Rc 'split("\t") | {key: .[0], at: (.[1] | tonumber), told: (.[2] == "1")}' "$state" | jq -sc . || echo '[]')"
result="$(jq -nc --argjson prs "$prs" --argjson issues "$issues" --argjson verdicts "$verdicts" \
  --argjson sessions "$sessions" --argjson reported "$reported" --argjson now "$now" --argjson current "$current" '
  def local: strflocaltime("%Y-%m-%d %H:%M");
  # A declared wait: needs-ceo or status:blocked on the item, or on the issue a PR closes, as
  # GitHub names it or as the description says ("Closes #N").
  def declared: any((.labels // [])[].name; endswith("needs-ceo") or endswith("status:blocked"));
  ($issues | map({key: (.number | tostring), value: declared}) | from_entries) as $waits
  | def closes: [(.closingIssuesReferences // [])[].number]
      + [.body // "" | scan("(?i)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?) #([0-9]+)") | .[0] | tonumber];
  def waits: declared or any(closes[]; $waits[tostring] // false);
  def author: (.body // "" | split("\n") | first // "" | gsub("\\*\\*"; "")) as $line
    | first(("QA", "DEV", "CTO") as $role
        | select($line | startswith({QA: "👩🏼‍🔬", DEV: "👨🏼‍💻", CTO: "👷🏼‍♂️"}[$role] + "[\($role)]:")) | $role) // null;
  # A PR: the reviewer reviews a head with no verdict on it; the author answers changes asked on
  # the head, merges an approved head, and finishes a draft. Without an author, the CTO finds one.
  def pr_step:
    author as $author | (if $author == "QA" then "DEV" else "QA" end) as $reviewer
    | .headRefOid[0:7] as $head | $verdicts[.number | tostring] as $v
    | if $author == null then {owner: "CTO", step: "find its author: its description is not signed"}
      elif .isDraft then {owner: $author, step: "finish the draft"}
      elif $v == null or $v.commit != .headRefOid then {owner: $reviewer, step: "review its head \($head)"}
      elif $v.verdict == "CHANGES-REQUESTED" then {owner: $author, step: "answer the changes requested on \($head)"}
      elif $v.verdict == "APPROVED" then {owner: $author, step: "merge it: QA approved its head \($head)"}
      else {owner: $reviewer, step: "review its head \($head)"} end;
  # An issue in progress: its owner label names the role; without one, the CTO gives it an owner.
  def issue_step:
    ([.labels[].name | capture("owner:(?<role>cto|dev|qa)$").role | ascii_upcase] | first) as $owner
    | if $owner == null then {owner: "CTO", step: "give it an owner"} else {owner: $owner, step: "carry on with it"} end;
  # The items: every open PR and every issue in progress, but for a stall check those whose wait
  # is declared.
  ([$prs | sort_by(.number)[] | select($current or (waits | not))
     | {item: "PR #\(.number)", url, updatedAt, author: author} + pr_step]
   + [$issues | sort_by(.number)[] | select($current or (declared | not))
      | select(any(.labels[].name; endswith("status:in-progress")))
      | {item: "#\(.number)", url, updatedAt} + issue_step])
  # The current items: for each role, the item whose next step it owns with the latest activity;
  # failing one, the PR it authored that waits on someone else.
  | if $current then . as $items
    | {current: [("CTO", "DEV", "QA") as $role
        | first(($items | map(select(.owner == $role)) | sort_by(.updatedAt) | last | select(. != null)),
                ($items | map(select(.author == $role)) | sort_by(.updatedAt) | last | select(. != null)
                 | .step = "wait for \(.owner) to \(.step)"))
        | [$role, .item, .url, .step] | @tsv]}
  else map(select($now - (.updatedAt | fromdateiso8601) >= 1800)
        | . + {since: (.updatedAt | fromdateiso8601 | local), key: "\(.item)|\(.owner)|\(.step)|\(.updatedAt)",
               session: ($sessions[.owner] // "none")}
        | select(.session != "busy")
        | (.key as $k | $reported | map(select(.key == $k)) | first) as $before
        | if .session == "idle" then
            if $before == null then . + {action: "ping", record: {key, at: $now, told: false}}
            elif ($before.told | not) and $now - $before.at >= 3600 then
              . + {action: "ceo", why: "pinged at \($before.at | local), and nothing since", record: ($before + {told: true})}
            else . + {record: $before} end
          elif $before == null then
            . + {action: "ceo", record: {key, at: $now, told: true},
                 why: (if .session == "waiting" then "its session waits on the CEO in its own terminal" else "it has no session open" end)}
          else . + {record: $before} end)
  | {findings: [.[] | select(.action) | [.action, .owner, .item, .url, .step, .since, (.why // "")] | @tsv],
     records: [.[] | .record | [.key, (.at | tostring), (if .told then "1" else "0" end)] | @tsv]} end')" || exit 1

# 3. The current items are printed as they are; findings after their records are kept.
if $current; then jq -r '.current[]' <<<"$result"; exit 0; fi
{ jq -r '.records[]' <<<"$result" > "$state.$$" && mv "$state.$$" "$state"; } 2>/dev/null \
  || { rm -f "$state.$$"; cannot_keep; }
jq -r '.findings[]' <<<"$result"
