#!/usr/bin/env bash
# A release's timeline (agent-squad #574): where the time of each issue of a milestone went, from
# GitHub alone. One row per issue, the plan issues left out, by number:
# - its PR: the merged PR that closed it, or else the open PR that closes it, the latest of several;
# - the PR's author, the role whose signature opens its description, or with no PR the issue's
#   owner;
# - Before the PR: from the issue's first status:in-progress label to the PR's creation;
# - Waiting for QA, Fixing, Approved → merge: how long the PR carried status:in-review,
#   status:in-progress and status:approved, up to its merge;
# - Total: from the issue's first status:in-progress label to the merge, which counts the spans
#   with no status label too;
# - Rounds: the PR's reviews whose last line is a QA-VERDICT; Sent back: those that ask for
#   changes;
# - Findings: the PR's inline comments, replies left out, and its PR comments, whose first line
#   opens with a priority tag after the signature and status emoji, by priority.
# Only the reviews and comments of the repository's owner, its organization's members and its
# collaborators count, as for the merge gate (SQUAD.md §4.9). A total row follows: each column the
# sum of the values above it.
#
# Times are wall-clock, in whole minutes rounded down: a night or a /squad-pause counts, which a
# line under the table says. While an issue or its PR is open, its times run to the time of the
# run. A cell with no data shows —, and a note under the table says why; a 0 is a span measured as
# under a minute. Everything comes from GitHub: the milestones, the open issues for the plan
# issues, one GraphQL query per milestone for its issues, their labels and the PRs that close them,
# and two calls per PR, its timeline and its inline comments.
#
# Usage: squad-timeline.sh [<milestone>]
#   <milestone> is a milestone's title, or the first word of it, as v76. Without it, the milestone
#   of each open plan issue (SQUAD.md §3), the releases in progress; with none, the milestone
#   closed last.
# Output: each milestone's table, in Markdown, a blank line between two: a title line, the table,
#   the line on wall-clock time, and the notes. With no milestone in progress or closed, one line
#   says so.
# Exit: 0 done; 1 GitHub could not be read, with gh's message; 2 bad usage, a milestone that is not
#   there or that several titles start with, or not run from a git checkout.
set -u
# jq on Windows ends each line with CRLF, and the shell keeps the CR in what it reads, as in an id
# sent to GitHub, which then refuses it (agent-squad #405): every jq of this script drops it here.
jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }
usage() { sed -n 's/^# Usage: /usage: /p' "$0" >&2; exit 2; }
die() { echo "timeline: $*" >&2; exit 1; }
# Each GitHub call goes through squad-timeout.sh, beside this script, which stops it after
# SQUAD_GH_TIMEOUT seconds of wall-clock time (120 when unset, or not a whole number above 0),
# saying so above the run's own message (agent-squad #430).
gh_seconds="${SQUAD_GH_TIMEOUT:-120}"
[[ "$gh_seconds" =~ ^[1-9][0-9]*$ ]] || gh_seconds=120
gh() { "$(dirname "$0")/squad-timeout.sh" "$gh_seconds" gh "$@"; }
case $# in
  0) wanted="" ;;
  1) [ -n "$1" ] && [ "${1#-}" = "$1" ] || usage; wanted="$1" ;;
  *) usage ;;
esac
git rev-parse --git-dir >/dev/null 2>&1 || { echo "timeline: run it from a checkout of the project" >&2; exit 2; }
here="$(dirname "$0")"
now="${SQUAD_NOW:-$(date +%s)}"

# What GitHub answers goes to jq through files of a work directory. `fetch <file> <gh arguments>`
# writes gh's answer to the file, and shows gh's messages only when it fails: gh prints hints on
# stderr for some of these calls.
work="${TMPDIR:-/tmp}"
work="$(mktemp -d "${work%/}/squad-timeline.XXXXXX")" || die "cannot make a work directory"
trap 'rm -rf "$work"' EXIT
fetch() {
  local file="$1"
  shift
  gh "$@" </dev/null > "$file" 2> "$work/gh.err" && return 0
  cat "$work/gh.err" >&2
  return 1
}

