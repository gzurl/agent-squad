#!/usr/bin/env bash
# The plan of each release in progress (agent-squad #370): a table the CEO reads at a glance, on a
# phone too. A release in progress is a milestone with an open plan issue: an issue of that
# milestone, pinned so that the CEO finds it on GitHub (SQUAD.md §3), whose description holds the
# markers <!-- squad-plan:start --> and <!-- squad-plan:end -->, each on a line of its own, the
# start before the end; an issue that quotes them inline is none. Each open plan issue gets its own
# milestone's table, so that a milestone left open by mistake takes none, and a project's milestones
# need no particular name.
#
# A table has one row per issue of the milestone, the plan issues left out, by priority, then
# number: the issue, its owner, where it stands, and the next step and whose it is, from
# squad-steps.jq, which the stall detector shares. Then the release's own steps: the CEO's read of
# the README, which SQUAD.md §3 asks of a milestone that does not only fix things, and, where the repository tracks SQUAD.md
# with a Version: line, as the method's own repository does, and the milestone's title starts with
# vN, the version PR before it, and the tag, the Release and the install here after it. While the
# version PR is open, its row shows it as an issue's row shows its PR: the version PR names the plan
# issue ("Part of #N") and closes no issue (SQUAD.md §3, agent-squad #384). Everything comes from
# GitHub, except the install, which comes from .agent-squad/install.log of the main checkout.
#
# --update rewrites what lies between each plan issue's markers, and only when the table changed,
# its time left out. Editing a description notifies nobody, and updates by several agents converge,
# since each rebuilds the table from GitHub as it is. It also keeps the plan issue's sub-issues in
# step with its milestone (agent-squad #391): each issue of the milestone, open or closed, the plan
# issues left out, is one, and a sub-issue that left the milestone is removed. An issue with
# another parent stays under it: GitHub refuses a second parent, and moving it could undo someone's
# structure. GitHub allows 100 sub-issues per issue, so those past that stay out, said on the line.
# Sub-issues are matched by id, and parents by URL, since either may be another repository's. They
# go through gh api, which any gh can call. A sub-issue that cannot be read or written stops no
# other plan: every table is still written, and the run ends with exit status 1.
#
# Usage: squad-plan.sh [--update]
# Output: each table, in Markdown, a blank line between two; with --update, after each table, one
#   line: "plan: #371 updated" or "plan: #371 unchanged", then what changed in its sub-issues, as
#   "; sub-issues added: #12, #13", "; sub-issues removed: #9", "; #30 not added: GitHub allows
#   100 sub-issues", past three issues their count, and "; #14 left under its parent #20" for an
#   issue with another parent. A plan issue with no milestone gets one line that says so, and with
#   no open plan issue, one line says so, and nothing else.
# Exit: 0 done; 1 GitHub could not be read, or a plan issue or its sub-issues could not be
#   written, with gh's message; 2 bad usage, or not run from a checkout of a project the squad is
#   installed in.
set -u
# jq on Windows ends each line with CRLF, and the shell keeps the CR in what it reads, as in an id
# sent to GitHub, which then refuses it (agent-squad #405): every jq of this script drops it here.
jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }
usage() { sed -n 's/^# Usage: /usage: /p' "$0" >&2; exit 2; }
die() { echo "plan: $*" >&2; exit 1; }
update=false
case "$*" in
  "") ;;
  --update) update=true ;;
  *) usage ;;
esac

