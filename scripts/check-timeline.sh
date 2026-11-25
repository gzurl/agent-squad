#!/usr/bin/env bash
# Check scripts/squad-timeline.sh (agent-squad #574) against a stub gh that answers every call it
# makes from a world of files: the milestones, their issues with the PRs that close them, and each
# PR's timeline and inline comments. Each table is compared whole. v76, rebuilt from its own
# events, gives the table the CEO saw on #574; a release in progress, chosen by its open plan issue,
# runs its open spans to the time of the run; with no plan issue open, the milestone closed last,
# whose rows hold the edge cases: no PR, a PR that never carried a status label, a PR opened before
# the in-progress label, several PRs, label events out of order, a night, the accounts and the
# lines that do not count. A milestone named by its title or its first word, or by neither; no
# milestone; a jq that ends its lines with CRLF, as on Windows (agent-squad #405); each failed
# read, a garbled answer and a call that never ends; bad usage. Nothing reaches GitHub.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
timeline="$root/scripts/squad-timeline.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-timeline.XXXXXX")" || exit 2
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
# `same <expected file>` passes when the last run printed exactly that file on its output, nothing
# on its errors, and exited 0; it shows the difference otherwise.
# shellcheck disable=SC2317,SC2329 # invoked through check
same() { diff "$1" <(printf '%s\n' "$out") >&2 && [ -z "$err" ] && [ "$code" -eq 0 ]; }

# GitHub, as far as the script is concerned: the files of the world $W. Each call is logged to
# $CALLS, one line. A call whose words hold STUB_FAIL fails, as gh does when GitHub cannot be
# reached; one whose words hold STUB_GARBAGE answers what is not JSON; and one whose words hold
# STUB_HANG never answers, its PID in $W/hung.pid. Every API call prints a hint on stderr, as gh
# does for a pull request's endpoints.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
# gh's own --jq ends its lines with LF on Windows too (go-gh's pkg/jq/jq.go), whatever jq does.
unset STUB_CRLF
printf '%s\n' "$*" >> "$CALLS"
if [ -n "${STUB_FAIL:-}" ] && [[ "$*" == *"$STUB_FAIL"* ]]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
if [ -n "${STUB_HANG:-}" ] && [[ "$*" == *"$STUB_HANG"* ]]; then echo "$$" > "$W/hung.pid"; exec sleep 60; fi
if [ -n "${STUB_GARBAGE:-}" ] && [[ "$*" == *"$STUB_GARBAGE"* ]]; then echo "<html>not JSON</html>"; exit 0; fi
case "$1 $2" in
  "repo view") echo o/r; exit 0 ;;
  "api "*) shift ;;
  *) exit 1 ;;
esac
echo "hint: what gh says on stderr about this call" >&2
milestone="" query="" endpoint=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate|--slurp) shift ;;
    -F) [[ "$2" != milestone=* ]] || milestone="${2#milestone=}"; shift 2 ;;
    -f) [[ "$2" != query=* ]] || query="${2#query=}"; shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