# 1. The milestones to show: the one named, or those of the open plan issues, or else the one
#    closed last.
fetch "$work/repo" repo view --json nameWithOwner --jq .nameWithOwner || die "cannot read the repository, as gh says above"
repo="$(cat "$work/repo")"
fetch "$work/milestones.pages" api --paginate --slurp "repos/$repo/milestones?state=all&per_page=100" \
  || die "cannot read the milestones, as gh says above"
jq -c 'add // [] | map({number, title, state, closed_at, html_url})' "$work/milestones.pages" > "$work/milestones.json" \
  || die "cannot read the milestones"
if [ -n "$wanted" ]; then
  # The milestone of that title, or else those whose title starts with it, as its first word.
  jq -c --arg wanted "$wanted" 'map(select(.title == $wanted)) as $exact
    | if $exact != [] then $exact else map(select(.title | startswith($wanted + " "))) end' \
    "$work/milestones.json" > "$work/chosen.json" || die "cannot read the milestones"
  case "$(jq length "$work/chosen.json")" in
    1) ;;
    0) echo "timeline: no milestone's title is $wanted or starts with it" >&2; exit 2 ;;
    *) echo "timeline: several milestones' titles start with $wanted: $(jq -r 'map(.title) | join("; ")' "$work/chosen.json")" >&2
       exit 2 ;;
  esac