# The main checkout, reached through the git directory every worktree shares, keeps install.log.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || { echo "plan: run it from a checkout of a project the squad is installed in" >&2; exit 2; }
squad="$(dirname "$common")/.agent-squad"
[ -d "$squad" ] || { echo "plan: $(dirname "$common") has no .agent-squad/: the squad is not installed there" >&2; exit 2; }
here="$(dirname "$0")"
now="${SQUAD_NOW:-$(date +%s)}"
markers="<!-- squad-plan:start --> and <!-- squad-plan:end -->"
# GitHub's limit on an issue's sub-issues (its documentation, "Adding sub-issues").
limit=100
# A plan issue's markers stand on lines of their own, the start before the end: an issue that only
# quotes them, as one that describes the plan does, is none, and a row of the table. `plan_parts`
# splits a description into what comes before the table, the table, and what comes after; `marked`
# tells a plan issue's description.
plan_defs='def plan_parts: ("\n" + . + "\n")
    | capture("^(?<before>[\\s\\S]*?\n)<!-- squad-plan:start -->\n(?<table>[\\s\\S]*?)(?<=\n)<!-- squad-plan:end -->\n(?<after>[\\s\\S]*)$");
  def marked: [plan_parts] != [];'

# 1. The open plan issues, each with its milestone. What GitHub answers goes to jq through files of
#    a work directory.
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null)" || die "cannot read the repository, as gh says above"
work="${TMPDIR:-/tmp}"
work="$(mktemp -d "${work%/}/squad-plan.XXXXXX")" || die "cannot make a work directory"
trap 'rm -rf "$work"' EXIT
gh api --paginate --slurp "repos/$repo/issues?state=open&per_page=100" </dev/null > "$work/open.pages" \
  || die "cannot read the open issues, as gh says above"
jq -c "$plan_defs"'add // [] | map(select(.pull_request == null) | .body = (.body // "" | gsub("\r"; "")) | select(.body | marked))
  | sort_by(.number)[] | {number, url, body, labels: [.labels[] | {name}],
    milestone: (.milestone | if . then {number, title, url: .html_url} else null end)}' "$work/open.pages" > "$work/plans.jsonl" \
  || die "cannot read the open issues"
if [ ! -s "$work/plans.jsonl" ]; then
  echo "plan: no open issue is a plan issue, whose description holds $markers; no release is in progress"
  exit 0
fi

# 2. What every table shares: the open PRs, and whether the repository tracks SQUAD.md with a
#    Version: line on its default branch, and which.
gh pr list --state open --limit 1000 --json number,isDraft,headRefOid,body,closingIssuesReferences,reviewRequests,statusCheckRollup \
  </dev/null > "$work/open-prs.json" || die "cannot read the open pull requests, as gh says above"
files="$(gh api "repos/$repo/contents" --jq '.[].name' </dev/null)" || die "cannot read the repository's files, as gh says above"
charter=""
if grep -qxF SQUAD.md <<<"$files"; then
  gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/SQUAD.md" </dev/null > "$work/SQUAD.md" \
    || die "cannot read SQUAD.md, as gh says above"
  charter="$(sed -n 's/^> \*\*Version:\*\* \([0-9][0-9]*\).*/\1/p' "$work/SQUAD.md" | head -1)"
fi

