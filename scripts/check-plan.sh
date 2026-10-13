#!/usr/bin/env bash
# Check scripts/squad-plan.sh (agent-squad #370) against a stub gh that answers every call it makes
# from a world of files: the milestones, the milestone's issues and the PR that closed each, the
# open PRs with their reviews and CI, the repository's files, its tags and its Releases. Each table
# is compared whole. A milestone with nothing started, one half done, with a PR under review, one
# with changes requested and one approved, and one complete, in a project and in a repository that
# tracks SQUAD.md; the plan issue rewritten between its markers, and left alone when only the time
# changed; no open milestone, and a milestone without a plan issue; a failed read or write; bad
# usage. Nothing reaches GitHub.
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
filter="" slurp=false endpoint="" milestone=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) filter="$2"; shift 2 ;;
    --slurp) slurp=true; shift ;;
    --paginate) shift ;;
    -F) [[ "$2" != milestone=* ]] || milestone="${2#milestone=}"; shift 2 ;;
    -H|-f) shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
case "$endpoint" in
  graphql)
    json="$(jq --argjson m "$milestone" '{data: {repository: {milestone: {issues: {nodes: [.[]
      | select(.milestone == $m and .state == "closed" and .pull_request == null)
      | {number, timelineItems: {nodes: (if .closer then [{closer: {number: .closer}}] else [{}] end)}}]}}}}}' "$W/issues.json")" ;;
  "repos/o/r/issues?state=open&per_page=100")
    json="$(jq --slurpfile milestones "$W/milestones.json" '[.[] | select(.state == "open") | del(.closer) | . as $issue
      | .milestone = ($milestones[0] | map(select(.number == $issue.milestone)) | first | if . then {number, title, html_url} else null end)]' \
      "$W/issues.json")" ;;
  "repos/o/r/issues?milestone="*"&state=all&per_page=100")
    milestone="${endpoint#repos/o/r/issues?milestone=}"
    json="$(jq --argjson m "${milestone%%&*}" 'map(select(.milestone == $m) | del(.closer, .milestone))' "$W/issues.json")" ;;
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
# `edits` counts the issue edits of the last run.
# shellcheck disable=SC2317,SC2329 # invoked through check
edits() { grep -c '^issue edit ' "$CALLS"; }

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
# M says otherwise ("null" for none).
issue() {
  jq --argjson n "$1" --arg state "$2" --arg title "$3" --argjson m "${M:-40}" '. + [{number: $n, state: $state, title: $title,
      body: "", milestone: $m, labels: [$ARGS.positional[] | {name: .}], html_url: "https://github.com/o/r/issues/\($n)"}]' \
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
# `pr <number> <issue it closes> <head> <ci: pass, fail, pending or none> [draft] [<reviewer requested>]`
# adds an open PR signed by DEV.
pr() {
  jq --argjson n "$1" --argjson closes "$2" --arg head "$3" --arg ci "$4" --arg draft "${5:-}" --arg requested "${6:-}" \
    '. + [{number: $n, isDraft: ($draft == "draft"), headRefOid: $head, body: "**👨🏼‍💻[DEV]:** Closes #\($closes).",
      closingIssuesReferences: [{number: $closes}], reviewRequests: (if $requested == "" then [] else [{login: $requested}] end),
      statusCheckRollup: {pass: [{__typename: "CheckRun", status: "COMPLETED", conclusion: "SUCCESS"}, {__typename: "StatusContext", state: "SUCCESS"}],
        fail: [{__typename: "CheckRun", status: "COMPLETED", conclusion: "SUCCESS"}, {__typename: "CheckRun", status: "COMPLETED", conclusion: "FAILURE"}],
        pending: [{__typename: "CheckRun", status: "IN_PROGRESS", conclusion: ""}], none: []}[$ci]}]' "$W/prs.json" > "$W/new"
  mv "$W/new" "$W/prs.json"
}
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
**[v55 — the labels](https://github.com/o/r/milestone/40)** · 0 of 4 issues closed · updated $time

| | Step | Who | State | Next |
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
**[v55 — the labels](https://github.com/o/r/milestone/40)** · 2 of 11 issues closed · updated $time

| | Step | Who | State | Next |
|---|---|---|---|---|
| 1 | #1 Closed by its PR | DEV | ✅ closed by PR #11 | — |
| 2 | #2 Closed by hand | CTO | ✅ closed | — |
| 3 | #3 Under review | DEV | 👀 PR #12 in review (\`aaaaaaa\`), CI ✅ | QA: review |
| 4 | #4 Changes requested | DEV | 👀 PR #13 changes requested (\`bbbbbbb\`), CI ❌ | DEV: answer the review |
| 5 | #5 Approved | DEV | 👀 PR #14 approved (\`ccccccc\`), CI ⏳ | DEV: merge |
| 6 | #6 In progress | QA | 🚧 in progress | QA: carry on |
| 7 | #7 Blocked | DEV | ⛔ blocked | DEV: unblock it |
| 8 | #8 Waits for the CEO | DEV | 👨🏻‍💼 waits for the CEO | CEO: decide |
| 9 | #9 A draft | DEV | 👀 PR #15 draft (\`ddddddd\`), no CI | DEV: finish the draft |
| 10 | #20 Approved, a reviewer requested | DEV | 👀 PR #17 approved (\`fffffff\`), CI ✅ | wait for alice |
| 11 | #21 In review, no open PR | DEV | 👀 in review, no open PR | DEV: carry on |
| 12 | Version PR | CTO | ⚪ waits for 9 issues | — |
| 13 | README read | CEO | ⚪ waits for the version PR | — |
| 14 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |
EOF
check "half done, upstream: exit 0" bash -c '[ "$1" -eq 0 ]' _ "$code"
check "the table is the one expected" same "$lab/expected"
check "a draft's reviews are not read" bash -c '! grep -q "pulls/15/reviews" "$1" && grep -q "pulls/12/reviews" "$1"' _ "$CALLS"

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

# 5. A project's README read, every issue closed: not asked yet, then waiting for the CEO.
world
issue 1 closed "Done" "👨🏼‍💻 owner:dev"
plan_issue 10
expect_steps "a project, every issue closed: the CTO asks the CEO" "| 2 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |"
set_issue 10 '.labels += [{name: "👨🏻‍💼 needs-ceo"}]'
expect_steps "a project, the plan issue labelled needs-ceo: the CEO reads it" "| 2 | README read | CEO | ⏳ waits for the CEO | CEO: read it |"

# 6. --update: the table between the markers, the text around them kept; then nothing written
#    while only the time changes, and written again when the table does.
world
issue 1 open "First" "👨🏼‍💻 owner:dev"
plan_issue 10
run
table="$out"
run --update
check "--update writes the plan issue once, saying so" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" -eq 1 ] && [ "$(tail -1 <<<"$3")" = "plan: #10 updated" ]' _ "$code" "$(edits)" "$out"
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

# 7. Two plan issues, in a repository that tracks SQUAD.md: v55's, with the release's own steps, and a
#    phase's, whose milestone names no version, with the README read alone. Each gets its own
#    milestone's table, in the order of their numbers, a blank line between them, and is written
#    with it. A plan issue with no milestone gets one line, and nothing written.
world && upstream 54
issue 1 open "First" "👨🏼‍💻 owner:dev" && plan_issue 10
M=42 issue 2 closed "Done in phase 2" "👨🏼‍💻 owner:dev" && M=42 plan_issue 5
M=null plan_issue 3
run --update
cat > "$lab/expected" <<EOF
plan: #3 is a plan issue with no milestone, so it has no table

**[Phase 2](https://github.com/o/r/milestone/42)** · 1 of 1 issues closed · updated $time

| | Step | Who | State | Next |
|---|---|---|---|---|
| 1 | #2 Done in phase 2 | DEV | ✅ closed | — |
| 2 | README read | CEO | ⚪ not asked yet | CTO: ask the CEO |
plan: #5 updated

**[v55 — the labels](https://github.com/o/r/milestone/40)** · 0 of 1 issues closed · updated $time

| | Step | Who | State | Next |
|---|---|---|---|---|
| 1 | #1 First | DEV | ⚪ not started | DEV: start it |
| 2 | Version PR | CTO | ⚪ waits for #1 | — |
| 3 | README read | CEO | ⚪ waits for the version PR | — |
| 4 | Tag, Release, install here | CTO | ⚪ waits for the CEO's OK | CTO: tag it, on the CEO's OK |
plan: #10 updated
EOF
check "two plan issues and one with no milestone: exit 0, two edits" bash -c '[ "$1" -eq 0 ] && [ "$2" -eq 2 ]' _ "$code" "$(edits)"
check "each plan issue with its own milestone's table, in order" same "$lab/expected"
check "each written with its own" \
  bash -c 'grep -qF "[Phase 2]" <<<"$1" && ! grep -qF "[v55" <<<"$1" && grep -qF "[v55" <<<"$2"' \
  _ "$(jq -r '.[] | select(.number == 5) | .body' "$W/issues.json")" "$(jq -r '.[] | select(.number == 10) | .body' "$W/issues.json")"

# 8. GitHub that cannot be read or written: exit 1, with gh's message and what failed.
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

# 9. Bad usage, and a checkout without the squad: exit 2, before anything reaches GitHub.
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

exit "$status"