else
  fetch "$work/open.pages" api --paginate --slurp "repos/$repo/issues?state=open&per_page=100" \
    || die "cannot read the open issues, as gh says above"
  jq -c -L "$here" --slurpfile milestones "$work/milestones.json" 'include "squad-steps";
    [add // [] | .[] | select(.pull_request == null and .milestone != null and (.body // "" | gsub("\r"; "") | marked))
     | .milestone.number] as $planned
    | $milestones[0] as $all
    | [$all[] | select(.number | IN($planned[]))] | sort_by(.number)
    | if . == [] then [$all | map(select(.state == "closed")) | sort_by(.closed_at) | last // empty] else . end' \
    "$work/open.pages" > "$work/chosen.json" || die "cannot read the open issues"
  if [ "$(jq length "$work/chosen.json")" = 0 ]; then
    echo "timeline: no milestone is in progress, with an open plan issue, nor closed"
    exit 0
  fi
fi

# `timeline <milestone>` prints the milestone's table, given its REST JSON.
timeline() {
  local number pr
  number="$(jq -r .number <<<"$1")"
  # Its issues, with their labels, when each was labelled, and the PRs of this repository that
  # close them, merged, open or closed, by pages of 100.
  # shellcheck disable=SC2016 # the $ are GraphQL's variables
  fetch "$work/issues.pages" api graphql --paginate --slurp -F owner="${repo%%/*}" -F name="${repo#*/}" -F milestone="$number" -f query='
    query($owner: String!, $name: String!, $milestone: Int!, $endCursor: String) {
      repository(owner: $owner, name: $name) { milestone(number: $milestone) {
        issues(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes {
          number state body labels(first: 100) { nodes { name } }
          timelineItems(itemTypes: [LABELED_EVENT], first: 100) { nodes { ... on LabeledEvent { createdAt label { name } } } }
          closedByPullRequestsReferences(first: 25, includeClosedPrs: true) { nodes {
            number state body createdAt mergedAt repository { nameWithOwner } } }
      } } } } }' \
    || die "cannot read the issues of $(jq -r .title <<<"$1"), as gh says above"
  # Each issue, the plan issues left out: when it first went in progress, its owner, and its PR.
  jq -c -L "$here" --arg repo "$repo" 'include "squad-steps";
    [.[].data.repository.milestone.issues.nodes[] | .body = (.body // "" | gsub("\r"; "")) | select(.body | marked | not)
     | {number, open: (.state == "OPEN"), labels: .labels.nodes,
        start: ([.timelineItems.nodes[] | select(.label.name // "" | endswith("status:in-progress")) | .createdAt] | first),
        pr: ([.closedByPullRequestsReferences.nodes[] | select(.repository.nameWithOwner == $repo)] as $prs
             | ($prs | map(select(.state == "MERGED")) | sort_by(.mergedAt) | last)
               // ($prs | map(select(.state == "OPEN")) | sort_by(.number) | last))}]
    | sort_by(.number)' "$work/issues.pages" > "$work/issues.json" \
    || die "cannot read the issues of $(jq -r .title <<<"$1")"

  # Each PR's status labels, verdicts and findings, from its timeline and its inline comments, one
  # object per PR, merged into one.
  : > "$work/prs.jsonl"
  for pr in $(jq -r '.[].pr.number // empty' "$work/issues.json"); do
    fetch "$work/timeline.pages" api --paginate --slurp "repos/$repo/issues/$pr/timeline?per_page=100" \
      || die "cannot read the timeline of PR #$pr, as gh says above"
    fetch "$work/inline.pages" api --paginate --slurp "repos/$repo/pulls/$pr/comments?per_page=100" \
      || die "cannot read the inline comments of PR #$pr, as gh says above"
    jq -c -L "$here" --arg n "$pr" --slurpfile inline "$work/inline.pages" 'include "squad-steps";
      def inside: .author_association | IN("OWNER", "MEMBER", "COLLABORATOR");
      def text: .body // "" | gsub("\r"; "");
      # A finding opens with a priority tag after its signature and status emoji (SQUAD.md §4.6,
      # §4.8).
      def priority: text | select(signed("^ *(✅|⏳|⚠️?|❌)? *\\[P[123]\\]")) | split("\n")[0] | capture("\\[P(?<p>[123])\\]").p;
      add // [] | {($n): {
        labels: [.[] | select(.event == "labeled" or .event == "unlabeled") | select(.label.name | test("status:"))
                 | {name: .label.name, on: (.event == "labeled"), at: (.created_at | fromdateiso8601)}],
        verdicts: [.[] | select(.event == "reviewed" and inside)
                   | text | split("\n") | map(select(test("\\S"))) | last // ""
                   | capture("^QA-VERDICT: (?<v>APPROVED|CHANGES-REQUESTED)\\s*$").v],
        findings: ([.[] | select(.event == "commented" and inside) | priority]
                   + [$inline[0] | add // [] | .[] | select(.in_reply_to_id == null and inside) | priority])}}' \
      "$work/timeline.pages" >> "$work/prs.jsonl" || die "cannot read the timeline of PR #$pr"
  done
  jq -sc 'add // {}' "$work/prs.jsonl" > "$work/prs.json" || die "cannot read the PRs"

  # The table, its line on wall-clock time, and its notes.
  jq -nr -L "$here" --argjson milestone "$1" --slurpfile issues "$work/issues.json" --slurpfile prs "$work/prs.json" \
    --argjson now "$now" 'include "squad-steps";
    $issues[0] as $issues | $prs[0] as $prs | ($now | strflocaltime("%Y-%m-%d %H:%M")) as $at
    # Minutes as a cell shows them: "—" for no data, "N min", or "H h M min" from an hour on.
    | def shown: if . == null then "—" elif . >= 60 then "\(. / 60 | floor) h \(. % 60) min" else "\(.) min" end;
    def minutes: if . == null then null else . / 60 | floor end;
    # How long a PR carried a status label between two times, from its label events in order.
    def carried($name; $from; $to): reduce (.[] | select(.name | endswith($name))) as $e ({since: null, total: 0};
        if $e.on then .since //= $e.at
        elif .since == null then .
        else .total += ([([$e.at, $to] | min) - ([.since, $from] | max), 0] | max) | .since = null end)
      | .total + (if .since == null then 0 else [$to - ([.since, $from] | max), 0] | max end);
    def findings: group_by(.) | map("P\(.[0]) \(length)") | if . == [] then "—" else join(" · ") end;
    # A row: its cells as numbers, null for no data, and the notes on why.
    def row:
      . as $issue | (.start | if . then fromdateiso8601 else null end) as $start
      | .pr as $pr | ($pr.number // null) as $n | ($prs[$n | tostring] // null) as $events
      | ($pr.createdAt // null | if . then fromdateiso8601 else null end) as $created
      | (if $pr == null then (if $issue.open then $now else null end)
         else ($pr.mergedAt // null | if . then fromdateiso8601 else $now end) end) as $end
      | ($events.labels // [] | sort_by(.at)) as $labels
      | {issue: "#\(.number)", pr: (if $n then "#\($n)" else "—" end),
         author: (($pr | if . then author else null end) // owner // "—"),
         before: (if $start == null then null
                  elif $pr == null then (if $issue.open then $now - $start else null end)
                  elif $created < $start then null else $created - $start end | minutes),
         qa: (if $labels == [] then null else $labels | carried("status:in-review"; $created; $end) | minutes end),
         fixing: (if $labels == [] then null else $labels | carried("status:in-progress"; $created; $end) | minutes end),
         approved: (if $labels == [] then null else $labels | carried("status:approved"; $created; $end) | minutes end),
         total: (if $start == null or $end == null then null else $end - $start | minutes end),
         rounds: ($events.verdicts // null | if . then length else null end),
         sent: ($events.verdicts // null | if . then map(select(. == "CHANGES-REQUESTED")) | length else null end),
         findings: ($events.findings // null),
         notes: [
           (if $start == null and $pr == null and $issue.open then "not started yet"
            elif $start == null then "never labelled in progress, so Before the PR and Total have no start"
            elif $pr != null and $created < $start then "labelled in progress only after PR #\($n) was opened, so Before the PR has no span"
            else empty end),
           (if $pr == null then
              (if ($issue.open | not) then "closed with no merged PR, so the PR'"'"'s columns have no data"
               elif $start != null then "no open PR yet: its times run to \($at)" else empty end)
            elif $pr.mergedAt == null then "PR #\($n) is not merged yet: its times run to \($at)"
            else empty end),
           (if $pr != null and $labels == [] then "PR #\($n) never carried a status label, so its three label columns have no data"
            else empty end)]};
    ($issues | map(row)) as $rows
    # The sum of a column, null when no row has data.
    | def sum($key): [$rows[][$key] | numbers] | if . == [] then null else add end;
    "**[\($milestone.title)](\($milestone.html_url))** · \($issues | map(select(.open | not)) | length) of \($issues | length) issues closed · as of \($at)",
    "",
    "| | Issue | PR | Author | Before the PR | Waiting for QA | Fixing | Approved → merge | Total | Rounds | Sent back | Findings |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ($rows | to_entries[] | .value as $r
     | "| \(.key + 1) | \($r.issue) | \($r.pr) | \($r.author) | \($r.before | shown) | \($r.qa | shown) | \($r.fixing | shown) | \($r.approved | shown) | \($r.total | shown) | \($r.rounds // "—") | \($r.sent // "—") | \($r.findings // [] | findings) |"),
    "| | **Total** | | | \(sum("before") | shown) | \(sum("qa") | shown) | \(sum("fixing") | shown) | \(sum("approved") | shown) | \(sum("total") | shown) | \(sum("rounds") // "—") | \(sum("sent") // "—") | \([$rows[].findings // [] | .[]] | findings) |",
    "",
    "Times are wall-clock, not effort: a night or a `/squad-pause` counts.",
    ($rows[] | .issue as $issue | .notes[] | "- \($issue): \(.).")' \
    || die "cannot build the table of $(jq -r .title <<<"$1")"
}

# 2. Each milestone's table, a blank line between two.
first=true
while IFS= read -r milestone; do
  $first || echo
  first=false
  timeline "$milestone" || exit 1
done < <(jq -c '.[]' "$work/chosen.json")
