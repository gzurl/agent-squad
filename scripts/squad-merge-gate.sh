#!/usr/bin/env bash
# Merge gate of SQUAD.md §4.9, checked by API. Prints the verified head SHA on stdout and exits 0
# when every condition holds; otherwise prints the reason on stderr and exits non-zero, so that
# SQUAD.md §4.9's command, which reaches this script through the playbook from any worktree,
#   p="$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook" &&
#   head=$("$p/scripts/squad-merge-gate.sh" <pr>) && gh pr merge <pr> --squash --match-head-commit "$head"
# cannot merge over an open thread, a stale verdict, a missing label, an unsettled body-only
# finding, a red or absent CI, or a head that moved between the check and the merge. When the PR is
# behind its base, it says what the base changed since (agent-squad #64), and stops when the base
# changed a file the PR changes too, until the author acknowledges that base with
# SQUAD_BEHIND_CHECKED (agent-squad #80).
#
# Usage: [SQUAD_BEHIND_CHECKED=<base sha>] squad-merge-gate.sh <pr-number> [owner/repo]
# Exit: 0 may be merged; 1 a condition failed; 2 bad usage; 3 behind a base that changed a file the
#       PR changes too, and not acknowledged for that base.
set -u
pr="${1:-}"
case "$pr" in ""|*[!0-9]*) echo "gate: usage: $0 <pr-number> [owner/repo]" >&2; exit 2 ;; esac
repo="${2:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
owner="${repo%%/*}"; name="${repo##*/}"
fail() { echo "gate FAILED: $*" >&2; exit 1; }

head="$(gh api "repos/$repo/pulls/$pr" --jq .head.sha 2>/dev/null)" || fail "cannot read PR #$pr"

# 1. The latest review that contains a QA-VERDICT line says APPROVED and is bound to the head.
#    --slurp joins the pages before jq runs (gh cannot combine --slurp with --jq); inline replies create empty reviews.
verdict="$(gh api --paginate --slurp "repos/$repo/pulls/$pr/reviews" \
  | jq -r '[add[] | select(.body | test("QA-VERDICT: "))] | last // empty | "\(.commit_id) \(.body | split("\n") | map(select(test("QA-VERDICT: "))) | last)"')"
[ -n "$verdict" ] || fail "no QA-VERDICT review yet"
case "$verdict" in
  "$head QA-VERDICT: APPROVED") ;;
  "$head "*) fail "latest verdict on the head is not APPROVED: ${verdict#* }" ;;
  *) fail "latest verdict is bound to ${verdict%% *}, not to the head $head" ;;
esac

# 2. Zero unresolved review threads.
open_threads="$(gh api graphql -f query="{repository(owner:\"$owner\",name:\"$name\"){pullRequest(number:$pr){reviewThreads(first:100){nodes{isResolved}}}}}" \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length')"
[ "$open_threads" = "0" ] || fail "$open_threads unresolved review thread(s)"

# 3. Every body-only finding (a QA PR comment whose first line carries a priority tag) is settled.
unsettled="$(gh api --paginate --slurp "repos/$repo/issues/$pr/comments" \
  | jq -r '[add[] | select((.body | split("\n") | first | test("^👩🏼‍🔬\\[QA\\]: \\S+ \\[P[123]\\]")) and (.body | test("\nSettled: ") | not))] | length')"
[ "$unsettled" = "0" ] || fail "$unsettled body-only finding(s) without a Settled: line"

# 4. The PR carries the approved status label, and no other of the three state labels: with two, a
#    reader cannot tell which is current (agent-squad #99).
states="$(gh api "repos/$repo/pulls/$pr" \
  --jq '[.labels[].name | select(test("status:(in-review|in-progress|approved)$"))] | "\(length)\t\(join(", "))"')" \
  || fail "cannot read the labels of PR #$pr"
case "${states%%$'\t'*}" in
  0|1) ;;
  *) fail "PR carries ${states%%$'\t'*} state labels, where one is the rule: ${states#*$'\t'}. Keep only the current one (✅ status:approved, if QA approved the head) and remove the others" ;;
esac
case ", ${states#*$'\t'}, " in
  *", ✅ status:approved, "*) ;;
  *) fail "PR does not carry ✅ status:approved" ;;
esac

# 5. CI ran on the head and every check run succeeded; no runs at all is not green.
runs="$(gh api "repos/$repo/commits/$head/check-runs" --jq '"\(.check_runs | length) \([.check_runs[] | select(.conclusion != "success")] | length)"')"
total="${runs%% *}"; not_green="${runs##* }"
[ "$total" != "0" ] || fail "no check runs on $head"
[ "$not_green" = "0" ] || fail "$not_green of $total check run(s) not successful on $head"

