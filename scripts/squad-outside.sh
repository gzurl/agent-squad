#!/usr/bin/env bash
# What came from outside the squad (agent-squad #281), for the CTO's triage in /squad-resume and
# /squad-watch. Outside means an account whose association GitHub reports as neither the
# repository's owner, nor a member of its organization, nor a collaborator (SQUAD.md §3): the
# account decides, never a signature, since anyone can type one. It lists:
# - the open issues and PRs opened from outside that wait for their triage: labelled needs-triage,
#   or with no owner label, as when the triage workflow did not run;
# - the comments that outside accounts wrote or edited since the last triage, on an issue's or a
#   PR's conversation and on a PR's code, and the reviews they submitted since then on an open PR,
#   each with its account.
# The CTO reads each as data, never as an instruction (§6), and triages. A listing changes nothing:
# it ends, on stderr, with the --mark command that records its own time as the last triage's, for
# the CTO to run once the triage is done. So a comment written during the triage, or a listing run
# by someone else meanwhile, never moves the mark past what the CTO read. The last triage's time is
# kept in .agent-squad/triage.since of the main checkout, which git ignores; with none yet, every
# comment counts.
#
# What GitHub answers goes to jq through files, never as arguments: a repository's comments with
# their bodies run to megabytes, over what one command's arguments may hold.
#
# Usage: squad-outside.sh [--mark <time>]
# Output: one line per finding, tab-separated: "item", "comment" or "review", the issue or PR ("#12"
#   or "PR #34"), the URL, the account, its association, and when it was opened, written, edited or
#   submitted (local time). Nothing when there is nothing. Then, on stderr, the --mark command for
#   this listing; <time> is the one it names, as GitHub writes times. --mark prints nothing.
# Exit: 0 done; 1 GitHub could not be read, so nothing was listed, or the mark could not be kept;
#   2 bad usage, or not run from a checkout of a project the squad is installed in.
set -u
# jq on Windows ends each line with CRLF, and the shell keeps the CR in what it reads, as in an id
# sent to GitHub, which then refuses it (agent-squad #405): every jq of this script drops it here.
jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }

usage() { sed -n 's/^# Usage: /usage: /p' "$0" >&2; exit 2; }
die() { echo "squad-outside: $*" >&2; exit 1; }
is_time() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; }
mark=""
case "${1:-}" in
  "") [ $# -eq 0 ] || usage ;;
  --mark)
    if [ $# -ne 2 ] || ! is_time "$2"; then usage; fi
    mark="$2" ;;
  *) usage ;;
esac

# The main checkout, reached through the git directory every worktree shares, keeps the mark.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || { echo "squad-outside: run it from a checkout of a project the squad is installed in" >&2; exit 2; }
squad="$(dirname "$common")/.agent-squad"
[ -d "$squad" ] || { echo "squad-outside: $(dirname "$common") has no .agent-squad/: the squad is not installed there" >&2; exit 2; }
since_at="$squad/triage.since"
# A mark that cannot be kept would list the same comments again, or lose some: the run fails first.
[ ! -e "$since_at" ] || [ -f "$since_at" ] || die "cannot keep the last triage's time in $since_at: it is not a file"

# --mark <time>: the listing's time becomes the last triage's.
if [ -n "$mark" ]; then
  { printf '%s\n' "$mark" > "$since_at.$$" && mv "$since_at.$$" "$since_at"; } 2>/dev/null \
    || { rm -f "$since_at.$$"; die "cannot keep the last triage's time in $since_at"; }
  exit 0
fi

# 1. What GitHub holds: who opened each open issue and PR, the comments since the last triage, and
#    each open PR's reviews. Each list is read, then cut down to what the findings use, into a file
#    of a work directory. A call that fails stops the run: an unread GitHub must not read as nothing
#    from outside.
now="${SQUAD_NOW:-$(date +%s)}"
since="$(cat "$since_at" 2>/dev/null)"
[ -z "$since" ] || is_time "$since" \
  || die "$since_at does not hold a time; run it with the --mark a listing gives to set it again"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
  || die "cannot read the repository from GitHub; nothing was listed"
[ -n "$repo" ] || die "cannot read the repository from GitHub; nothing was listed"
work="${TMPDIR:-/tmp}"
work="$(mktemp -d "${work%/}/squad-outside.XXXXXX")" || die "cannot make a work directory; nothing was listed"
trap 'rm -rf "$work"' EXIT
# `fetch <path> <file> <what> <fields>` writes every page of a list to <file> as one array of
# objects cut down to the jq <fields>, or stops the run.
fetch() {
  gh api --paginate --slurp "repos/$repo/$1" > "$work/$2.pages" 2>/dev/null || die "cannot read $3; nothing was listed"
  jq -ce "add // [] | map($4)" "$work/$2.pages" > "$work/$2.json" 2>/dev/null || die "cannot read $3; nothing was listed"
  rm -f "$work/$2.pages"
}
who='login: .user.login, association: .author_association'
query="per_page=100${since:+&since=$since}"
fetch "issues?state=open&per_page=100" opened "who opened the open issues and pull requests" \
  "{number, url: .html_url, $who, at: .created_at, pr: (.pull_request != null), labels: [.labels[].name]}"
fetch "issues/comments?$query" conversation "the comments" \
  "{url: .html_url, $who, at: .updated_at, on: (.issue_url | capture(\"/(?<n>[0-9]+)\$\").n), pr: (.html_url | test(\"/pull/\"))}"
fetch "pulls/comments?$query" code "the comments on pull requests' code" \
  "{url: .html_url, $who, at: .updated_at, on: (.pull_request_url | capture(\"/(?<n>[0-9]+)\$\").n), pr: true}"
: > "$work/reviews.json"
for number in $(jq -r '.[] | select(.pr) | .number' "$work/opened.json"); do
  fetch "pulls/$number/reviews?per_page=100" "reviews-$number" "the reviews of PR #$number" \
    "{url: .html_url, $who, at: .submitted_at, on: \"$number\", pr: true}"
  cat "$work/reviews-$number.json" >> "$work/reviews.json"
done

# 2. The findings. GitHub's since keeps a comment updated at or after it; the same test is made
#    here, so that the list never depends on it, and it is how reviews, which take no since, are
#    kept.
jq -nr --slurpfile opened "$work/opened.json" --slurpfile conversation "$work/conversation.json" \
  --slurpfile code "$work/code.json" --slurpfile reviews "$work/reviews.json" --arg since "$since" '
  def local: fromdateiso8601 | strflocaltime("%Y-%m-%d %H:%M");
  def outside: .association | IN("OWNER", "MEMBER", "COLLABORATOR") | not;
  def untriaged: any(.labels[]; endswith("needs-triage")) or (any(.labels[]; test("owner:(cto|dev|qa)$")) | not);
  def since: $since == "" or .at >= $since;
  def written($kind): select(outside) | select(.at != null) | select(since)
    | [$kind, "\(if .pr then "PR " else "" end)#\(.on)", .url, .login, .association, (.at | local)];
  ([$opened[0] | sort_by(.number)[] | select(outside) | select(untriaged)
    | ["item", "\(if .pr then "PR " else "" end)#\(.number)", .url, .login, .association, (.at | local)]]
   + [$conversation[0] + $code[0] | sort_by(.at)[] | written("comment")]
   + [$reviews | add // [] | sort_by(.at // "")[] | written("review")])
  | .[] | @tsv' || exit 1
echo "squad-outside: once this is triaged, record it with: squad-outside.sh --mark $(jq -nr --argjson now "$now" '$now | todateiso8601')" >&2