# An array as --paginate --slurp gives it: pages of two, and one empty page for an empty array.
pages='[range(0; [length, 1] | max; 2) as $i | .[$i:$i + 2]]'
case "$endpoint" in
  "repos/o/r/milestones?state=all&per_page=100") jq "$pages" "$W/milestones.json" ;;
  # The open issues, and an open PR whose description holds the plan's markers, which is no plan
  # issue.
  "repos/o/r/issues?state=open&per_page=100")
    jq '[.[] | select(.state == "open") | {number, body, milestone: (if .milestone then {number: .milestone} else null end)}]
      + [{number: 999, pull_request: {}, milestone: {number: 61}, body: "<!-- squad-plan:start -->\n<!-- squad-plan:end -->"}]
      | '"$pages" "$W/issues.json" ;;
  # The milestone's issues, by pages, as gh paginates a query that takes $endCursor: their labels,
  # their labelled events (a priority label first, then each in-progress label), and the PRs that
  # close them.
  graphql)
    # shellcheck disable=SC2016 # GraphQL's variable, not the shell's
    [[ "$query" == *'after: $endCursor'* ]] || exit 1
    jq --argjson m "$milestone" '[.[] | select(.milestone == $m) | {number, state: (.state | ascii_upcase), body,
        labels: {nodes: [.labels[] | {name: .}]},
        timelineItems: {nodes: ([{createdAt: "2026-11-01T00:00:00Z", label: {name: "🔵 P3"}}]
          + [.starts[] | {createdAt: ., label: {name: "🚧 status:in-progress"}}])},
        closedByPullRequestsReferences: {nodes: [.prs[] | {number, state, body, createdAt, mergedAt,
          repository: {nameWithOwner: .repo}}]}}]
      | [range(0; [length, 1] | max; 2) as $i | {data: {repository: {milestone: {issues: {nodes: .[$i:$i + 2]}}}}}]' \
      "$W/issues.json" ;;
  # A PR's timeline: a commit, which has no time, a priority label, its status labels, its reviews
  # and its comments.
  "repos/o/r/issues/"*"/timeline?per_page=100")
    number="${endpoint#repos/o/r/issues/}"
    jq --arg n "${number%%/*}" '.[$n] // {} | [{event: "committed", sha: "abc1234"},
        {event: "labeled", created_at: "2026-11-01T00:00:00Z", label: {name: "🐛 bug"}}]
      + [.labels // [] | .[] | {event: (if .on then "labeled" else "unlabeled" end), created_at: .at, label: {name}}]
      + [.reviews // [] | .[] | {event: "reviewed", state: "commented", author_association: .assoc, body}]
      + [.comments // [] | .[] | {event: "commented", author_association: .assoc, body}]
      | '"$pages" "$W/prs.json" ;;
  "repos/o/r/pulls/"*"/comments?per_page=100")
    number="${endpoint#repos/o/r/pulls/}"
    jq --arg n "${number%%/*}" '[.[$n].inline // [] | .[]
        | {author_association: .assoc, body, in_reply_to_id: (if .reply then 7001 else null end)}] | '"$pages" "$W/prs.json" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
# jq as on Windows (agent-squad #405), in the runs that `crlf <command...>` makes: every line it
# writes ends with CRLF. The stub gh, which uses jq too, sets it aside.
mkdir -p "$lab/crlf"
printf '#!/usr/bin/env bash\n[ -n "${STUB_CRLF:-}" ] || exec %q "$@"\n%q "$@" | awk %q\nexit "${PIPESTATUS[0]}"\n' \
  "$(command -v jq)" "$(command -v jq)" '{ printf "%s\r\n", $0 }' > "$lab/crlf/jq"
chmod +x "$lab/crlf/jq"
crlf() { STUB_CRLF=1 PATH="$lab/crlf:$PATH" "$@"; }
export PATH="$lab/bin:$PATH" CALLS="$lab/calls" W="$lab/world" TZ=UTC

# The scratch checkout the script runs from.
project="$lab/project"
git init -q "$project"
# `run [args]` runs the script from the checkout at $now, into out, err and code, after clearing
# the log.
run() {
  : > "$CALLS"
  out="$(cd "$project" && SQUAD_NOW="$now" "$timeline" "$@" 2>"$lab/err" </dev/null)"
  code=$?
  err="$(cat "$lab/err")"
}

# The world. A time is a time of day on $DAY, 2026-11-13 unless set, in UTC, or a full ISO time;
# - is none.
iso() {
  case "$1" in
    -|*T*) echo "$1" ;;
    ??:??) echo "${DAY:-2026-11-13}T$1:00Z" ;;
    *) echo "${DAY:-2026-11-13}T$1Z" ;;
  esac
}
# A text of several lines, its lines ending with CRLF when $CRLF is set, as some clients write.
lines() { if [ -n "${CRLF:-}" ]; then printf '%s\r\n' "$@"; else printf '%s\n' "$@"; fi; }
world() {
  rm -rf "$W" && mkdir -p "$W"
  echo '[]' > "$W/milestones.json" && echo '[]' > "$W/issues.json" && echo '{}' > "$W/prs.json"
}
# `update <file> <jq program> [<jq option>...]` changes a file of the world.
update() {
  local file="$W/$1" program="$2"
  shift 2
  jq "$@" "$program" "$file" > "$W/new" && mv "$W/new" "$file"
}
# `milestone <number> <open|closed> <closed at|-> <title>`
milestone() {
  update milestones.json '. + [{number: $n, title: $title, state: $state, closed_at: (if $at == "-" then null else $at end),
      html_url: "https://github.com/o/r/milestone/\($n)", open_issues: 0}]' \
    --argjson n "$1" --arg state "$2" --arg at "$(iso "$3")" --arg title "$4"
}
# `issue <milestone|-> <number> <open|closed> <owner: CTO, DEV, QA or -> <in-progress label|->
# [plan|quoted]`: an issue, its first in-progress label at that time; a plan issue's description
# holds the plan's markers, each on a line of its own, and a quoted one names them inline.
issue() {
  local body
  case "${6:-}" in
    plan) body="$(lines "**👷🏼‍♂️[CTO]:** The plan." "" "<!-- squad-plan:start -->" "| table |" "<!-- squad-plan:end -->")" ;;
    quoted) body="It writes the table between <!-- squad-plan:start --> and <!-- squad-plan:end -->." ;;
    *) body="**👷🏼‍♂️[CTO]:** An issue." ;;
  esac
  update issues.json '. + [{milestone: (if $m == "-" then null else ($m | tonumber) end), number: $n, state: $state, body: $body,
      labels: (["🔵 P3"] + ({CTO: ["👷🏼‍♂️ owner:cto"], DEV: ["👨🏼‍💻 owner:dev"], QA: ["👩🏼‍🔬 owner:qa"]}[$owner] // [])),
      starts: (if $start == "-" then [] else [$start] end), prs: []}]' \
    --arg m "$1" --argjson n "$2" --arg state "$3" --arg owner "$4" --arg start "$(iso "$5")" --arg body "$body"
}
# `relabel <issue> <time>`: the issue goes in progress again.
relabel() { update issues.json 'map(if .number == $n then .starts += [$at] else . end)' --argjson n "$1" --arg at "$(iso "$2")"; }
# `pr <issue> <pr> <MERGED|OPEN|CLOSED> <created> <merged|-> <signature: CTO, DEV, QA or ->
# [<repository>]`: a PR that closes the issue, of o/r unless another repository is given.
pr() {
  local body
  case "$6" in
    CTO) body="**👷🏼‍♂️[CTO]:** The change." ;;
    DEV) body="**👨🏼‍💻[DEV]:** The change." ;;
    QA) body="**👩🏼‍🔬[QA]:** The change." ;;
    *) body="The change, unsigned." ;;
  esac
  update issues.json 'map(if .number == $issue then .prs += [{number: $n, state: $state, body: $body, createdAt: $created,
      mergedAt: (if $merged == "-" then null else $merged end), repo: $repo}] else . end)' \
    --argjson issue "$1" --argjson n "$2" --arg state "$3" --arg created "$(iso "$4")" --arg merged "$(iso "$5")" \
    --arg body "$body" --arg repo "${7:-o/r}"
}
# `label <pr> <+|-><in-review|in-progress|approved> <time>`: the PR's status label added or removed.
label() {
  update prs.json '.[$n].labels += [{on: ($change[0:1] == "+"), at: $at,
      name: {"in-review": "👀 status:in-review", "in-progress": "🚧 status:in-progress", approved: "✅ status:approved"}[$change[1:]]}]' \
    --arg n "$1" --arg change "$2" --arg at "$(iso "$3")"
}
# `review <pr> <association> <last line>`: a review by an account of that association, whose last
# line is that one.
review() {
  update prs.json '.[$n].reviews += [{assoc: $assoc, body: $body}]' --arg n "$1" --arg assoc "$2" \
    --arg body "$(lines "**👩🏼‍🔬[QA]:** ✅ The review." "" "$3")"
}
# `comment <pr> <association> <first line>` and `inline <pr> <association> <top|reply> <first
# line>`: a comment on the PR, or an inline one, opening a thread or replying in one.
comment() {
  update prs.json '.[$n].comments += [{assoc: $assoc, body: $body}]' --arg n "$1" --arg assoc "$2" \
    --arg body "$(lines "$3" "" "The detail.")"
}
inline() {
  update prs.json '.[$n].inline += [{assoc: $assoc, reply: ($where == "reply"), body: $body}]' --arg n "$1" --arg assoc "$2" \
    --arg where "$3" --arg body "$(lines "$4" "The detail.")"
}
# `expect <name>` writes the expected output from its input, into $lab/<name>.
expect() { cat > "$lab/$1"; }

