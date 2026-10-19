# The squad's next steps, from GitHub alone (agent-squad #174, #370): who owns the next step of an
# open PR or of an issue in progress, and what that step is. squad-stalls.sh pings the owner of a
# step that has stalled, and squad-plan.sh shows each step in the plan of the release in progress;
# both include this module (`jq -L <scripts> 'include "squad-steps"; …'`), so that they never
# disagree. Each step is {owner, step, short}: the role that owns it ("requested" for a reviewer
# requested on GitHub, then named in `reviewers`), the sentence the stall watch prints, and the few
# words the plan's table shows.

# The issues a PR closes, as GitHub names them or as its description says ("Closes #N").
def closes: [(.closingIssuesReferences // [])[].number]
  + [.body // "" | scan("(?i)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?) #([0-9]+)") | .[0] | tonumber];

# The issues a PR closes on purpose, as the squad writes it: "Closes #N" (SQUAD.md §3). GitHub links
# a PR to an issue on other words too, such as "closed: #N" in a sentence, and its merge then closes
# that issue all the same: such an issue is a stray link (agent-squad #461).
def closes_on_purpose: [.body // "" | scan("\\bCloses #([0-9]+)") | .[0] | tonumber];
def stray_links: closes_on_purpose as $meant | [(.closingIssuesReferences // [])[].number | select(IN($meant[]) | not)];

# A PR's author: the role whose signature opens the first line of its description (SQUAD.md §6), in
# bold or not; null when none does.
def author: (.body // "" | split("\n") | first // "" | gsub("\\*\\*"; "")) as $line
  | first(("QA", "DEV", "CTO") as $role
      | select($line | startswith({QA: "👩🏼‍🔬", DEV: "👨🏼‍💻", CTO: "👷🏼‍♂️"}[$role] + "[\($role)]:")) | $role) // null;

# A PR's next step, given $verdicts, the latest verdict on each PR by the squad's accounts, by
# number: {commit, verdict}, or null. The reviewer reviews a head with no verdict on it; the author
# answers changes asked on the head, merges an approved head, and finishes a draft. Without an
# author, the CTO finds one. An approved head with a review still requested on GitHub, from a user
# or a team, waits for that reviewer instead, who is none of the squad's sessions.
def pr_step($verdicts):
  author as $author | (if $author == "QA" then "DEV" else "QA" end) as $reviewer
  | .headRefOid[0:7] as $head | $verdicts[.number | tostring] as $v
  | if $author == null then {owner: "CTO", step: "find its author: its description is not signed", short: "find its author"}
    elif .isDraft then {owner: $author, step: "finish the draft", short: "finish the draft"}
    elif $v == null or $v.commit != .headRefOid then {owner: $reviewer, step: "review its head \($head)", short: "review"}
    elif $v.verdict == "CHANGES-REQUESTED" then {owner: $author, step: "answer the changes requested on \($head)", short: "answer the review"}
    elif $v.verdict == "APPROVED" and (.reviewRequests // []) != [] then
      ([.reviewRequests[] | .login // .slug // .name] | join(", ")) as $who
      | {owner: "requested", reviewers: $who, step: "wait for the review requested from \($who) on GitHub, before the merge", short: "wait for \($who)"}
    elif $v.verdict == "APPROVED" then {owner: $author, step: "merge it: QA approved its head \($head)", short: "merge"}
    else {owner: $reviewer, step: "review its head \($head)", short: "review"} end;

# An issue's owner: the role its owner label names; null without one.
def owner: [.labels[].name | capture("owner:(?<role>cto|dev|qa)$").role | ascii_upcase] | first;

# An issue in progress: its owner carries on; without an owner label, the CTO gives it one.
def issue_step:
  owner as $owner
  | if $owner == null then {owner: "CTO", step: "give it an owner", short: "give it an owner"}
    else {owner: $owner, step: "carry on with it", short: "carry on"} end;

# A PR's latest verdict by the squad's accounts, from the pages of its reviews (`gh api --paginate
# --slurp …/reviews`): {commit, verdict}, or null with none. Only the reviews of the repository's
# owner, its organization's members and its collaborators count (SQUAD.md §4.9).
def latest_verdict: add // []
  | map(select((.author_association | IN("OWNER", "MEMBER", "COLLABORATOR")) and (.body | test("QA-VERDICT: "))))
  | last | if . == null then null
    else {commit: .commit_id, verdict: (.body | split("\n") | map(select(test("QA-VERDICT: "))) | last | sub(".*QA-VERDICT: "; ""))} end;
