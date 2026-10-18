#!/usr/bin/env bash
# Check scripts/squad-plan.sh (agent-squad #370) against a stub gh that answers every call it makes
# from a world of files: the milestones, the milestone's issues with their parents and the PR that
# closed each, the open PRs with their reviews and CI, the repository's files, its tags and its
# Releases. Each table is compared whole. A milestone with nothing started, one half done, with a PR
# under review, one with changes requested and one approved, and one complete, in a project and in a
# repository that tracks SQUAD.md; the release's version PR open in each of its states, and the PRs
# that are not it (agent-squad #384); the plan issue rewritten between its markers, and left alone
# when only the time changed; the plan issue's sub-issues kept in step with its milestone
# (agent-squad #391); the same table and sub-issues with a jq that ends its lines with CRLF, as on
# Windows (agent-squad #405); no open milestone, and a milestone without a plan issue; a failed read
# or write; bad usage. Nothing reaches GitHub.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
plan="$root/scripts/squad-plan.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-plan.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }
# `check <description> <command...>` passes when the command does.
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}
# `same <expected file>` passes when the last run printed exactly that file, and shows the difference
# otherwise.
# shellcheck disable=SC2317,SC2329 # invoked through check
same() { diff "$1" <(printf '%s\n' "$out") >&2; }

# GitHub, as far as the script is concerned: the files of the world $W. Each call is logged to
# $CALLS, one line, with what it read on its input. A call whose words hold STUB_FAIL fails, as gh
# does when GitHub cannot be reached.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
# gh's own --jq ends its lines with LF on Windows too (go-gh's pkg/jq/jq.go), whatever jq does.
unset STUB_CRLF
printf '%s | input: %s\n' "$*" "$(cat)" >> "$CALLS"
if [ -n "${STUB_FAIL:-}" ] && [[ "$*" == *"$STUB_FAIL"* ]]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
case "$1 $2" in
  "repo view") echo o/r; exit 0 ;;
  "pr list") cat "$W/prs.json"; exit 0 ;;
  "issue edit")
    # gh issue edit <n> --body-file <file>: the issue's description becomes the file's.
    [ "$4" = --body-file ] || exit 1
    jq --argjson n "$3" --rawfile body "$5" 'map(if .number == $n then .body = $body else . end)' "$W/issues.json" > "$W/issues.new"
    mv "$W/issues.new" "$W/issues.json"
    exit 0 ;;
  "api "*) shift ;;
  *) exit 1 ;;
esac
filter="" slurp=false paginate=false endpoint="" milestone="" query="" method=GET sub=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) filter="$2"; shift 2 ;;
    --slurp) slurp=true; shift ;;
    --paginate) paginate=true; shift ;;
    -X) method="$2"; shift 2 ;;
    -F) case "$2" in milestone=*) milestone="${2#milestone=}" ;; sub_issue_id=*) sub="${2#sub_issue_id=}" ;; esac; shift 2 ;;
    -f) [[ "$2" != query=* ]] || query="${2#query=}"; shift 2 ;;
    -H) shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
