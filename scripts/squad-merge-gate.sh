#!/usr/bin/env bash
# Merge gate of SQUAD.md §4.9, checked by API. Prints the verified head SHA on stdout and exits 0
# when every condition holds; otherwise prints the reason on stderr and exits non-zero, so that
# SQUAD.md §4.9's command, which reaches this script through the playbook from any worktree,
#   p="$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook" &&
#   head=$("$p/scripts/squad-merge-gate.sh" <pr>) && gh pr merge <pr> --squash --match-head-commit "$head"
# cannot merge over an open thread, a stale verdict, a missing label, an unsettled body-only
# finding, a red or absent CI, or a head that moved between the check and the merge. When the PR is
# behind its base, it also warns, without failing, what the base changed since (#64).
#
# Usage: squad-merge-gate.sh <pr-number> [owner/repo]
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

# 4. The PR carries the approved status label.
labelled="$(gh api "repos/$repo/pulls/$pr" --jq '[.labels[].name] | any(startswith("✅ status:approved"))')"
[ "$labelled" = "true" ] || fail "PR does not carry ✅ status:approved"

# 5. CI ran on the head and every check run succeeded; no runs at all is not green.
runs="$(gh api "repos/$repo/commits/$head/check-runs" --jq '"\(.check_runs | length) \([.check_runs[] | select(.conclusion != "success")] | length)"')"
total="${runs%% *}"; not_green="${runs##* }"
[ "$total" != "0" ] || fail "no check runs on $head"
[ "$not_green" = "0" ] || fail "$not_green of $total check run(s) not successful on $head"

# 6. Not a condition, a warning: a verdict binds to a commit, but what a PR says binds to the
#    world, and the base may have moved under it since it was approved (#57). When the PR is behind
#    its base, say by how many commits and which files they touched, marking those the PR also
#    changes or names in its description; the result of the gate does not change.
base="$(gh api "repos/$repo/pulls/$pr" --jq .base.ref 2>/dev/null)"
if [ -n "$base" ] && compare="$(gh api "repos/$repo/compare/$head...$base" \
  --jq '{ahead_by, files: [.files[].filename]}' 2>/dev/null)"; then
  behind="$(jq -r .ahead_by <<<"$compare")"
  if [ "$behind" -gt 0 ]; then
    pr_files="$(gh api --paginate --slurp "repos/$repo/pulls/$pr/files" 2>/dev/null | jq -r 'add[].filename' 2>/dev/null)"
    body="$(gh api "repos/$repo/pulls/$pr" --jq '.body // ""' 2>/dev/null)"
    echo "gate WARNING: PR #$pr is behind $base by $behind commit(s), which changed since the merge base:" >&2
    jq -r '.files[]' <<<"$compare" | while IFS= read -r file; do
      if grep -qxF -- "$file" <<<"$pr_files"; then
        echo "  $file (the PR changes it too)"
      elif grep -qF -- "$file" <<<"$body" || grep -qF -- "${file##*/}" <<<"$body"; then
        echo "  $file (the PR's description names it)"
      else
        echo "  $file"
      fi
    done >&2
    echo "  Before merging, check the PR's claims against $base; if one no longer holds, merge $base in and fix it, which takes a new verdict." >&2
  fi
else
  echo "gate note: cannot tell whether PR #$pr is behind its base; compare it by hand before merging" >&2
fi

echo "gate OK: PR #$pr at $head may be merged" >&2
echo "$head"