header='| | Issue | PR | Author | Before the PR | Waiting for QA | Fixing | Approved → merge | Total | Rounds | Sent back | Findings |
|---|---|---|---|---|---|---|---|---|---|---|---|'
wall='Times are wall-clock, not effort: a night or a `/squad-pause` counts.'

echo "check-timeline: the tables" >&2
# 1. v76, rebuilt from its own events: its plan issue, #564, and its five issues, each closed by its
#    PR, with their status labels, reviews and findings as GitHub recorded them, and the comments
#    and replies that are no findings. It gives the table the CEO saw on #574, computed by hand.
v76() {
  world
  milestone 61 closed 22:35:04 "v76 — a plan's own steps are the project's checklist; two races in the watch and the plan"
  issue 61 564 closed CTO - plan
  issue 61 560 closed DEV 20:04:55 && pr 560 570 MERGED 20:24:56 20:58:04 DEV
  issue 61 561 closed DEV 19:56:48 && pr 561 569 MERGED 20:02:55 20:26:54 DEV
  issue 61 562 closed DEV 19:44:00 && pr 562 566 MERGED 19:55:32 20:07:39 DEV
  issue 61 563 closed CTO 19:43:20 && pr 563 565 MERGED 19:47:12 19:56:37 CTO
  issue 61 567 closed CTO 19:57:09 && pr 567 568 MERGED 19:59:04 20:08:40 CTO
  label 565 +in-review 19:47:15 && label 565 +approved 19:54:51 && label 565 -in-review 19:54:51
  review 565 OWNER "QA-VERDICT: APPROVED"
  comment 565 OWNER '**👩🏼‍🔬[QA]:** ✅ State: approved `df146f3` with 2 P3s.'
  inline 565 OWNER top "**👩🏼‍🔬[QA]:** ⚠️ [P3] The table's description now"
  inline 565 OWNER top "**👩🏼‍🔬[QA]:** ⚠️ [P3] A plan can now hold several"
  inline 565 OWNER reply "**👷🏼‍♂️[CTO]:** ⏳ Deferred to #567, in v76."
  inline 565 OWNER reply "**👷🏼‍♂️[CTO]:** ⏳ Deferred to #567, in v76."
  label 566 +in-review 19:58:53 && label 566 -in-review 20:06:11 && label 566 +approved 20:06:11
  review 566 OWNER "QA-VERDICT: APPROVED"
  comment 566 OWNER '**👩🏼‍🔬[QA]:** ✅ State: approved `df48c8e`, no findings.'
  label 568 +in-review 19:59:08 && label 568 -in-review 20:07:40 && label 568 +approved 20:07:40
  review 568 OWNER "QA-VERDICT: APPROVED"
  label 569 +in-review 20:06:27 && label 569 -in-review 20:12:38 && label 569 +approved 20:12:38
  label 569 +in-review 20:24:23 && label 569 -approved 20:24:23 && label 569 -in-review 20:25:58 && label 569 +approved 20:25:59
  review 569 OWNER "QA-VERDICT: APPROVED" && review 569 OWNER "" && review 569 OWNER "QA-VERDICT: APPROVED"
  inline 569 OWNER top "**👩🏼‍🔬[QA]:** ⚠️ [P3] The rewrap left this line at 129 columns."
  inline 569 OWNER reply '**👨🏼‍💻[DEV]:** ✅ Fixed in `95b61bc`, rewrapped.'
  label 570 +in-review 20:28:02 && label 570 +in-progress 20:38:29 && label 570 -in-review 20:38:29
  label 570 -in-progress 20:46:49 && label 570 +in-review 20:46:49 && label 570 -in-review 20:50:27 && label 570 +approved 20:50:27
  label 570 +in-review 20:55:45 && label 570 -approved 20:55:45 && label 570 -in-review 20:57:18 && label 570 +approved 20:57:18
  review 570 OWNER "QA-VERDICT: CHANGES-REQUESTED" && review 570 OWNER "" && review 570 OWNER "QA-VERDICT: APPROVED"
  review 570 OWNER "" && review 570 OWNER "QA-VERDICT: APPROVED"
  comment 570 OWNER '**👩🏼‍🔬[QA]:** ✅ State: approved `e811d22`, every thread resolved.'
  inline 570 OWNER top "**👩🏼‍🔬[QA]:** ❌ [P2] claims: yes. Claim 2 fails for a fence."
  inline 570 OWNER reply '**👨🏼‍💻[DEV]:** ✅ Fixed in `1536b56` with your change.'
  inline 570 OWNER top "**👩🏼‍🔬[QA]:** ⚠️ [P3] This line runs to 133 columns."
  inline 570 OWNER reply '**👨🏼‍💻[DEV]:** ✅ Fixed in `e811d22` with your rewrap.'
}
expect v76 <<EOF
**[v76 — a plan's own steps are the project's checklist; two races in the watch and the plan](https://github.com/o/r/milestone/61)** · 5 of 5 issues closed · as of 2026-11-25 22:00

$header
| 1 | #560 | #570 | DEV | 20 min | 15 min | 8 min | 6 min | 53 min | 3 | 1 | P2 1 · P3 1 |
| 2 | #561 | #569 | DEV | 6 min | 7 min | 0 min | 12 min | 30 min | 2 | 0 | P3 1 |
| 3 | #562 | #566 | DEV | 11 min | 7 min | 0 min | 1 min | 23 min | 1 | 0 | — |
| 4 | #563 | #565 | CTO | 3 min | 7 min | 0 min | 1 min | 13 min | 1 | 0 | P3 2 |
| 5 | #567 | #568 | CTO | 1 min | 8 min | 0 min | 1 min | 11 min | 1 | 0 | — |
| | **Total** | | | 41 min | 44 min | 8 min | 21 min | 2 h 10 min | 8 | 1 | P2 1 · P3 4 |

$wall
EOF
now="$(jq -nr '"2026-11-25T22:00:00Z" | fromdateiso8601')"
v76
run v76
check "v76 by its first word: the CEO's table of #574, computed by hand from the same events" same "$lab/v76"
run "v76 — a plan's own steps are the project's checklist; two races in the watch and the plan"
check "v76 by its whole title: the same table" same "$lab/v76"
crlf run v76
check "v76 with a jq that ends its lines with CRLF: the same table" same "$lab/v76"
check "a run writes nothing to GitHub, and reads each PR's timeline and inline comments once" \
  bash -c '! grep -qE -- "-X|POST|PATCH|DELETE|edit" "$1" && [ "$(grep -c "/timeline" "$1")" -eq 5 ] && [ "$(grep -c "/comments" "$1")" -eq 5 ]' \
  _ "$CALLS"

# 2. The release in progress, chosen by its open plan issue, #575, when no milestone is named:
#    v77, open, beside v76, closed, and a phase whose issue only quotes the plan's markers. An open
#    PR under review, then being fixed; an issue in progress with no PR; one not started. Its open
#    spans run to the time of the run.
in_progress() {
  v76
  milestone 62 open - "v77 — a release timeline"
  milestone 63 open - "Phase 2"
  issue 63 590 open CTO - quoted
  DAY=2026-11-25
  issue 62 575 open CTO - plan
  issue 62 572 open CTO 21:00 && pr 572 576 OPEN 21:04 - CTO
  label 576 +in-review 21:05 && label 576 -in-review 21:20 && label 576 +in-progress 21:20
  review 576 OWNER "QA-VERDICT: CHANGES-REQUESTED"
  inline 576 OWNER top "**👩🏼‍🔬[QA]:** ❌ [P1] The span runs past the merge."
  inline 576 OWNER reply "**👷🏼‍♂️[CTO]:** ⏳ [P2] Fixing it."
  issue 62 574 open DEV 21:11
  issue 62 577 open QA -
  unset DAY
}
expect in-progress <<EOF
**[v77 — a release timeline](https://github.com/o/r/milestone/62)** · 0 of 3 issues closed · as of 2026-11-25 21:30

$header
| 1 | #572 | #576 | CTO | 4 min | 15 min | 10 min | 0 min | 30 min | 1 | 1 | P1 1 |
| 2 | #574 | — | DEV | 19 min | — | — | — | 19 min | — | — | — |
| 3 | #577 | — | QA | — | — | — | — | — | — | — | — |
| | **Total** | | | 23 min | 15 min | 10 min | 0 min | 49 min | 1 | 1 | P1 1 |

$wall
- #572: PR #576 is not merged yet: its times run to 2026-11-25 21:30.
- #574: no open PR yet: its times run to 2026-11-25 21:30.
- #577: not started yet.
EOF
now="$(jq -nr '"2026-11-25T21:30:00Z" | fromdateiso8601')"
in_progress
run
check "no milestone named: the release in progress, its open spans run to the time of the run" same "$lab/in-progress"
crlf run
check "the release in progress with a jq that ends its lines with CRLF: the same table" same "$lab/in-progress"
#    Two plans open: each milestone's table, a blank line between, by number; a plan issue with no
#    milestone has none.
update issues.json 'map(if .number == 590 then .body = $plan else . end)' --arg plan "$(lines "<!-- squad-plan:start -->" "<!-- squad-plan:end -->")"
issue - 591 open CTO - plan
expect two <<EOF
$(cat "$lab/in-progress")

**[Phase 2](https://github.com/o/r/milestone/63)** · 0 of 0 issues closed · as of 2026-11-25 21:30

$header
| | **Total** | | | — | — | — | — | — | — | — | — |

$wall
EOF
run
check "two plan issues open: both milestones, by number, the one with no issue but its plan issue empty" same "$lab/two"

# 3. No plan issue open: the milestone closed last, by when it closed, not by its number, here v80
#    over v81; an open milestone with no plan issue is not in progress. Its rows hold the edge
#    cases:
#    - #1: closed, never in progress, with no PR, and #6 the same with no owner either;
#    - #2: its PR opened before the in-progress label, and never labelled itself;
#    - #3: a night; label events out of order, the approved label kept after the merge; a closed
#      PR, two merged ones, the later unsigned, one of another repository merged later still, and an
#      open one; the reviews and the comments of outside accounts, a verdict that is not the last
#      line, a priority tag that does not open its line, an inline reply, and the findings of DEV
#      and of a signature without bold;
#    - #4: open, though its PR was merged, its approved label removed after the merge, its review's
#      lines ending with CRLF;
#    - #5: open and in progress, its one PR closed unmerged;
#    - #7: two open PRs, the later of which stands for it, never labelled.
world
milestone 70 closed 2026-11-20T10:00:00Z "v80 — closed last"
milestone 71 closed 2026-11-10T10:00:00Z "v81 — closed first"
milestone 72 open - "v82 — open, with no plan"
issue 71 700 closed DEV 09:00 && pr 700 701 MERGED 09:10 09:20 DEV
issue 72 710 open DEV 09:00
issue 70 1 closed CTO -
issue 70 2 closed DEV 09:00 && pr 2 20 MERGED 08:50 10:00 DEV
issue 70 3 closed DEV 2026-11-12T18:00:00Z && relabel 3 08:00
pr 3 29 MERGED 2026-11-12T18:05:00Z 2026-11-12T19:00:00Z DEV && pr 3 30 CLOSED 2026-11-12T18:10:00Z - DEV
pr 3 31 MERGED 2026-11-12T18:30:00Z 09:03 -
pr 3 32 MERGED 2026-11-12T18:20:00Z 09:30 DEV o/other && pr 3 33 OPEN 08:40 - DEV
label 31 -in-review 2026-11-12T18:31:00Z && label 31 +in-review 2026-11-12T18:31:00Z
label 31 +in-review 2026-11-12T18:35:00Z && label 31 -in-review 08:00 && label 31 +approved 08:00
label 30 +in-review 2026-11-12T18:11:00Z
review 31 OWNER "QA-VERDICT: APPROVED" && review 31 MEMBER "QA-VERDICT: CHANGES-REQUESTED"
review 31 COLLABORATOR "QA-VERDICT: APPROVED" && review 31 CONTRIBUTOR "QA-VERDICT: APPROVED"
review 31 NONE "QA-VERDICT: CHANGES-REQUESTED" && review 31 OWNER "QA-VERDICT: APPROVED, as the line above says"
update prs.json '.["31"].reviews += [{assoc: "OWNER", body: "QA-VERDICT: APPROVED\n\nA line after the verdict."}]'
comment 31 OWNER "**👩🏼‍🔬[QA]:** ⚠️ [P2] A body-only finding."
comment 31 OWNER "👩🏼‍🔬[QA]: ⚠️ [P2] A finding signed without bold, as before v40."
comment 31 NONE "**👩🏼‍🔬[QA]:** ⚠️ [P1] From an outside account."
comment 31 OWNER "**👩🏼‍🔬[QA]:** ✅ State: approved, and the [P3] is deferred."
inline 31 OWNER top "**👩🏼‍🔬[QA]:** [P3] A finding with no status emoji."
inline 31 OWNER top "**👨🏼‍💻[DEV]:** ❌ [P1] DEV reviews a PR that QA authors."
inline 31 OWNER reply "**👩🏼‍🔬[QA]:** ⚠️ [P1] A reply is no finding."
inline 31 FIRST_TIME_CONTRIBUTOR top "**👩🏼‍🔬[QA]:** ⚠️ [P1] From an outside account."
issue 70 4 open CTO 10:00 && pr 4 40 MERGED 10:05 10:20 CTO
label 40 +in-review 10:06 && label 40 -in-review 10:16 && label 40 +approved 10:16 && label 40 -approved 10:25
CRLF=1 review 40 OWNER "QA-VERDICT: APPROVED"
issue 70 5 open DEV 11:00 && pr 5 50 CLOSED 11:10 - DEV
issue 70 6 closed - -
issue 70 7 open DEV 11:30 && pr 7 72 OPEN 11:45 - DEV && pr 7 71 OPEN 11:40 - CTO
expect closed <<EOF
**[v80 — closed last](https://github.com/o/r/milestone/70)** · 4 of 7 issues closed · as of 2026-11-13 12:00

$header
| 1 | #1 | — | CTO | — | — | — | — | — | — | — | — |
| 2 | #2 | #20 | DEV | — | — | — | — | 1 h 0 min | 0 | 0 | — |
| 3 | #3 | #31 | DEV | 30 min | 13 h 29 min | 0 min | 1 h 3 min | 15 h 3 min | 3 | 1 | P1 1 · P2 2 · P3 1 |
| 4 | #4 | #40 | CTO | 5 min | 10 min | 0 min | 4 min | 20 min | 1 | 0 | — |
| 5 | #5 | — | DEV | 1 h 0 min | — | — | — | 1 h 0 min | — | — | — |
| 6 | #6 | — | — | — | — | — | — | — | — | — | — |
| 7 | #7 | #72 | DEV | 15 min | — | — | — | 30 min | 0 | 0 | — |
| | **Total** | | | 1 h 50 min | 13 h 39 min | 0 min | 1 h 7 min | 17 h 53 min | 4 | 1 | P1 1 · P2 2 · P3 1 |

$wall
- #1: never labelled in progress, so Before the PR and Total have no start.
- #1: closed with no merged PR, so the PR's columns have no data.
- #2: labelled in progress only after PR #20 was opened, so Before the PR has no span.
- #2: PR #20 never carried a status label, so its three label columns have no data.
- #5: no open PR yet: its times run to 2026-11-13 12:00.
- #6: never labelled in progress, so Before the PR and Total have no start.
- #6: closed with no merged PR, so the PR's columns have no data.
- #7: PR #72 is not merged yet: its times run to 2026-11-13 12:00.
- #7: PR #72 never carried a status label, so its three label columns have no data.
EOF
now="$(jq -nr '"2026-11-13T12:00:00Z" | fromdateiso8601')"
run
check "no plan issue open: the milestone closed last, with each edge case's cells and notes" same "$lab/closed"
crlf run
check "the milestone closed last with a jq that ends its lines with CRLF: the same table" same "$lab/closed"
run "v81 — closed first"
check "a milestone named by its whole title, though another closed after it" \
  bash -c '[ "$1" -eq 0 ] && grep -qF "**[v81 — closed first](https://github.com/o/r/milestone/71)** · 1 of 1 issues closed" <<<"$2" \
    && grep -qxF "| 1 | #700 | #701 | DEV | 10 min | — | — | — | 20 min | 0 | 0 | — |" <<<"$2"' _ "$code" "$out"

echo "check-timeline: the milestone named, or none" >&2
# 4. A name that is no milestone's title nor its first word, and one that several titles start with:
#    exit 2, saying which. A title that is a whole milestone's wins over those it starts.
world
milestone 80 open - "Beta one" && milestone 81 open - "Beta two" && milestone 82 closed 10:00 "v7"
milestone 83 closed 11:00 "v76 — the plan" && milestone 84 open - "Beta"
issue 84 1 open DEV -
run v77
check "a milestone that is not there: exit 2, saying so, nothing on the output" \
  bash -c '[ "$1" -eq 2 ] && [ -z "$2" ] && [ "$3" = "timeline: no milestone'"'"'s title is v77 or starts with it" ]' _ "$code" "$out" "$err"
run Beta
check "a whole title wins over the titles that start with it" \
  bash -c '[ "$1" -eq 0 ] && grep -qF "**[Beta](https://github.com/o/r/milestone/84)**" <<<"$2"' _ "$code" "$out"
update milestones.json 'map(select(.number != 84))'
run Beta
check "a first word that several titles start with: exit 2, naming them" \
  bash -c '[ "$1" -eq 2 ] && [ -z "$2" ] && [ "$3" = "timeline: several milestones'"'"' titles start with Beta: Beta one; Beta two" ]' \
  _ "$code" "$out" "$err"
run v7
check "v7 is v7's, not v76's" bash -c '[ "$1" -eq 0 ] && grep -qF "**[v7](https://github.com/o/r/milestone/82)** · 0 of 0 issues closed" <<<"$2"' \
  _ "$code" "$out"
# 5. No milestone at all, or only open ones with no plan issue: one line, exit 0.
world
run
check "no milestone: one line, exit 0" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" = "timeline: no milestone is in progress, with an open plan issue, nor closed" ] && [ -z "$3" ]' \
  _ "$code" "$out" "$err"
milestone 90 open - "v90 — no plan issue"
run
check "only an open milestone with no plan issue: the same line" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" = "timeline: no milestone is in progress, with an open plan issue, nor closed" ]' _ "$code" "$out"

echo "check-timeline: failures and usage" >&2
# 6. A call that fails stops the run with exit 1, gh's message, and the line that says what could
#    not be read, and prints no table; a garbled answer too, with that line alone.
now="$(jq -nr '"2026-11-25T22:00:00Z" | fromdateiso8601')"
v76
while IFS='|' read -r failing message; do
  STUB_FAIL="$failing" run v76
  check "$failing fails: exit 1, gh's message, then: $message" \
    bash -c '[ "$1" -eq 1 ] && [ -z "$2" ] && [ "$3" = "$(printf "HTTP 502: Bad Gateway\ntimeline: %s" "$4")" ]' _ "$code" "$out" "$err" "$message"
done <<'CASES'
repo view|cannot read the repository, as gh says above
milestones|cannot read the milestones, as gh says above
graphql|cannot read the issues of v76 — a plan's own steps are the project's checklist; two races in the watch and the plan, as gh says above
issues/566/timeline|cannot read the timeline of PR #566, as gh says above
pulls/569/comments|cannot read the inline comments of PR #569, as gh says above
CASES
STUB_FAIL="issues?state=open" run
check "the open issues fail: exit 1, gh's message, then why" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "$(printf "HTTP 502: Bad Gateway\ntimeline: cannot read the open issues, as gh says above")" ]' _ "$code" "$err"
while IFS='|' read -r garbled args message; do
  # shellcheck disable=SC2086 # no argument, or one word
  STUB_GARBAGE="$garbled" run $args
  check "$garbled garbled: exit 1, $message" \
    bash -c '[ "$1" -eq 1 ] && [ -z "$2" ] && grep -qxF "timeline: $4" <<<"$3"' _ "$code" "$out" "$err" "$message"
done <<'CASES'
milestones|v76|cannot read the milestones
issues?state=open||cannot read the open issues
graphql|v76|cannot read the issues of v76 — a plan's own steps are the project's checklist; two races in the watch and the plan
issues/570/timeline|v76|cannot read the timeline of PR #570
pulls/565/comments|v76|cannot read the timeline of PR #565
CASES
#    A call that GitHub never answers is stopped after SQUAD_GH_TIMEOUT seconds of wall-clock time,
#    and fails the run as any other failure does, below the line that says why (agent-squad #430).
started=$SECONDS
STUB_HANG=graphql SQUAD_GH_TIMEOUT=1 run v76
# Within 30 s: well under its stub's 60 s, and over what CI's kcov takes (agent-squad #447).
check "a call that GitHub never answers is stopped after its bound, within 30 s: exit 1, saying so, and nothing left running" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" -le 30 ] && [ "$(tail -n 2 <<<"$3")" = "$4" ] && ! kill -0 "$(cat "$5")" 2>/dev/null' \
  _ "$code" "$((SECONDS - started))" "$err" \
  "$(printf '%s\n%s' "squad-timeout: gh did not end within 1 s, so it was stopped" "timeline: cannot read the issues of v76 — a plan's own steps are the project's checklist; two races in the watch and the plan, as gh says above")" \
  "$W/hung.pid"
SQUAD_GH_TIMEOUT=abc run v76
check "a SQUAD_GH_TIMEOUT that is no number reads GitHub as without one" same "$lab/v76"

# 7. Bad usage: two words, an option, an empty name: exit 2 with the usage line, and nothing asked
#    of GitHub. Run from a directory that is no checkout: exit 2, saying so.
for args in "v76 v77" "--all" ""; do
  # shellcheck disable=SC2086 # the words split on purpose, the empty one given as one
  if [ -z "$args" ]; then run ""; else run $args; fi
  check "bad usage ('$args'): exit 2, the usage line, no call" \
    bash -c '[ "$1" -eq 2 ] && [ -z "$2" ] && [ "$3" = "usage: squad-timeline.sh [<milestone>]" ] && [ ! -s "$4" ]' \
    _ "$code" "$out" "$err" "$CALLS"
done
mkdir -p "$lab/nowhere"
: > "$CALLS"
out="$(cd "$lab/nowhere" && GIT_CEILING_DIRECTORIES="$lab" "$timeline" 2>&1)"
code=$?
check "run from no checkout: exit 2, saying so, no call" \
  bash -c '[ "$1" -eq 2 ] && [ "$2" = "timeline: run it from a checkout of the project" ] && [ ! -s "$3" ]' _ "$code" "$out" "$CALLS"

exit "$status"
