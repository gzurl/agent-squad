#!/usr/bin/env bash
# Merge gate of SQUAD.md §4.9, checked by API. Exits non-zero on the first failed condition, so
# that `scripts/squad-merge-gate.sh <pr> && gh pr merge <pr> --squash` cannot merge over an open
# thread, a stale verdict, a missing label, an unsettled body-only finding or a red CI.
#
# Usage: scripts/squad-merge-gate.sh <pr-number> [owner/repo]
set -u
pr="${1:?usage: $0 <pr-number> [owner/repo]}"
case "$pr" in *[!0-9]*|"") echo "gate: PR number must be a plain integer"; exit 2 ;; esac
repo="${2:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
owner="${repo%%/*}"; name="${repo##*/}"
fail() { echo "gate FAILED: $*"; exit 1; }

head="$(gh api "repos/$repo/pulls/$pr" --jq .head.sha)" || fail "cannot read PR #$pr"

# 1. The latest review that contains a QA-VERDICT line says APPROVED and is bound to the head.
verdict="$(gh api --paginate "repos/$repo/pulls/$pr/reviews" \
  --jq '[.[] | select(.body | test("QA-VERDICT: "))] | last | "\(.commit_id) \(.body | split("\n") | map(select(test("QA-VERDICT: "))) | last)"')"
[ -n "$verdict" ] && [ "$verdict" != "null null" ] || fail "no QA-VERDICT review yet"
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
unsettled="$(gh api --paginate "repos/$repo/issues/$pr/comments" \
  --jq '[.[] | select((.body | split("\n") | first | test("^👩🏼‍🔬\\[QA\\]: \\S+ \\[P[123]\\]")) and (.body | test("\nSettled: ") | not))] | length')"
[ "$unsettled" = "0" ] || fail "$unsettled body-only finding(s) without a Settled: line"

# 4. The PR carries the approved status label.
gh api "repos/$repo/pulls/$pr" --jq '[.labels[].name] | any(startswith("✅ status:approved"))' | grep -q true \
  || fail "PR does not carry ✅ status:approved"

# 5. CI is green on the head (no failed or pending check runs).
not_green="$(gh api "repos/$repo/commits/$head/check-runs" --jq '[.check_runs[] | select(.conclusion != "success")] | length')"
[ "$not_green" = "0" ] || fail "$not_green check run(s) not successful on $head"

echo "gate OK: PR #$pr at ${head:0:7} may be merged"