case "$endpoint" in
  graphql)
    # The closed issues come by pages, as gh paginates a query that takes $endCursor.
    # shellcheck disable=SC2016 # GraphQL's variable, not the shell's
    $paginate && $slurp && [[ "$query" == *'after: $endCursor'* ]] || exit 1
    json="$(jq --argjson m "$milestone" '{data: {repository: {milestone: {issues: {nodes: [.[]
      | select(.milestone == $m and .state == "closed" and .pull_request == null)
      | {number, timelineItems: {nodes: (if .closer then [{closer: {number: .closer}}]
          elif .commit then [{closer: {associatedPullRequests: {nodes: [.commit | numbers | {number: .}]}}}] else [{}] end)}}]}}}}}' "$W/issues.json")" ;;
  "repos/o/r/issues?state=open&per_page=100")
    json="$(jq --slurpfile milestones "$W/milestones.json" '[.[] | select(.state == "open") | del(.closer) | . as $issue
      | del(.commit) | .milestone = ($milestones[0] | map(select(.number == $issue.milestone)) | first | if . then {number, title, html_url} else null end)]' \
      "$W/issues.json")" ;;
  "repos/o/r/issues?milestone="*"&state=all&per_page=100")
    milestone="${endpoint#repos/o/r/issues?milestone=}"
    json="$(jq --argjson m "${milestone%%&*}" 'map(select(.milestone == $m)
      | .parent_issue_url = (if .parent | type == "string" then .parent
          elif .parent then "https://api.github.com/repos/o/r/issues/\(.parent)" else null end)
      | del(.closer, .commit, .milestone, .parent))' "$W/issues.json")" ;;
  # The sub-issues (agent-squad #391): an issue's are those whose parent it is, of any repository.
  # Adding one that already has a parent fails, as GitHub refuses a second parent, and so does
  # adding a 101st, past GitHub's limit; removing one that is not there fails too. Both take the
  # sub-issue's id, not its number.
  "repos/o/r/issues/"*"/sub_issues?per_page=100")
    parent="${endpoint#repos/o/r/issues/}"
    json="$(jq --argjson p "${parent%%/*}" '[.[] | select(.parent == $p) | {number, id, state, title, repository_url}]' "$W/issues.json")" ;;
  repos/o/r/issues/*/sub_issues|repos/o/r/issues/*/sub_issue)
    # gh -F sends a value that is not a number as a string, which GitHub refuses (agent-squad #405).
    [[ "$sub" =~ ^[0-9]+$ ]] || { echo "Invalid property /sub_issue_id: \`\"$sub\"\` is not of type \`integer\`. (HTTP 422)" >&2; exit 1; }
    parent="${endpoint#repos/o/r/issues/}" parent="${parent%%/*}"
    case "$method:$endpoint" in
      POST:*/sub_issues) before=null after="$parent" ;;
      DELETE:*/sub_issue) before="$parent" after=null ;;
      *) exit 1 ;;
    esac
    jq -e --argjson id "$sub" --argjson before "$before" --argjson after "$after" \
      'any(.[]; .id == $id and .parent == $before) and ($after == null or ([.[] | select(.parent == $after)] | length) < 100)' "$W/issues.json" >/dev/null \
      || { echo "HTTP 422: Validation Failed" >&2; exit 1; }
    jq --argjson id "$sub" --argjson after "$after" 'map(if .id == $id then .parent = $after else . end)' "$W/issues.json" > "$W/issues.new"
    mv "$W/issues.new" "$W/issues.json"
    exit 0 ;;
  repos/o/r/pulls/*/reviews) json="$(cat "$W/reviews-$(basename "$(dirname "$endpoint")").json" 2>/dev/null || echo '[]')" ;;
  repos/o/r/contents) json="$(jq -R '{name: .}' "$W/files" | jq -s .)" ;;
  repos/o/r/contents/SQUAD.md) cat "$W/SQUAD.md"; exit 0 ;;
  repos/o/r/git/matching-refs/tags/v*) json="$(cat "$W/refs.json")" ;;
  "repos/o/r/releases?per_page=100") json="$(cat "$W/releases.json")" ;;
  *) exit 1 ;;
esac
! $slurp || json="[$json]"
if [ -n "$filter" ]; then jq -r "$filter" <<<"$json"; else printf '%s\n' "$json"; fi
GH
chmod +x "$lab/bin/gh"
# jq as on Windows (agent-squad #405), in the runs that `crlf <command...>` makes: every line it
# writes ends with CRLF. The stub gh, which uses jq for its own --jq, sets it aside.
mkdir -p "$lab/crlf"
printf '#!/usr/bin/env bash\n[ -n "${STUB_CRLF:-}" ] || exec %q "$@"\n%q "$@" | awk %q\nexit "${PIPESTATUS[0]}"\n' \
  "$(command -v jq)" "$(command -v jq)" '{ printf "%s\r\n", $0 }' > "$lab/crlf/jq"
chmod +x "$lab/crlf/jq"
crlf() { STUB_CRLF=1 PATH="$lab/crlf:$PATH" "$@"; }
export PATH="$lab/bin:$PATH" CALLS="$lab/calls" W="$lab/world" TZ=UTC

# The scratch checkout, where the squad is installed.
project="$lab/project"
git init -q "$project" && mkdir -p "$project/.agent-squad"
now=1791900000
time="$(jq -nr "$now | strftime(\"%Y-%m-%d %H:%M\")")"
# `run [args]` runs the script from the checkout at $now, with an input of its own, into out and
# code, after clearing the log.
run() {
  : > "$CALLS"
  out="$(cd "$project" && echo "the caller's input" | SQUAD_NOW="${at:-$now}" "$plan" "$@" 2>&1)"
  code=$?
}
# `edits` counts the issue edits of the last run, and `adoptions` its writes of sub-issues.
# shellcheck disable=SC2317,SC2329 # invoked through check
edits() { grep -c '^issue edit ' "$CALLS"; }
# shellcheck disable=SC2317,SC2329 # invoked through check
adoptions() { grep -c -E '^api -X (POST|DELETE) ' "$CALLS"; }

# The world. `world` starts one: two milestones, v55 and a phase whose title names no version, with
# no issue, no PR, a project's files and no tag or Release.
world() {
  rm -rf "$W" && mkdir -p "$W"
  jq -n '[{number: 40, title: "v55 — the labels", html_url: "https://github.com/o/r/milestone/40"},
          {number: 42, title: "Phase 2", html_url: "https://github.com/o/r/milestone/42"}]' > "$W/milestones.json"
  echo '[]' > "$W/issues.json" && echo '[]' > "$W/prs.json" && echo '[]' > "$W/refs.json" && echo '[]' > "$W/releases.json"
  printf 'README.md\n' > "$W/files"
  : > "$project/.agent-squad/install.log"
}
# `issue <number> <open|closed> <title> [<label>...]` adds an issue of milestone $M, v55's unless
# M says otherwise ("null" for none), with no parent. Its id is not its number, as on GitHub.
issue() {
  jq --argjson n "$1" --arg state "$2" --arg title "$3" --argjson m "${M:-40}" '. + [{number: $n, id: (9000 + $n), state: $state,
      title: $title, body: "", milestone: $m, parent: null, labels: [$ARGS.positional[] | {name: .}],
      html_url: "https://github.com/o/r/issues/\($n)", url: "https://api.github.com/repos/o/r/issues/\($n)",
      repository_url: "https://api.github.com/repos/o/r"}]' \
    "$W/issues.json" --args "${@:4}" > "$W/new"
  mv "$W/new" "$W/issues.json"
}
# `plan_issue <number> [<label>...]` adds the milestone's plan issue, its markers in its description.
plan_issue() {
  issue "$1" open "The plan" "👷🏼‍♂️ owner:cto" "${@:2}"
  set_issue "$1" '.body = $plan' --arg plan "$PLAN_BODY"
}
# `set_issue <number> <jq update> [<jq option>...]` changes an issue: its closer, the PR that closed
# it, its labels or its description.
set_issue() {
  local number="$1" change="$2"
  shift 2
  jq --argjson n "$number" "$@" "map(if .number == \$n then $change else . end)" "$W/issues.json" > "$W/new" && mv "$W/new" "$W/issues.json"
}
# `open_pr <number> <description> <issue GitHub links to it, or ""> <head> <ci: pass, fail, pending or
# none> [draft] [<reviewer requested>]` adds an open PR.
open_pr() {
  jq --argjson n "$1" --arg body "$2" --arg linked "$3" --arg head "$4" --arg ci "$5" --arg draft "${6:-}" --arg requested "${7:-}" \
    '. + [{number: $n, isDraft: ($draft == "draft"), headRefOid: $head, body: $body,
      closingIssuesReferences: [$linked | select(. != "") | {number: tonumber}],
      reviewRequests: (if $requested == "" then [] else [{login: $requested}] end),
      statusCheckRollup: {pass: [{__typename: "CheckRun", status: "COMPLETED", conclusion: "SUCCESS"}, {__typename: "StatusContext", state: "SUCCESS"}],
        fail: [{__typename: "CheckRun", status: "COMPLETED", conclusion: "SUCCESS"}, {__typename: "CheckRun", status: "COMPLETED", conclusion: "FAILURE"}],
        pending: [{__typename: "CheckRun", status: "IN_PROGRESS", conclusion: ""}], none: []}[$ci]}]' "$W/prs.json" > "$W/new"
  mv "$W/new" "$W/prs.json"
}
# `pr <number> <issue it closes> <head> <ci> [draft] [<reviewer requested>]` adds an open PR signed by
# DEV that closes the issue.
pr() { open_pr "$1" "**👨🏼‍💻[DEV]:** Closes #$2." "$2" "${@:3}"; }
# `review <pr> <commit> <verdict>` adds QA's review of a commit to a PR, by the repository's owner.
review() {
  [ -f "$W/reviews-$1.json" ] || echo '[]' > "$W/reviews-$1.json"
  jq --arg commit "$2" --arg verdict "$3" '. + [{commit_id: $commit, author_association: "OWNER", body: "**👩🏼‍🔬[QA]:** review\n\nQA-VERDICT: \($verdict)"}]' \
    "$W/reviews-$1.json" > "$W/new" && mv "$W/new" "$W/reviews-$1.json"
}
# `upstream <version>` makes the repository track SQUAD.md at that version, as the method's does.
upstream() {
  printf 'README.md\nSQUAD.md\n' > "$W/files"
  printf '# Squad Charter\n\n> **Version:** %s (2026-10-13). **Home:** the agent-squad repository.\n' "$1" > "$W/SQUAD.md"
}
PLAN_BODY=$'The plan of v55.\n\n<!-- squad-plan:start -->\nnothing yet\n<!-- squad-plan:end -->\n\nThe CEO reads the README here.'

# 1. No open plan issue: an open issue with one marker only, one that quotes both inline, as an
#    issue describing the plan does, one with both in the wrong order, one with either marker inline
#    and the other on a line of its own, a closed one with both, and a PR whose description holds
#    both are none. One line, exit 0, nothing read past the open issues, and
#    nothing written, with --update too.
world
issue 1 open "One marker" && set_issue 1 '.body = "<!-- squad-plan:start -->\nonly"'
issue 4 open "Quotes the markers" && set_issue 4 '.body = "Its table goes between `<!-- squad-plan:start -->` and `<!-- squad-plan:end -->`."'
issue 5 open "The markers in the wrong order" && set_issue 5 '.body = "<!-- squad-plan:end -->\n<!-- squad-plan:start -->"'
issue 6 open "The start inline" && set_issue 6 '.body = "From `<!-- squad-plan:start -->`\n<!-- squad-plan:end -->"'
issue 7 open "The end inline" && set_issue 7 '.body = "<!-- squad-plan:start -->\nup to <!-- squad-plan:end -->"'
plan_issue 2 && set_issue 2 '.state = "closed"'
plan_issue 3 && set_issue 3 '.pull_request = {}'
for args in "" --update; do
  # shellcheck disable=SC2086 # the argument is split on purpose
  run $args
  check "no open plan issue${args:+, with $args}: one line, exit 0, nothing read past the open issues" \
    bash -c '[ "$1" -eq 0 ] && [ "$2" = "plan: no open issue is a plan issue, whose description holds <!-- squad-plan:start --> and <!-- squad-plan:end -->; no release is in progress" ] && [ "$(wc -l < "$3")" -eq 2 ]' \
    _ "$code" "$out" "$CALLS"
done

# 2. Nothing started, in a project: rows by priority then number, a long title cut at a word, a pipe
#    kept out of the table, an issue without an owner, an issue that only quotes the markers, which
#    is a row like any other, and the README read waiting for the open issues, with the plan issue
#    left out of rows and counts.
world
issue 3 open "Third, a feature" "👨🏼‍💻 owner:dev" "🟡 P2"
issue 1 open "First, the most urgent" "👷🏼‍♂️ owner:cto" "🔴 P1"
issue 2 open "Second | with a pipe, and a title long enough to be cut at a word"
issue 4 open "Quotes the markers" "👨🏼‍💻 owner:dev" "🔵 P3"
set_issue 4 '.body = "Its table goes between `<!-- squad-plan:start -->` and `<!-- squad-plan:end -->`."'
plan_issue 10
run
cat > "$lab/expected" <<EOF
🗺️ **[v55 — the labels](https://github.com/o/r/milestone/40)** · 0 of 4 issues closed · updated $time

| | 📌 Step | 👤 Who | 🚦 State | ⏭️ Next |
|---|---|---|---|---|
| 1 | #1 First, the most urgent | CTO | ⚪ not started | CTO: start it |
| 2 | #3 Third, a feature | DEV | ⚪ not started | DEV: start it |
| 3 | #4 Quotes the markers | DEV | ⚪ not started | DEV: start it |
| 4 | #2 Second \| with a pipe, and a title long enough… | — | ⚪ not started | CTO: give it an owner |
| 5 | README read | CEO | ⚪ waits for 4 issues | — |
EOF
check "nothing started, in a project: the table as expected, exit 0" bash -c '[ "$1" -eq 0 ]' _ "$code"
check "the table is the one expected" same "$lab/expected"
check "gh reads no input of the caller's" bash -c '[ -s "$1" ] && ! grep -q "| input: ." "$1"' _ "$CALLS"
check "and a project's repository reads no SQUAD.md, tag or Release" bash -c '! grep -q "SQUAD.md\|matching-refs\|releases" "$1"' _ "$CALLS"

# 3. Half done, in a repository that tracks SQUAD.md: closed issues, with and without the PR that
#    closed them; PRs under review, with a verdict on an older commit, with changes requested,
#    approved, approved with a review requested on GitHub, and a draft, each with its CI; an issue
#    in progress, one blocked, one waiting for the CEO, and one in review with no open PR. A PR in
#    the milestone's list and a PR that closes an issue outside it are no rows.
world && upstream 54 && plan_issue 10
issue 1 closed "Closed by its PR" "👨🏼‍💻 owner:dev" "🟡 P2" && set_issue 1 '.closer = 11'
issue 2 closed "Closed by hand" "👷🏼‍♂️ owner:cto" "🟡 P2"
issue 22 closed "Closed by its PR's squash commit" "👨🏼‍💻 owner:dev" "🟡 P2" && set_issue 22 '.commit = 18'
issue 23 closed "Closed by a commit of no PR" "👨🏼‍💻 owner:dev" "🟡 P2" && set_issue 23 '.commit = "none"'
issue 3 open "Under review" "👨🏼‍💻 owner:dev" "🟡 P2" "👀 status:in-review"
issue 4 open "Changes requested" "👨🏼‍💻 owner:dev" "🟡 P2" "👀 status:in-review"
issue 5 open "Approved" "👨🏼‍💻 owner:dev" "🟡 P2" "👀 status:in-review"
issue 6 open "In progress" "👩🏼‍🔬 owner:qa" "🔵 P3" "🚧 status:in-progress"
issue 7 open "Blocked" "👨🏼‍💻 owner:dev" "🔵 P3" "⛔ status:blocked"
issue 8 open "Waits for the CEO" "👨🏼‍💻 owner:dev" "🔵 P3" "👨🏻‍💼 needs-ceo"
issue 9 open "A draft" "👨🏼‍💻 owner:dev" "🔵 P3" "🚧 status:in-progress"
issue 20 open "Approved, a reviewer requested" "👨🏼‍💻 owner:dev" "🔵 P3" "👀 status:in-review"
issue 21 open "In review, no open PR" "👨🏼‍💻 owner:dev" "🔵 P3" "👀 status:in-review"
issue 30 open "A PR in the milestone" && set_issue 30 '.pull_request = {}'
pr 12 3 aaaaaaa1111 pass && review 12 old0000 APPROVED
pr 13 4 bbbbbbb2222 fail && review 13 bbbbbbb2222 CHANGES-REQUESTED
pr 14 5 ccccccc3333 pending && review 14 ccccccc3333 APPROVED
pr 15 9 ddddddd4444 none draft
pr 16 99 eeeeeee5555 pass
pr 17 20 fffffff6666 pass "" alice && review 17 fffffff6666 APPROVED
run
cat > "$lab/expected" <<EOF
🗺️ **[v55 — the labels](https://github.com/o/r/milestone/40)** · 4 of 13 issues closed · updated $time

| | 📌 Step | 👤 Who | 🚦 State | ⏭️ Next |
|---|---|---|---|---|
| 1 | #1 Closed by its PR | DEV | ✅ closed by PR #11 | — |
| 2 | #2 Closed by hand | CTO | ✅ closed | — |
| 3 | #3 Under review | DEV | 👀 PR #12 in review (\`aaaaaaa\`), CI ✅ | QA: review |
| 4 | #4 Changes requested | DEV | 👀 PR #13 changes requested (\`bbbbbbb\`), CI ❌ | DEV: answer the review |
| 5 | #5 Approved | DEV | 👀 PR #14 approved (\`ccccccc\`), CI ⏳ | DEV: merge |
| 6 | #22 Closed by its PR's squash commit | DEV | ✅ closed by PR #18 | — |
| 7 | #23 Closed by a commit of no PR | DEV | ✅ closed | — |
| 8 | #6 In progress | QA | 🚧 in progress | QA: carry on |
| 9 | #7 Blocked | DEV | ⛔ blocked | DEV: unblock it |
| 10 | #8 Waits for the CEO | DEV | 👨🏻‍💼 waits for the CEO | CEO: decide |
| 11 | #9 A draft | DEV | 👀 PR #15 draft (\`ddddddd\`), no CI | DEV: finish the draft |
| 12 | #20 Approved, a reviewer requested | DEV | 👀 PR #17 approved (\`fffffff\`), CI ✅ | wait for alice |
| 13 | #21 In review, no open PR | DEV | 👀 in review, no open PR | DEV: carry on |
| 14 | Version PR | CTO | ⚪ waits for 9 issues | — |
| 15 | README read | CEO | ⚪ waits for the version PR | — |
| 16 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |
EOF
check "half done, upstream: exit 0" bash -c '[ "$1" -eq 0 ]' _ "$code"
check "the table is the one expected" same "$lab/expected"
check "a draft's reviews are not read" bash -c '! grep -q "pulls/15/reviews" "$1" && grep -q "pulls/12/reviews" "$1"' _ "$CALLS"
#    With a jq that ends its lines with CRLF, as on Windows, the table is the same (agent-squad #405).
crlf run
check "with a jq that ends its lines with CRLF: exit 0, and the same table" \
  bash -c '[ "$1" -eq 0 ] && diff "$2" <(printf "%s\n" "$3") >&2' _ "$code" "$lab/expected" "$out"

# 4. The release's own steps, step by step, upstream: every issue closed, the version PR not yet
#    merged, then merged, then the README asked, then the tag, the Release and the install.
world && upstream 54
issue 1 closed "Done" "👨🏼‍💻 owner:dev" && set_issue 1 '.closer = 11'
plan_issue 10
# `steps` prints the release's own rows of the last run.
steps() { grep -E '^\| [0-9]+ \| (Version PR|README read|Tag, Release, install here) \|' <<<"$out"; }
expect_steps() {
  run
  check "$1" bash -c '[ "$1" = "$2" ]' _ "$(steps)" "$2"
}
expect_steps "every issue closed, the version PR not merged: the CTO opens it" \
"| 2 | Version PR | CTO | ⚪ not started | CTO: open it |
| 3 | README read | CEO | ⚪ waits for the version PR | — |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |"
upstream 55
expect_steps "the version PR merged: the CTO asks the CEO" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |"
set_issue 10 '.labels += [{name: "👨🏻‍💼 needs-ceo"}]'
expect_steps "the plan issue labelled needs-ceo: the README read waits for the CEO" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ⏳ waits for the CEO | CEO: read it |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |"
set_issue 10 '.labels = []'
echo '[{"ref": "refs/tags/v550"}]' > "$W/refs.json"
expect_steps "a tag whose name only starts the same is not the release's" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |"
echo '[{"ref": "refs/tags/v55"}, {"ref": "refs/tags/v550"}]' > "$W/refs.json"
expect_steps "tagged: the README read is done, and the CTO publishes the Release" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ✅ done | — |
| 4 | Tag, Release, install here | CTO | ⏳ tag ✅, Release ⚪, install ⚪ | CTO: publish the Release |"
echo '[{"tag_name": "v54"}, {"tag_name": "v55"}]' > "$W/releases.json"
printf '2026-10-13 18:00 v54 -> v55\n2026-10-13 18:05 v55 -> v54\n' > "$project/.agent-squad/install.log"
expect_steps "published, and installed here earlier but not last: the CTO installs it" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ✅ done | — |
| 4 | Tag, Release, install here | CTO | ⏳ tag ✅, Release ✅, install ⚪ | CTO: install it here |"
printf '2026-10-13 18:10 v54 -> v55\n' >> "$project/.agent-squad/install.log"
expect_steps "installed here: every step done" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ✅ done | — |
| 4 | Tag, Release, install here | CTO | ✅ done | — |"
check "with the header counting the issues closed, the plan issue left out" \
  bash -c '[[ "$(head -1 <<<"$1")" == *" · 1 of 1 issues closed · "* ]]' _ "$out"

# 4b. A release that takes no README read (agent-squad #429): the line of the plan issue's
#     description that says so, outside its markers, is its README row, before the tag and after it,
#     and the CTO tags the release once its version PR is merged.
world && upstream 54
issue 1 closed "Done" "👨🏼‍💻 owner:dev" && set_issue 1 '.closer = 11'
plan_issue 10
# `plan_body <text before the markers>` writes the plan issue's description, the table after it.
plan_body() { set_issue 10 '.body = $body' --arg body "$1"$'\n\n<!-- squad-plan:start -->\nnothing yet\n<!-- squad-plan:end -->'; }
plan_body $'The plan of v55.\n\nNo README read: it only fixes things'
expect_steps "no README read, the version PR not merged: the row says so, and the tag waits for the version PR" \
"| 2 | Version PR | CTO | ⚪ not started | CTO: open it |
| 3 | README read | CEO | ➖ not taken: it only fixes things | — |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the version PR | — |"
upstream 55
expect_steps "the version PR merged: the CTO tags it, asking the CEO nothing" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ➖ not taken: it only fixes things | — |
| 4 | Tag, Release, install here | CTO | ⚪ not tagged yet | CTO: tag it |"
echo '[{"ref": "refs/tags/v55"}]' > "$W/refs.json"
expect_steps "tagged: the row still says that no read was taken" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ➖ not taken: it only fixes things | — |
| 4 | Tag, Release, install here | CTO | ⏳ tag ✅, Release ⚪, install ⚪ | CTO: publish the Release |"
echo '[]' > "$W/refs.json"
#     The line counts only at the start of a line, with a reason, and outside the markers: the table
#     between them is rewritten at every update.
for text in $'Note: No README read: it only fixes things' 'No README read:' $'No README read:   '; do
  plan_body "$text"
  expect_steps "'$text' is no such line: the CTO asks the CEO" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |"
done
set_issue 10 '.body = $body' --arg body $'The plan.\n\n<!-- squad-plan:start -->\nNo README read: it only fixes things\n<!-- squad-plan:end -->'
expect_steps "nor is the line between the markers" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |"
#     After the markers, and with the reason's pipe kept out of the table's cells, it counts too.
set_issue 10 '.body = $body' --arg body $'The plan.\n\n<!-- squad-plan:start -->\nnothing yet\n<!-- squad-plan:end -->\nNo README read: a fix | no rule'
expect_steps "after the markers too, its pipe escaped" \
"| 2 | Version PR | CTO | ✅ done | — |
| 3 | README read | CEO | ➖ not taken: a fix \\| no rule | — |
| 4 | Tag, Release, install here | CTO | ⚪ not tagged yet | CTO: tag it |"

# 5. The release's version PR (agent-squad #384), upstream: the open PR whose description names the
#    plan issue ("Part of #10") and that closes no issue. None of these is it, each numbered above
#    it so that the highest-numbered would be one of them: a PR that names the plan issue and closes
#    an issue of the milestone, which is that issue's PR; one that names it and that GitHub links to
#    an issue outside the milestone, which its description does not name; one that names #100; and
#    one that names another issue. Then the version PR in review, with changes requested, approved,
#    and a second one above it, whose description says "part of"; once SQUAD.md has the milestone's
#    version, done while one is still open; and a draft while an issue is still open.
world && upstream 54 && plan_issue 10
issue 1 closed "Done" "👨🏼‍💻 owner:dev" && set_issue 1 '.closer = 11'
issue 2 open "Second" "👨🏼‍💻 owner:dev" "👀 status:in-review"
open_pr 30 "**👨🏼‍💻[DEV]:** Closes #2, part of #10." 2 bbbbbbb2222 pass
open_pr 31 "**👨🏼‍💻[DEV]:** Part of #10." 99 ccccccc3333 pass
open_pr 32 "**👷🏼‍♂️[CTO]:** Part of #100." "" ddddddd4444 pass
open_pr 33 "**👷🏼‍♂️[CTO]:** Part of #2." "" eeeeeee5555 pass
run
cat > "$lab/expected" <<EOF
🗺️ **[v55 — the labels](https://github.com/o/r/milestone/40)** · 1 of 2 issues closed · updated $time

| | 📌 Step | 👤 Who | 🚦 State | ⏭️ Next |
|---|---|---|---|---|
| 1 | #1 Done | DEV | ✅ closed by PR #11 | — |
| 2 | #2 Second | DEV | 👀 PR #30 in review (\`bbbbbbb\`), CI ✅ | QA: review |
| 3 | Version PR | CTO | ⚪ waits for #2 | — |
| 4 | README read | CEO | ⚪ waits for the version PR | — |
| 5 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |
EOF
check "PRs that name the plan issue or another, none the version PR: exit 0" bash -c '[ "$1" -eq 0 ]' _ "$code"
check "the table is the one expected, the PR that closes #2 on its row" same "$lab/expected"
check "the reviews of the issue's PR are read, and those of the others not" \
  bash -c 'grep -q "pulls/30/reviews" "$1" && ! grep -q "pulls/3[123]/reviews" "$1"' _ "$CALLS"
# `expect_version <description> <row>` runs the script and checks its Version PR row.
expect_version() {
  run
  check "$1" bash -c '[ "$1" = "$2" ]' _ "$(grep -F '| Version PR |' <<<"$out")" "$2"
}
set_issue 2 '.state = "closed" | .closer = 30'
expect_version "every issue closed, none of those PRs the version PR: the CTO opens it" \
  "| 3 | Version PR | CTO | ⚪ not started | CTO: open it |"
open_pr 20 "**👷🏼‍♂️[CTO]:** Part of #10." "" aaaaaaa1111 pending
expect_version "the version PR open, no verdict: QA reviews it" \
  "| 3 | Version PR | CTO | 👀 PR #20 in review (\`aaaaaaa\`), CI ⏳ | QA: review |"
review 20 aaaaaaa1111 CHANGES-REQUESTED
expect_version "changes requested on its head: its author answers" \
  "| 3 | Version PR | CTO | 👀 PR #20 changes requested (\`aaaaaaa\`), CI ⏳ | CTO: answer the review |"
review 20 aaaaaaa1111 APPROVED
expect_version "approved: its author merges it" \
  "| 3 | Version PR | CTO | 👀 PR #20 approved (\`aaaaaaa\`), CI ⏳ | CTO: merge |"
open_pr 21 "**👷🏼‍♂️[CTO]:** v55, part of #10." "" fffffff6666 pass
expect_version "two version PRs: the highest-numbered, whatever the case of its words" \
  "| 3 | Version PR | CTO | 👀 PR #21 in review (\`fffffff\`), CI ✅ | QA: review |"
upstream 55
expect_version "SQUAD.md at the milestone's version, a version PR still open: done" \
  "| 3 | Version PR | CTO | ✅ done | — |"
world && upstream 54 && plan_issue 10
issue 2 open "Second" "👨🏼‍💻 owner:dev"
open_pr 20 "**👷🏼‍♂️[CTO]:** Part of #10." "" aaaaaaa1111 none draft
expect_version "a draft version PR while an issue is still open: the row shows the draft" \
  "| 2 | Version PR | CTO | 👀 PR #20 draft (\`aaaaaaa\`), no CI | CTO: finish the draft |"
check "whose reviews are not read" bash -c '! grep -q "pulls/20/reviews" "$1"' _ "$CALLS"

# 6. A project's README read, every issue closed: not asked yet, then waiting for the CEO.
world
issue 1 closed "Done" "👨🏼‍💻 owner:dev"
plan_issue 10
expect_steps "a project, every issue closed: the CTO asks the CEO" "| 2 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |"
set_issue 10 '.labels += [{name: "👨🏻‍💼 needs-ceo"}]'
expect_steps "a project, the plan issue labelled needs-ceo: the CEO reads it" "| 2 | README read | CEO | ⏳ waits for the CEO | CEO: read it |"
set_issue 10 '.labels = []' && plan_body $'The plan.\nNo README read: it only fixes things'
expect_steps "a project's release that takes no README read says so (agent-squad #429)" "| 2 | README read | CEO | ➖ not taken: it only fixes things | — |"

# 7. --update: the table between the markers, the text around them kept; then nothing written
#    while only the time changes, and written again when the table does.
world
issue 1 open "First" "👨🏼‍💻 owner:dev"
plan_issue 10
run
table="$out"
run --update
check "--update writes the plan issue once, saying so, and makes the milestone's issue its sub-issue" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" -eq 1 ] && [ "$(tail -1 <<<"$3")" = "plan: #10 updated; sub-issues added: #1" ]' _ "$code" "$(edits)" "$out"
check "with the table between its markers, and the text around them as it was" \
  bash -c '[ "$1" = "The plan of v55."$'\''\n\n'\''"<!-- squad-plan:start -->"$'\''\n'\''"$2"$'\''\n'\''"<!-- squad-plan:end -->"$'\''\n\n'\''"The CEO reads the README here." ]' \
  _ "$(jq -r '.[] | select(.number == 10) | .body' "$W/issues.json")" "$table"
run --update
check "run again, it writes nothing, and says so" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" -eq 0 ] && [ "$(tail -1 <<<"$3")" = "plan: #10 unchanged" ]' _ "$code" "$(edits)" "$out"
at=$((now + 3600)) run --update
check "an hour later, with only the time changed, it writes nothing" \
  bash -c '[ "$1" -eq 0 ] && [ "$(tail -1 <<<"$2")" = "plan: #10 unchanged" ]' _ "$(edits)" "$out"
set_issue 10 '.body |= gsub("\n"; "\r\n")'
run --update
check "a description saved with CRLF line ends, as the web page saves it, is no change either" \
  bash -c '[ "$1" -eq 0 ] && [ "$(tail -1 <<<"$2")" = "plan: #10 unchanged" ]' _ "$(edits)" "$out"
set_issue 10 '.body = "<!-- squad-plan:start -->\n<!-- squad-plan:end -->"'
run --update
check "a description that holds its markers alone, nothing between them: the table goes between" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "<!-- squad-plan:start -->"$'\''\n'\''"$3"$'\''\n'\''"<!-- squad-plan:end -->" ]' \
  _ "$(edits)" "$(jq -r '.[] | select(.number == 10) | .body' "$W/issues.json")" "$table"
set_issue 1 '.labels += [{name: "🚧 status:in-progress"}]'
run --update
check "a state changed: it writes again" \
  bash -c '[ "$1" -eq 1 ] && [ "$(tail -1 <<<"$2")" = "plan: #10 updated" ] && grep -qF "| 1 | #1 First | DEV | 🚧 in progress | DEV: carry on |" <<<"$2"' _ "$(edits)" "$out"
run
check "and a run without --update writes nothing" bash -c '[ "$1" -eq 0 ] && ! grep -q "^plan: " <<<"$2"' _ "$(edits)" "$out"

# 8. Two plan issues, in a repository that tracks SQUAD.md: v55's, with the release's own steps, and a
#    phase's, whose milestone names no version, with the README read alone. Each gets its own
#    milestone's table, in the order of their numbers, a blank line between them, and is written
#    with it, its milestone's issue made its sub-issue. A plan issue with no milestone gets one
#    line, and nothing written.
world && upstream 54
issue 1 open "First" "👨🏼‍💻 owner:dev" && plan_issue 10
M=42 issue 2 closed "Done in phase 2" "👨🏼‍💻 owner:dev" && M=42 plan_issue 5
M=null plan_issue 3
run --update
cat > "$lab/expected" <<EOF
plan: #3 is a plan issue with no milestone, so it has no table

🗺️ **[Phase 2](https://github.com/o/r/milestone/42)** · 1 of 1 issues closed · updated $time

| | 📌 Step | 👤 Who | 🚦 State | ⏭️ Next |
|---|---|---|---|---|
| 1 | #2 Done in phase 2 | DEV | ✅ closed | — |
| 2 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |
plan: #5 updated; sub-issues added: #2

🗺️ **[v55 — the labels](https://github.com/o/r/milestone/40)** · 0 of 1 issues closed · updated $time

| | 📌 Step | 👤 Who | 🚦 State | ⏭️ Next |
|---|---|---|---|---|
| 1 | #1 First | DEV | ⚪ not started | DEV: start it |
| 2 | Version PR | CTO | ⚪ waits for #1 | — |
| 3 | README read | CEO | ⚪ waits for the version PR | — |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |
plan: #10 updated; sub-issues added: #1
EOF
check "two plan issues and one with no milestone: exit 0, two edits" bash -c '[ "$1" -eq 0 ] && [ "$2" -eq 2 ]' _ "$code" "$(edits)"
check "each plan issue with its own milestone's table, in order" same "$lab/expected"
check "each written with its own" \
  bash -c 'grep -qF "[Phase 2]" <<<"$1" && ! grep -qF "[v55" <<<"$1" && grep -qF "[v55" <<<"$2"' \
  _ "$(jq -r '.[] | select(.number == 5) | .body' "$W/issues.json")" "$(jq -r '.[] | select(.number == 10) | .body' "$W/issues.json")"

# 9. GitHub that cannot be read or written: exit 1, with gh's message and what failed.
world && upstream 55 && issue 1 open "First" && pr 12 1 aaaaaaa1111 pass
plan_issue 10
while IFS='|' read -r failing message; do
  STUB_FAIL="$failing" run --update
  check "$failing failing: exit 1, $message" \
    bash -c '[ "$1" -eq 1 ] && grep -qxF "HTTP 502: Bad Gateway" <<<"$2" && [ "$(tail -1 <<<"$2")" = "plan: $3" ]' _ "$code" "$out" "$message"
done <<'CASES'
repo view|cannot read the repository, as gh says above
state=open|cannot read the open issues, as gh says above
state=all|cannot read the issues of the milestone, as gh says above
graphql|cannot read the PRs that closed the milestone's issues, as gh says above
pr list|cannot read the open pull requests, as gh says above
pulls/12/reviews|cannot read the reviews of PR #12, as gh says above
repos/o/r/contents --jq|cannot read the repository's files, as gh says above
contents/SQUAD.md|cannot read SQUAD.md, as gh says above
matching-refs|cannot read the tags, as gh says above
releases|cannot read the Releases, as gh says above
issue edit|cannot write the plan issue #10, as gh says above
CASES
#    Sub-issues that cannot be read, added or removed stop no other plan (QA's finding on PR #393):
#    the later plan, #12, still gets its table, and the run exits 1 at its end. #2, a sub-issue of
#    #10 that left its milestone, is to be removed, and #1 added.
while IFS='|' read -r failing message; do
  world && issue 1 open "First" && M=42 issue 2 open "Moved away" && set_issue 2 '.parent = 10'
  plan_issue 10 && M=42 plan_issue 12
  STUB_FAIL="$failing" run --update
  check "$failing failing: exit 1, $message, and the later plan still written" \
    bash -c '[ "$1" -eq 1 ] && grep -qxF "HTTP 502: Bad Gateway" <<<"$2" && grep -qxF "plan: $3" <<<"$2" && grep -q "^plan: #12 updated" <<<"$2" \
      && grep -qF "[Phase 2]" <<<"$4"' _ "$code" "$out" "$message" "$(jq -r '.[] | select(.number == 12) | .body' "$W/issues.json")"
done <<'CASES'
sub_issues?per_page|cannot read the sub-issues of #10, as gh says above
-X POST|cannot add #1 to the sub-issues of #10, as gh says above
-X DELETE|cannot remove #2 from the sub-issues of #10, as gh says above
CASES

# 10. Bad usage, and a checkout without the squad: exit 2, before anything reaches GitHub.
for args in "--updat" "--update --update" "update"; do
  # shellcheck disable=SC2086 # the arguments are split on purpose
  run $args
  check "'$args' is bad usage: exit 2, and nothing sent" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "usage: squad-plan.sh [--update]" ] && [ ! -s "$3" ]' _ "$code" "$out" "$CALLS"
done
mkdir -p "$lab/bare" && git init -q "$lab/plain"
for dir in "$lab/bare" "$lab/plain"; do
  : > "$CALLS"
  out="$(cd "$dir" && "$plan" 2>&1)"
  code=$?
  check "from ${dir#"$lab/"}, no checkout the squad is installed in: exit 2, and nothing sent" \
    bash -c '[ "$1" -eq 2 ] && [[ "$2" == "plan: "* ]] && [ ! -s "$3" ]' _ "$code" "$out" "$CALLS"
done

# 11. The plan issue's sub-issues are its milestone's issues, open and closed (agent-squad #391).
#     Without --update, nothing about them is read or written. With it, an open and a closed issue of
#     the milestone become sub-issues, and a sub-issue that left the milestone is removed, each by
#     its id, which is not its number. An issue with another parent stays under it, and the line
#     says so. The plan issue, and an older plan issue of the milestone, closed, are never sub-issues.
#     The table's rows are still the milestone's. Run again, nothing is written.
# `sub_world` starts that world.
sub_world() {
  world
  plan_issue 10
  issue 1 open "Open" "👨🏼‍💻 owner:dev"
  issue 2 closed "Closed" "👨🏼‍💻 owner:dev"
  issue 3 open "Under another parent" "👨🏼‍💻 owner:dev" && set_issue 3 '.parent = 50'
  M=42 issue 4 open "Left the milestone" && set_issue 4 '.parent = 10'
  issue 5 open "Already a sub-issue" "👨🏼‍💻 owner:dev" && set_issue 5 '.parent = 10'
  plan_issue 9 && set_issue 9 '.state = "closed"'
}
sub_world
# `parents` prints each issue's number and parent, the parentless ones as "-".
parents() { jq -r 'sort_by(.number)[] | "\(.number):\(.parent // "-")"' "$W/issues.json" | tr '\n' ' '; }
run
check "without --update, no sub-issue is read or written, and no plan line is printed" \
  bash -c '[ "$1" -eq 0 ] && ! grep -q "sub_issue" "$2" && ! grep -q "^plan: " <<<"$3"' _ "$code" "$CALLS" "$out"
run --update
check "--update adds the open and the closed issue, removes the one that left, and leaves the one under another parent, saying each" \
  bash -c '[ "$1" -eq 0 ] && [ "$(tail -1 <<<"$2")" = "plan: #10 updated; sub-issues added: #1, #2; sub-issues removed: #4; #3 left under its parent #50" ] && [ "$3" -eq 3 ]' \
  _ "$code" "$out" "$(adoptions)"
check "the parents are then the milestone's, the plan issues none" \
  bash -c '[ "$1" = "1:10 2:10 3:50 4:- 5:10 9:- 10:- " ]' _ "$(parents)"
check "and the table's rows are still the milestone's issues" \
  bash -c '[ "$(grep -oE "^\| [0-9]+ \| #[0-9]+" <<<"$1" | sed "s/.*#//" | tr "\n" " ")" = "1 2 3 5 " ]' _ "$out"
run --update
check "run again: nothing written, and the line says only what stays under another parent" \
  bash -c '[ "$1" -eq 0 ] && [ "$(tail -1 <<<"$2")" = "plan: #10 unchanged; #3 left under its parent #50" ] && [ "$3" -eq 0 ] && [ "$4" -eq 0 ]' \
  _ "$code" "$out" "$(adoptions)" "$(edits)"
#     With a jq that ends its lines with CRLF, as on Windows, the same sub-issues are added and
#     removed, and the description written holds no CR: GitHub refused each id that came with its CR
#     (agent-squad #405).
sub_world
crlf run --update
check "with a jq that ends its lines with CRLF: the same sub-issues added and removed, and no CR written" \
  bash -c '[ "$1" -eq 0 ] && [ "$(tail -1 <<<"$2")" = "plan: #10 updated; sub-issues added: #1, #2; sub-issues removed: #4; #3 left under its parent #50" ] \
    && [ "$3" = "1:10 2:10 3:50 4:- 5:10 9:- 10:- " ] && [ "$4" -eq 0 ]' \
  _ "$code" "$out" "$(parents)" "$(jq -r '.[] | select(.number == 10) | .body' "$W/issues.json" | tr -cd '\r' | wc -c)"

#     GitHub allows 100 sub-issues per issue (QA's finding on PR #393): a milestone of 102 closed
#     issues gets its first 100, the line names the two left out, and the exit status stays 0. The
#     later plan still gets its table and its sub-issue. Run again, nothing is written.
world
M=42 plan_issue 5
jq '. + [range(100; 202) | {number: ., id: (9000 + .), state: "closed", title: "Old \(.)", body: "", milestone: 42,
  parent: null, labels: [], html_url: "https://github.com/o/r/issues/\(.)", url: "https://api.github.com/repos/o/r/issues/\(.)",
  repository_url: "https://api.github.com/repos/o/r"}]' "$W/issues.json" > "$W/new" && mv "$W/new" "$W/issues.json"
issue 1 open "First" && plan_issue 10
run --update
check "past GitHub's 100 sub-issues, the rest are named on the line, exit 0, and the later plan is written" \
  bash -c '[ "$1" -eq 0 ] && grep -qxF "plan: #5 updated; sub-issues added: 100 issues; #200, #201 not added: GitHub allows 100 sub-issues" <<<"$2" \
    && grep -qxF "plan: #10 updated; sub-issues added: #1" <<<"$2" && [ "$3" -eq 100 ]' \
  _ "$code" "$out" "$(jq '[.[] | select(.parent == 5)] | length' "$W/issues.json")"
run --update
check "run again: nothing written, the two still named" \
  bash -c '[ "$1" -eq 0 ] && grep -qxF "plan: #5 unchanged; #200, #201 not added: GitHub allows 100 sub-issues" <<<"$2" && [ "$3" -eq 0 ]' \
  _ "$code" "$out" "$(adoptions)"
#     #100 leaves the milestone: it is removed before #200 is added, which makes room for it, at 100.
set_issue 100 '.milestone = null'
run --update
check "a sub-issue that left is removed first, which makes room for the next issue, at 100" \
  bash -c '[ "$1" -eq 0 ] && grep -qxF "plan: #5 updated; sub-issues added: #200; sub-issues removed: #100; #201 not added: GitHub allows 100 sub-issues" <<<"$2" && [ "$3" -eq 100 ]' \
  _ "$code" "$out" "$(jq '[.[] | select(.parent == 5)] | length' "$W/issues.json")"

#     Sub-issues are matched by id and parents by URL, since either may be another repository's
#     (QA's finding on PR #393): another repository's #1, a sub-issue of the plan, is removed and
#     named with its repository, and this repository's #1 is still added; #2, under another
#     repository's #10, is left there, not taken for the plan's child.
world
plan_issue 10
issue 1 open "Ours" && issue 2 open "Under another repository's #10"
set_issue 2 '.parent = "https://api.github.com/repos/other/r/issues/10"'
jq '. + [{number: 1, id: 7001, state: "open", title: "Theirs", body: "", milestone: null, parent: 10, labels: [],
  html_url: "https://github.com/other/r/issues/1", url: "https://api.github.com/repos/other/r/issues/1",
  repository_url: "https://api.github.com/repos/other/r"}]' "$W/issues.json" > "$W/new" && mv "$W/new" "$W/issues.json"
run --update
check "another repository's sub-issue and parent are told apart from this one's by id and URL" \
  bash -c '[ "$1" -eq 0 ] && [ "$(tail -1 <<<"$2")" = "plan: #10 updated; sub-issues added: #1; sub-issues removed: other/r#1; #2 left under its parent other/r#10" ]' \
  _ "$code" "$out"

exit "$status"