# 6. A verdict binds to a commit, but what a PR says binds to the world, and the base may have moved
#    under it since it was approved (agent-squad #57). When the PR is behind its base, say by how
#    many commits and which files they touched, marking those the PR also changes or names in its
#    description. If none is one the PR changes, that is a warning. If one is, the gate stops with
#    exit 3, since a warning inside §4.9's chained command is read only after the merge
#    (agent-squad #80): the author checks the PR's claims against that base and acknowledges it with
#    SQUAD_BEHIND_CHECKED=<its SHA>, which counts for that base and no other. When the gate cannot
#    tell whether the base moved, it stops the same way: a gate that passes when it cannot see is
#    the failure agent-squad #80 is about.
# `names_it <file>` passes when the PR's description names the file: its path or its base name in
# backticks, or as a whole word when the name is distinctive enough to be one (it has a dot or a
# slash). A bare word such as `a` is not taken for a file.
names_it() {
  local base="${1##*/}" name
  for name in "$1" "$base"; do
    grep -qF -- "\`$name\`" <<<"$body" && return 0
    case "$name" in
      *.*|*/*) grep -qwF -- "$name" <<<"$body" && return 0 ;;
    esac
  done
  return 1
}
# `acknowledges <sha>` passes when SQUAD_BEHIND_CHECKED names that commit: its full SHA, or a
# prefix of 7 or more of its lowercase hex digits.
acknowledges() {
  local acknowledged="${SQUAD_BEHIND_CHECKED:-}"
  [ -n "$1" ] && [ "${#acknowledged}" -ge 7 ] && [ -z "${acknowledged//[0-9a-f]/}" ] \
    && [ "${1#"$acknowledged"}" != "$1" ]
}
# `cannot_tell <why>` answers when the gate cannot see whether the base moved under the PR: an
# acknowledgement of the base after a manual comparison lets it pass; anything else stops it.
cannot_tell() {
  if acknowledges "$base_sha"; then
    echo "gate note: $1, and PR #$pr was checked by hand against $base at ${base_sha:0:7} (SQUAD_BEHIND_CHECKED)" >&2
  elif [ -n "$base_sha" ]; then
    echo "gate FAILED: cannot tell whether PR #$pr is behind $base: $1. Compare them by hand: if the PR's claims hold, merge again with SQUAD_BEHIND_CHECKED=$base_sha in front of the command." >&2
    exit 3
  else
    echo "gate FAILED: cannot tell whether PR #$pr is behind its base: its tip could not be read. Run the gate again." >&2
    exit 3
  fi
}
# `read_pr_files` prints every name the PR's files go by, and fails when GitHub does not list them.
read_pr_files() {
  local pages
  pages="$(gh api --paginate --slurp "repos/$repo/pulls/$pr/files" 2>/dev/null)" \
    && jq -r 'add[] | .filename, (.previous_filename // empty)' <<<"$pages" 2>/dev/null
}
# The base's tip is read first and compared by SHA, so that the count, the files and the SHA an
# acknowledgement must match all describe one base. A renamed file counts under both of its names,
# on either side: GitHub lists it under the new one, with the old one as previous_filename.
base="$(gh api "repos/$repo/pulls/$pr" --jq .base.ref 2>/dev/null)"
base_sha=""
[ -z "$base" ] || base_sha="$(gh api "repos/$repo/commits/$base" --jq .sha 2>/dev/null)"
behind=""
if [ -n "$base_sha" ] && compare="$(gh api "repos/$repo/compare/$head...$base_sha" \
  --jq '{ahead_by, count: (.files | length), files: [.files[] | .filename, (.previous_filename // empty)]}' 2>/dev/null)"; then
  behind="$(jq -r '.ahead_by // empty' <<<"$compare" 2>/dev/null)"
fi
# No overlap means something only when both lists are complete: GitHub lists at most 300 files in
# a comparison, and a PR changes at least one file.
case "$behind" in
  ''|*[!0-9]*) cannot_tell "GitHub did not compare the PR with $base" ;;
  0) ;;
  *)
    if [ "$(jq -r '.count' <<<"$compare")" -ge 300 ]; then
      cannot_tell "GitHub listed its maximum of 300 files changed on $base, which may not be all of them"
    elif ! pr_files="$(read_pr_files)" || [ -z "$pr_files" ]; then
      cannot_tell "GitHub did not list the files the PR changes"
    else
      body="$(gh api "repos/$repo/pulls/$pr" --jq '.body // ""' 2>/dev/null)"
      echo "gate WARNING: PR #$pr is behind $base by $behind commit(s), which changed since the merge base:" >&2
      jq -r '.files[]' <<<"$compare" | while IFS= read -r file; do
        if grep -qxF -- "$file" <<<"$pr_files"; then
          echo "  $file (the PR changes it too)"
        elif names_it "$file"; then
          echo "  $file (the PR's description names it)"
        else
          echo "  $file"
        fi
      done >&2
      in_common="$(jq -r '.files[]' <<<"$compare" | grep -xF -f <(printf '%s\n' "$pr_files"))"
      if [ -z "$in_common" ]; then
        echo "  Before merging, check the PR's claims against $base; if one no longer holds, merge $base in and fix it, which takes a new verdict." >&2
      elif acknowledges "$base_sha"; then
        echo "gate note: PR #$pr changes files that $base changed too, and was checked against $base at ${base_sha:0:7} (SQUAD_BEHIND_CHECKED)" >&2
      else
        echo "gate FAILED: PR #$pr is behind $base, which changed files the PR changes too. Check the PR's claims against $base at $base_sha: if they hold, merge again with SQUAD_BEHIND_CHECKED=$base_sha in front of the command; if one no longer holds, merge $base in and fix it, which takes a new verdict." >&2
        exit 3
      fi
    fi
    ;;
esac

echo "gate OK: PR #$pr at $head may be merged" >&2
echo "$head"
