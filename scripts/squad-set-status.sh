#!/usr/bin/env bash
# Set the status label of an issue or a PR as SQUAD.md §3 asks, in one command that cannot be half
# run (agent-squad #367). It first reads the item's kind, and refuses a number of the other kind
# before anything is written, since the API answers for a PR as for an issue and gh issue edit would
# edit a PR (agent-squad #375). Then one gh edit adds the state's label and removes every other
# status label, never listing the one it adds among those it removes, since the removal would win
# and leave none. Then the item's labels are read back from the API: the script exits 0 only when
# its status labels are exactly the one asked for, or none for `none`. Labels that are not status
# labels are left as they are. It works from any worktree of a project, on the repository its
# checkout names, as gh reads it there. The four status labels must exist in that repository
# (BOOTSTRAP.md row 7), since gh refuses to remove a label the repository lacks. Once the state is
# read back, squad-plan.sh --update rewrites the table of each release in progress, so that the
# pinned plan follows every state change (agent-squad #370).
#
# Usage: squad-set-status.sh <issue|pr> <number> <state>
#   <state>: in-progress, in-review, blocked (an issue only), approved (a PR only), or none
# Output: one line, such as
#   status: issue #12 is 🚧 status:in-progress
#   status: PR #34 has no status label
# and, for an issue set in progress, a second that reminds its owner of the state it owes now,
# naming the approach (SQUAD.md §3, agent-squad #521); then, on stderr, a warning when the plan's
# table could not be updated, which leaves the exit status as it is.
# Exit: 0 set and read back; 1 the item is of the other kind, nothing written; the edit or a read
#       failed; or the item carries other status labels than the one asked for, saying what it
#       carries; 2 bad usage, before anything reaches GitHub.
set -u
# Each GitHub call goes through squad-timeout.sh, beside this script, which stops it after
# SQUAD_GH_TIMEOUT seconds of wall-clock time (120 when unset, or not a whole number above 0),
# saying so above this script's own message: a call that GitHub never answers fails, as any other
# failure does (agent-squad #435).
gh_seconds="${SQUAD_GH_TIMEOUT:-120}"
[[ "$gh_seconds" =~ ^[1-9][0-9]*$ ]] || gh_seconds=120
gh() { "$(dirname "$0")/squad-timeout.sh" "$gh_seconds" gh "$@"; }
usage="usage: squad-set-status.sh <issue|pr> <number> <in-progress|in-review|blocked|approved|none>"
# `refuse <reason>` stops on bad usage.
refuse() {
  echo "status: $1" >&2
  echo "$usage" >&2
  exit 2
}
[ $# -eq 3 ] || refuse "it takes three arguments, not $#"
kind="$1" number="$2" state="$3"

# The item: its kind, and its number, a plain integer (SQUAD.md §6, Validate the identifier).
case "$kind" in
  issue) name="issue #$number" ;;
  pr) name="PR #$number" ;;
  *) refuse "the kind is issue or pr, not '$kind'" ;;
esac
case "$number" in ""|*[!0-9]*) refuse "the number is a plain integer, not '$number'" ;; esac

# The state's label, among the four, and whether it applies to the kind (§3's table): blocked is an
# issue's state only, and approved a PR's.
statuses=("🚧 status:in-progress" "👀 status:in-review" "⛔ status:blocked" "✅ status:approved")
case "$kind:$state" in
  *:in-progress) label="${statuses[0]}" ;;
  *:in-review) label="${statuses[1]}" ;;
  issue:blocked) label="${statuses[2]}" ;;
  pr:approved) label="${statuses[3]}" ;;
  *:none) label="" ;;
  issue:approved) refuse "approved is a PR's state, not an issue's (SQUAD.md §3)" ;;
  pr:blocked) refuse "blocked is an issue's state, not a PR's (SQUAD.md §3)" ;;
  *) refuse "the state is in-progress, in-review, blocked, approved or none, not '$state'" ;;
esac

# The item's kind, read before anything is written (agent-squad #375): the API answers issues/<n>
# for a PR too, and gh issue edit would edit a PR, so a number of the other kind is refused here.
if ! actual="$(gh api "repos/{owner}/{repo}/issues/$number" --jq 'if has("pull_request") then "pr" else "issue" end' </dev/null)"; then
  echo "status FAILED: cannot read $name, as gh says above; nothing was written" >&2
  exit 1
fi
case "$kind:$actual" in
  issue:pr) echo "status FAILED: #$number is a PR, not an issue; nothing was written" >&2; exit 1 ;;
  pr:issue) echo "status FAILED: #$number is an issue, not a PR; nothing was written" >&2; exit 1 ;;
esac

# One edit: the state's label added, and every other status label removed, all four for none.
edit=()
[ -z "$label" ] || edit+=(--add-label "$label")
for status in "${statuses[@]}"; do
  [ "$status" = "$label" ] || edit+=(--remove-label "$status")
done
edited=""
gh "$kind" edit "$number" "${edit[@]}" </dev/null >/dev/null || edited="cannot edit $name, as gh says above; "

# The read-back, even after a failed edit, which may have changed part of what it asked: the item's
# status labels, by the end of their names, so that one written with another emoji counts too.
if ! found="$(gh api "repos/{owner}/{repo}/issues/$number" </dev/null \
  --jq '[.labels[].name | select(test("status:(in-progress|in-review|blocked|approved)$"))] | join(", ")')"; then
  echo "status FAILED: ${edited}cannot read the labels of $name, as gh says above" >&2
  exit 1
fi
carries="${found:-no status label}"
if [ -n "$edited" ]; then
  echo "status FAILED: ${edited}it carries $carries" >&2
  exit 1
fi
if [ "$found" != "$label" ]; then
  echo "status FAILED: $name carries $carries, where ${label:-none} was asked" >&2
  exit 1
fi
if [ -n "$label" ]; then echo "status: $name is $label"; else echo "status: $name has no status label"; fi
# Whoever sets an issue in progress writes a state on it in the same step, naming the approach
# (agent-squad #521).
[ "$kind:$state" != issue:in-progress ] \
  || echo "status: now write a state on $name that names your approach, in a line or two (SQUAD.md §3)"

# The plan's table follows the state (agent-squad #370): squad-plan.sh, beside this script, rewrites
# each open plan issue's table when it changed. A failure costs the state nothing, whose exit status
# stands: one warning, and the next update corrects the table.
"$(dirname "$0")/squad-plan.sh" --update </dev/null >/dev/null 2>&1 \
  || echo "status: warning: the plan's table could not be updated; the next update corrects it" >&2
