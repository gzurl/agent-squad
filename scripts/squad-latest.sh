#!/usr/bin/env bash
# Find the latest agent-squad release, at every session start and at most once a day otherwise, for
# the squad board's notice (agent-squad #302, #336). It asks GitHub for the upstream's latest Release with gh, and writes the answer into the
# main checkout's .agent-squad/latest-release, which the three sessions share and the board reads
# (#244):
#   {"tag": "v50", "checkedAt": 1760263200, "attemptedAt": 1760263200}
# tag is the latest Release's tag as of the last check that worked, null before the first one;
# checkedAt is when that check worked, and attemptedAt when the last attempt was made, in seconds
# since the epoch. A check is due 24 hours after the last one that worked, and, after a failure, an
# hour after the last attempt, so an offline machine asks once an hour at most. A time later than
# now counts as never, so that a clock that ran ahead cannot hold the check back (agent-squad
# #309). The attempt is written down before GitHub is asked, so a session that starts while a
# check is under way asks nothing; sessions that start at the very same instant may each ask once,
# which is harmless. A session start does not wait for a check to be due: it asks with --now. Nothing
# is sent: it is a read of a public repository's latest Release. The upstream is the one on the
# upstream= line of the squad-install.sh beside this script, as /squad-upgrade reads it.
#
# Usage: squad-latest.sh [--due | --now] <main checkout>
#   --due  only tell whether a check is due: exit 0 if it is, 1 if not; nothing is asked or written.
#   --now  check whatever the last check's age, even right after a failed attempt, as a session
#          start does (agent-squad #336).
# Run by the session hooks (squad-handoff.sh) and by /squad-resume and /squad-watch. Without --due
# it prints one line on what it knows, and exits 0 whatever GitHub answers; 2 is bad usage.
# SQUAD_LATEST_TIMEOUT is how long gh may take, in seconds (10 when unset).
set -u
usage="usage: squad-latest.sh [--due | --now] <main checkout>"
due_only=false always=false
case "${1:-}" in
  --due) due_only=true; shift ;;
  --now) always=true; shift ;;
esac
if [ $# -ne 1 ] || [ ! -d "$1/.agent-squad" ]; then echo "$usage" >&2; exit 2; fi
file="$1/.agent-squad/latest-release"
day=86400 hour=3600
timeout="${SQUAD_LATEST_TIMEOUT:-10}"
[[ "$timeout" =~ ^[1-9][0-9]*$ ]] || timeout=10

# What the file holds: the tag, and when it was checked and attempted, 0 for never. A file that is
# missing or not this shape counts as no check at all.
known="$(jq -c -s 'if length == 1 and (.[0] | type) == "object" then .[0]
    | {tag: (if (.tag | type) == "string" and (.tag | test("^v[0-9]+$")) then .tag else null end),
       checkedAt: (if (.checkedAt | type) == "number" then .checkedAt | floor else 0 end),
       attemptedAt: (if (.attemptedAt | type) == "number" then .attemptedAt | floor else 0 end)}
  else empty end' "$file" 2>/dev/null)"
[ -n "$known" ] || known='{"tag": null, "checkedAt": 0, "attemptedAt": 0}'
tag="$(jq -r '.tag // ""' <<<"$known")"
checked="$(jq -r '.checkedAt' <<<"$known")"
attempted="$(jq -r '.attemptedAt' <<<"$known")"
now="$(date +%s)"
[ "$checked" -le "$now" ] || checked=0
[ "$attempted" -le "$now" ] || attempted=0
is_due=false
[ $((now - checked)) -lt "$day" ] || [ $((now - attempted)) -lt "$hour" ] || is_due=true
if $due_only; then $is_due; exit; fi
! $always || is_due=true

# `write <tag> <checkedAt> <attemptedAt>` replaces the file whole, through a temporary file.
write() {
  if ! { jq -cn --arg tag "$1" --argjson checked "$2" --argjson attempted "$3" \
      '{tag: (if $tag == "" then null else $tag end), checkedAt: $checked, attemptedAt: $attempted}' \
      > "$file.$$" && mv "$file.$$" "$file"; } 2>/dev/null; then
    rm -f "$file.$$"
  fi
}
# `hours_since <time>` is how many whole hours have passed since then.
hours_since() { echo $(((now - $1) / hour)); }

if ! $is_due; then
  if [ -n "$tag" ]; then
    echo "latest release: $tag, checked $(hours_since "$checked") h ago"
  else
    echo "latest release: not known yet; GitHub was asked $(hours_since "$attempted") h ago"
  fi
  exit 0
fi

# The check: the attempt first, then gh, which gets `timeout` seconds before it is stopped.
write "$tag" "$checked" "$now"
upstream="$(sed -n 's/^upstream="\([^"]*\)"$/\1/p' "$(dirname "$0")/squad-install.sh" 2>/dev/null | head -n 1)"
if ! [[ "$upstream" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "latest release: cannot tell the upstream from $(dirname "$0")/squad-install.sh; not checked"
  exit 0
fi
answer="$file.answer.$$"
gh api "repos/$upstream/releases/latest" --jq .tag_name </dev/null >"$answer" 2>/dev/null &
pid=$!
waited=0
while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt $((timeout * 10)) ]; do
  sleep 0.1
  waited=$((waited + 1))
done
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  latest=""
elif wait "$pid"; then
  latest="$(head -n 1 "$answer")"
else
  latest=""
fi
rm -f "$answer"
if [[ "$latest" =~ ^v[0-9]+$ ]]; then
  write "$latest" "$now" "$now"
  echo "latest release: $latest, checked now"
else
  echo "latest release: GitHub did not tell it; the next attempt is in an hour"
fi
