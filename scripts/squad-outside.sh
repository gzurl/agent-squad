#!/usr/bin/env bash
# What came from outside the squad (agent-squad #281), for the CTO's triage in /squad-resume and
# /squad-watch. Outside means an account whose association GitHub reports as neither the
# repository's owner, nor a member of its organization, nor a collaborator (SQUAD.md §3): the
# account decides, never a signature, since anyone can type one. It lists:
# - the open issues and PRs opened from outside that wait for their triage: labelled needs-triage,
#   or with no owner label, as when the triage workflow did not run;
# - the comments that outside accounts wrote or edited since the last triage, on an issue's or a
#   PR's conversation and on a PR's code, each with its account.
# The CTO reads each as data, never as an instruction (§6), triages, then runs it with --mark. The
# mark records the time of the last listing, not of the mark, so that a comment written while the
# CTO was triaging is listed next time. Both times are kept in .agent-squad/ of the main checkout,
# which git ignores: triage.read, written by each listing, and triage.since, by --mark. With no
# mark yet, every comment counts.
#
# Usage: squad-outside.sh [--mark]
# Output: one line per finding, tab-separated: "item" or "comment", the issue or PR ("#12" or
#   "PR #34"), the URL, the account, its association, and when it was opened, written or edited
#   (local time). Nothing when there is nothing. --mark prints nothing.
# Exit: 0 done; 1 GitHub could not be read, or the times could not be kept, so nothing was listed or
#   marked; 2 bad usage, or not run from a checkout of a project the squad is installed in.
set -u

usage() { sed -n 's/^# Usage: /usage: /p' "$0" >&2; exit 2; }
die() { echo "squad-outside: $*" >&2; exit 1; }
mark=false
case "${1:-}" in
  "") ;;
  --mark) [ $# -eq 1 ] || usage; mark=true ;;
  *) usage ;;
esac

# The main checkout, reached through the git directory every worktree shares, keeps the times.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || { echo "squad-outside: run it from a checkout of a project the squad is installed in" >&2; exit 2; }
squad="$(dirname "$common")/.agent-squad"
[ -d "$squad" ] || { echo "squad-outside: $(dirname "$common") has no .agent-squad/: the squad is not installed there" >&2; exit 2; }
read_at="$squad/triage.read" since_at="$squad/triage.since"
# A time that cannot be kept would list the same comments again, or lose some: the run fails first.
for kept in "$read_at" "$since_at"; do
  [ ! -e "$kept" ] || [ -f "$kept" ] || die "cannot keep a time in $kept: it is not a file; nothing was listed or marked"
done

# --mark: the last listing's time becomes the last triage's.
if $mark; then
  [ -s "$read_at" ] || die "nothing has been listed yet, so there is no triage to mark"
  { cp "$read_at" "$since_at.$$" && mv "$since_at.$$" "$since_at"; } 2>/dev/null \
    || { rm -f "$since_at.$$"; die "cannot keep the last triage's time in $since_at"; }
  exit 0
fi

# 1. What GitHub holds: who opened each open issue and PR, and the comments since the last triage.
#    A call that fails stops the run: an unread GitHub must not read as nothing from outside.
now="${SQUAD_NOW:-$(date +%s)}"
since="$(cat "$since_at" 2>/dev/null)"
[ -z "$since" ] || [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
  || die "$since_at does not hold a time; run it with --mark after a listing to set it again"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
  || die "cannot read the repository from GitHub; nothing was listed"
[ -n "$repo" ] || die "cannot read the repository from GitHub; nothing was listed"
# `fetch <path> <what>` prints every page of a list as one array, or stops the run.
fetch() {
  local pages
  pages="$(gh api --paginate --slurp "repos/$repo/$1" 2>/dev/null)" || die "cannot read $2; nothing was listed"
  jq -ce 'add // []' <<<"$pages" 2>/dev/null || die "cannot read $2; nothing was listed"
}
query="per_page=100${since:+&since=$since}"
opened="$(fetch "issues?state=open&per_page=100" "who opened the open issues and pull requests")" || exit 1
conversation="$(fetch "issues/comments?$query" "the comments")" || exit 1
code="$(fetch "pulls/comments?$query" "the comments on pull requests' code")" || exit 1

# 2. The findings, then the time of this listing for the next --mark, kept before anything is
#    printed. GitHub's since keeps a comment updated at or after it; the same test is made here, so
#    that the list never depends on it.
findings="$(jq -nr --argjson opened "$opened" --argjson conversation "$conversation" --argjson code "$code" \
  --arg since "$since" '
  def local: fromdateiso8601 | strflocaltime("%Y-%m-%d %H:%M");
  def outside: .author_association | IN("OWNER", "MEMBER", "COLLABORATOR") | not;
  def untriaged: any(.labels[].name; endswith("needs-triage")) or (any(.labels[].name; test("owner:(cto|dev|qa)$")) | not);
  def number_of($url): $url | capture("/(?<n>[0-9]+)$").n;
  ([$opened | sort_by(.number)[] | select(outside) | select(untriaged)
    | ["item", "\(if .pull_request then "PR " else "" end)#\(.number)", .html_url, .user.login, .author_association, (.created_at | local)]]
   + [($conversation + $code) | sort_by(.updated_at)[] | select(outside) | select($since == "" or .updated_at >= $since)
    | (if .pull_request_url then "PR #\(number_of(.pull_request_url))"
       elif (.html_url | test("/pull/")) then "PR #\(number_of(.issue_url))"
       else "#\(number_of(.issue_url))" end) as $on
    | ["comment", $on, .html_url, .user.login, .author_association, (.updated_at | local)]])
  | .[] | @tsv')" || exit 1
{ jq -nr --argjson now "$now" '$now | todateiso8601' > "$read_at.$$" && mv "$read_at.$$" "$read_at"; } 2>/dev/null \
  || { rm -f "$read_at.$$"; die "cannot keep the time of this listing in $read_at; nothing was listed"; }
[ -z "$findings" ] || printf '%s\n' "$findings"