# `table <plan issue>` prints the table of the plan issue's milestone, given as its JSON.
table() {
  local plan="$1" number version release=null tagged installed
  number="$(jq -r .milestone.number <<<"$plan")"
  # Its issues, open and closed, each with its id and its parent's URL, if it has one, for the
  # sub-issues; and the PR that closed each closed one, from its closing event: the PR itself,
  # or the PR of the commit that closed it, as a squash merge's commit (QA's finding on PR #377).
  # The closed issues come by pages of 100, as the issues do.
  gh api --paginate --slurp "repos/$repo/issues?milestone=$number&state=all&per_page=100" </dev/null > "$work/issues.pages" \
    || die "cannot read the issues of the milestone, as gh says above"
  jq -c 'add // [] | map(select(.pull_request == null)
    | {number, id, title, state, body: (.body // "" | gsub("\r"; "")), labels: [.labels[] | {name}],
       parent: .parent_issue_url})' \
    "$work/issues.pages" > "$work/issues.json" || die "cannot read the issues of the milestone"
  # shellcheck disable=SC2016 # the $ are GraphQL's variables
  gh api graphql --paginate --slurp -F owner="${repo%%/*}" -F name="${repo#*/}" -F milestone="$number" -f query='
    query($owner: String!, $name: String!, $milestone: Int!, $endCursor: String) {
      repository(owner: $owner, name: $name) { milestone(number: $milestone) {
        issues(first: 100, states: CLOSED, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes {
          number timelineItems(itemTypes: [CLOSED_EVENT], last: 1) { nodes { ... on ClosedEvent { closer {
            ... on PullRequest { number } ... on Commit { associatedPullRequests(first: 1) { nodes { number } } } } } } }
      } } } } }' \
    </dev/null > "$work/closers.pages" || die "cannot read the PRs that closed the milestone's issues, as gh says above"
  jq -c '[.[].data.repository.milestone.issues.nodes[] | {key: (.number | tostring),
      value: (.timelineItems.nodes[0].closer // {} | .number // .associatedPullRequests.nodes[0].number)}] | from_entries' \
    "$work/closers.pages" > "$work/closers.json" || die "cannot read the PRs that closed the milestone's issues"

  # The open PRs that close one of its issues; the release's version PR, the open PR that names the
  # plan issue ("Part of #N") and closes no issue, the highest-numbered of several, as a list of one
  # or none (agent-squad #384); and the latest verdict on each.
  jq -c -L "$here" --slurpfile issues "$work/issues.json" 'include "squad-steps";
    [$issues[0][].number] as $ours | map(select(any(closes[]; IN($ours[]))))' "$work/open-prs.json" > "$work/prs.json" \
    || die "cannot read the open pull requests"
  jq -c -L "$here" --argjson plan_issue "$(jq .number <<<"$plan")" 'include "squad-steps";
    map(select(closes == [] and any(.body // "" | scan("(?i)\\bpart of #([0-9]+)"); .[0] | tonumber == $plan_issue)))
    | sort_by(.number) | .[-1:]' "$work/open-prs.json" > "$work/version-pr.json" \
    || die "cannot read the open pull requests"
  : > "$work/verdicts.jsonl"
  for pr in $(jq -r '.[] | select(.isDraft | not) | .number' "$work/prs.json" "$work/version-pr.json"); do
    gh api --paginate --slurp "repos/$repo/pulls/$pr/reviews" </dev/null > "$work/reviews.json" \
      || die "cannot read the reviews of PR #$pr, as gh says above"
    jq -c -L "$here" --arg n "$pr" 'include "squad-steps"; {($n): latest_verdict}' "$work/reviews.json" >> "$work/verdicts.jsonl" \
      || die "cannot read the reviews of PR #$pr"
  done
  jq -sc 'add // {}' "$work/verdicts.jsonl" > "$work/verdicts.json" || die "cannot read the reviews"

  # The release's own steps, where SQUAD.md has a version and the milestone's title starts with vN:
  # whether the tag and its Release exist, and whether the last install here installed it.
  version="$(jq -r '.milestone.title | capture("^v(?<n>[0-9]+)").n // empty' <<<"$plan")"
  if [ -n "$charter" ] && [ -n "$version" ]; then
    tagged="$(gh api "repos/$repo/git/matching-refs/tags/v$version" --jq "any(.[]; .ref == \"refs/tags/v$version\")" </dev/null)" \
      || die "cannot read the tags, as gh says above"
    gh api --paginate --slurp "repos/$repo/releases?per_page=100" </dev/null > "$work/releases.json" \
      || die "cannot read the Releases, as gh says above"
    installed=false
    ! tail -1 "$squad/install.log" 2>/dev/null | grep -q -- "-> v$version\$" || installed=true
    release="$(jq -c --argjson charter "$charter" --argjson version "$version" --argjson tagged "$tagged" --argjson installed "$installed" \
      '{charter: $charter, version: $version, tagged: $tagged, published: (add // [] | any(.[]; .tag_name == "v\($version)")),
        installed: $installed}' "$work/releases.json")" || die "cannot read the Releases"
  fi

  # The table, in the CEO's format (agent-squad #370): a title line, then one row per issue, then
  # the release's own steps, all in English; the CTO translates the cells in its terminal.
  jq -nr -L "$here" --slurpfile issues "$work/issues.json" --slurpfile prs "$work/prs.json" \
    --slurpfile version_prs "$work/version-pr.json" --slurpfile verdicts "$work/verdicts.json" \
    --slurpfile closers "$work/closers.json" --argjson plan "$plan" --argjson release "$release" --argjson now "$now" '
    include "squad-steps";'"$plan_defs"'
    $issues[0] as $issues | $prs[0] as $prs | $version_prs[0][0] as $version_pr | $verdicts[0] as $verdicts
    | $closers[0] as $closers
    | def labelled($end): any(.labels[].name; endswith($end));
    def plan_issue: .body | marked;
    def priority: if labelled("P1") then 1 elif labelled("P2") then 2 elif labelled("P3") then 3 else 4 end;
    # A title short enough for a phone, cut at a word, and safe in a table cell.
    def short: (if length > 48 then (.[0:47] | sub(" [^ ]*$"; "")) + "…" else . end) | gsub("\\|"; "\\|");
    # A PR'"'"'s CI, from its checks: failed, running, passed, or none.
    def ci: [(.statusCheckRollup // [])[] | if .__typename == "StatusContext" then .state
               elif .status == "COMPLETED" then .conclusion else "PENDING" end] as $results
      | if $results == [] then "no CI"
        elif any($results[]; IN("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE")) then "CI ❌"
        elif any($results[]; IN("PENDING", "EXPECTED")) then "CI ⏳"
        else "CI ✅" end;
    # An open PR: where it stands, with its head and its CI, and its next step and whose it is, the
    # step the stall detector gives a PR.
    def pr_cells:
      $verdicts[.number | tostring] as $v | pr_step($verdicts) as $step
      | {state: ("👀 PR #\(.number) "
          + (if .isDraft then "draft" elif $v == null or $v.commit != .headRefOid then "in review"
             elif $v.verdict == "APPROVED" then "approved" else "changes requested" end)
          + " (`\(.headRefOid[0:7])`), \(ci)"),
         next: (if $step.owner == "requested" then $step.short else "\($step.owner): \($step.short)" end)};
    # An issue: where it stands, and its next step and whose it is. Its open PR, the latest that
    # closes it, stands for it.
    def row:
      . as $issue | owner as $owner
      | ([$prs[] | select(any(closes[]; . == $issue.number))] | sort_by(.number) | last) as $pr
      | (if .state == "closed" then
           {state: ("✅ closed" + ($closers[.number | tostring] // null | if . then " by PR #\(.)" else "" end)), next: "—"}
         elif labelled("needs-ceo") then {state: "👨🏻‍💼 waits for the CEO", next: "CEO: decide"}
         elif labelled("status:blocked") then {state: "⛔ blocked", next: "\($owner // "CTO"): unblock it"}
         elif $pr != null then $pr | pr_cells
         elif labelled("status:in-progress") then issue_step as $step | {state: "🚧 in progress", next: "\($step.owner): \($step.short)"}
         elif labelled("status:in-review") then issue_step as $step | {state: "👀 in review, no open PR", next: "\($step.owner): \($step.short)"}
         elif $owner == null then {state: "⚪ not started", next: "CTO: give it an owner"}
         else {state: "⚪ not started", next: "\($owner): start it"} end)
      | {step: "#\($issue.number) \($issue.title | short)", who: ($owner // "—")} + .;
    ($issues | map(select(plan_issue | not))) as $items
    # What a step that cannot start yet waits for: the open issues, by number, or how many, past three.
    | ($items | map(select(.state == "open")) | sort_by(.number) | map("#\(.number)")) as $open
    | (if $open == [] then null elif ($open | length) > 3 then "waits for \($open | length) issues"
       else "waits for \($open | join(", "))" end) as $waits
    | ($plan | labelled("needs-ceo")) as $asked
    # The release'"'"'s own steps: the README read everywhere; the version PR, the tag, the Release
    # and the install where the repository tracks SQUAD.md with a Version: line. The version PR,
    # while it is open, shows as an issue'"'"'s PR does, whether the milestone'"'"'s issues are closed or not.
    | (if $release == null then
         [{step: "README read", who: "CEO",
           state: (if $asked then "⏳ waits for the CEO" elif $waits then "⚪ \($waits)" else "⚪ not asked yet" end),
           next: (if $asked then "CEO: read it" elif $waits then "—" else "CTO: ask the CEO" end)}]
       else
         ($release.charter >= $release.version) as $versioned
         | [{step: "Version PR", who: "CTO"}
            + (if $versioned then {state: "✅ done", next: "—"}
               elif $version_pr != null then $version_pr | pr_cells
               elif $waits then {state: "⚪ \($waits)", next: "—"}
               else {state: "⚪ not started", next: "CTO: open it"} end),
            {step: "README read", who: "CEO",
             state: (if $release.tagged then "✅ done" elif $asked then "⏳ waits for the CEO"
                     elif $versioned | not then "⚪ waits for the version PR" else "⚪ not asked yet" end),
             next: (if $release.tagged then "—" elif $asked then "CEO: read it" elif $versioned then "CTO: ask the CEO" else "—" end)},
            {step: "Tag, Release, install here", who: "CTO",
             state: (if $release.tagged and $release.published and $release.installed then "✅ done"
                     elif $release.tagged | not then "⚪ waits for the CEO'"'"'s OK"
                     else "⏳ tag ✅, Release \(if $release.published then "✅" else "⚪" end), install \(if $release.installed then "✅" else "⚪" end)" end),
             next: (if $release.tagged and $release.published and $release.installed then "—"
                    elif $release.tagged | not then "CTO: tag it, on the CEO'"'"'s OK"
                    elif $release.published | not then "CTO: publish the Release" else "CTO: install it here" end)}]
       end) as $steps
    | ($items | sort_by(priority, .number) | map(row)) + $steps
    | "🗺️ **[\($plan.milestone.title)](\($plan.milestone.url))** · \($items | map(select(.state == "closed")) | length) of \($items | length) issues closed · updated \($now | strflocaltime("%Y-%m-%d %H:%M"))",
      "",
      "| | 📌 Step | 👤 Who | 🚦 State | ⏭️ Next |",
      "|---|---|---|---|---|",
      (to_entries[] | "| \(.key + 1) | \(.value.step) | \(.value.who) | \(.value.state) | \(.value.next) |")' \
    || die "cannot build the table"
}

# `rewrite <plan issue> <table>` writes the table between the plan issue's markers, when it changed
# with its time left out, and says which: "updated" or "unchanged".
rewrite() {
  local number
  number="$(jq -r .number <<<"$1")"
  jq -r --arg table "$2" "$plan_defs"'.body | plan_parts as $parts
    | def timeless: gsub(" · updated [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}"; "") | ltrimstr("\n") | rtrimstr("\n");
    if ($parts.table | timeless) == ($table | timeless) then empty
    else $parts.before + "<!-- squad-plan:start -->\n" + $table + "\n<!-- squad-plan:end -->\n" + $parts.after | .[1:-1] end' \
    <<<"$1" > "$work/body.md"
  if [ ! -s "$work/body.md" ]; then
    echo unchanged
  else
    gh issue edit "$number" --body-file "$work/body.md" </dev/null >/dev/null || die "cannot write the plan issue #$number, as gh says above"
    echo updated
  fi
}

# `adopt <plan issue>` makes the plan issue's sub-issues its milestone's issues, as table() last
# read them (agent-squad #391), and says what changed, as the end of the plan issue's line: the
# issues it added, the sub-issues it removed, the issues GitHub's limit keeps out, and each issue
# left under another parent. A sub-issue or a parent of another repository is named with it.
adopt() {
  local number pair
  number="$(jq -r .number <<<"$1")"
  gh api --paginate --slurp "repos/$repo/issues/$number/sub_issues?per_page=100" </dev/null > "$work/subs.pages" \
    || die "cannot read the sub-issues of #$number, as gh says above"
  jq -c --arg plan "$(jq -r .url <<<"$1")" --arg repo "$repo" --argjson limit "$limit" --slurpfile subs "$work/subs.pages" "$plan_defs"'
    # An issue as the line names it, from its repository and number: "#12", or "owner/name#12".
    def named($r; $n): if $r == $repo then "#\($n)" else "\($r)#\($n)" end;
    ($subs[0] | add // [] | map({id, number, name: named(.repository_url // "" | sub("^.*/repos/"; ""); .number)})) as $subs
    | map(select(.body | marked | not) | {id, number, name: "#\(.number)", parent}) | sort_by(.number) as $items
    | [$subs[] | select(.id | IN($items[].id) | not)] as $remove
    | [$items[] | select(.parent == null and (.id | IN($subs[].id) | not))] as $missing
    | ([$limit - ($subs | length) + ($remove | length), 0] | max) as $room
    | {add: $missing[:$room], full: $missing[$room:], remove: ($remove | sort_by(.name)),
       others: [$items[] | select(.parent != null and .parent != $plan)
         | .parent |= (capture("/repos/(?<r>[^/]+/[^/]+)/issues/(?<n>[0-9]+)$") | named(.r; .n))]}' \
    "$work/issues.json" > "$work/adopt.json" || die "cannot read the sub-issues of #$number"
  for pair in $(jq -r '.remove[] | "\(.name):\(.id)"' "$work/adopt.json"); do
    gh api -X DELETE "repos/$repo/issues/$number/sub_issue" -F sub_issue_id="${pair##*:}" </dev/null >/dev/null \
      || die "cannot remove ${pair%:*} from the sub-issues of #$number, as gh says above"
  done
  for pair in $(jq -r '.add[] | "\(.number):\(.id)"' "$work/adopt.json"); do
    gh api -X POST "repos/$repo/issues/$number/sub_issues" -F sub_issue_id="${pair#*:}" </dev/null >/dev/null \
      || die "cannot add #${pair%%:*} to the sub-issues of #$number, as gh says above"
  done
  jq -r --argjson limit "$limit" '# The issues a line names: each, or past three, how many.
    def names: if length > 3 then "\(length) issues" else map(.name) | join(", ") end;
    [(if .add != [] then "sub-issues added: \(.add | names)" else empty end),
     (if .remove != [] then "sub-issues removed: \(.remove | names)" else empty end),
     (if .full != [] then "\(.full | names) not added: GitHub allows \($limit) sub-issues" else empty end),
     (.others[] | "\(.name) left under its parent \(.parent)")] | map("; " + .) | join("")' "$work/adopt.json"
}

# 3. Each plan issue's table, and with --update, the table written into it and its sub-issues kept
#    in step, on one line. Sub-issues that cannot be read or written leave the other plans to be
#    written, and the run exits 1 at its end.
first=true failed=false
while IFS= read -r plan; do
  $first || echo
  first=false
  if [ "$(jq -r .milestone <<<"$plan")" = null ]; then
    echo "plan: #$(jq -r .number <<<"$plan") is a plan issue with no milestone, so it has no table"
    continue
  fi
  text="$(table "$plan")" || exit 1
  echo "$text"
  if $update; then
    written="$(rewrite "$plan" "$text")" || exit 1
    related="$(adopt "$plan")" || failed=true
    echo "plan: #$(jq -r .number <<<"$plan") $written$related"
  fi
done < "$work/plans.jsonl"
! $failed || exit 1
