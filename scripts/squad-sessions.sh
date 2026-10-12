#!/usr/bin/env bash
# Name the squad's sessions that still run an older release than the one installed (agent-squad
# #361), for /squad-upgrade and /squad-resume. Each session's board writes its record in the main
# checkout's .agent-squad/sessions/<role>.json whenever it publishes its state: its name, the
# release its code loaded, and the time, in milliseconds since the epoch:
#   {"name": "DEV:proj", "sessionId": "…", "release": "v53", "at": 1791827603871}
# A session's hooks cannot tell the release it runs: a /clear starts a session with no reload of
# its code. The installed release is the major version of the board's plugin.json in the playbook,
# as the band reads it. Nothing is asked of GitHub or of the sessions.
#
# Usage: squad-sessions.sh <main checkout>
# Output: one line per role, in the order CTO, DEV, QA, then the roles to restart:
#   sessions: DEV  DEV:proj runs v53, the installed release
#   sessions: DEV  DEV:proj runs v50, older than the installed v53: /restart it
#   sessions: DEV  DEV:proj ran v50 until 12 min ago, older than the installed v53: /restart it if it is open
#   sessions: DEV  no record: no session of this role runs a board that writes one; /restart it if it is open
#   sessions: to restart: DEV
#   sessions: to restart if open: QA
# or, when none is older, "sessions: every open session runs v53".
# A session counts as open while its record is younger than three minutes, as the band's do.
# Exit: 0, whatever it finds; 2 bad usage.
set -u
usage="usage: squad-sessions.sh <main checkout>"
if [ $# -ne 1 ] || [ ! -d "$1/.agent-squad" ]; then echo "$usage" >&2; exit 2; fi
squad="$1/.agent-squad"
stale_ms=180000

# The installed release's number, from the playbook's board; empty when it cannot be read.
manifest="$squad/playbook/mods/squad-board/.claude-plugin/plugin.json"
installed="$(jq -r '.version // "" | capture("^(?<major>[0-9]+)[.]").major // ""' "$manifest" 2>/dev/null)"
if [ -z "$installed" ]; then
  echo "sessions: the installed release cannot be read from ${manifest#"$1/"}; nothing compared"
fi
now_ms=$(($(date +%s) * 1000))

to_restart=() if_open=()
for role in CTO DEV QA; do
  # The record: its name, its release's number, and how long ago it was written; nothing for a
  # record that is missing, or not that shape.
  record="$(jq -r 'select((.name | type) == "string" and (.release | type) == "string" and (.release | test("^v[0-9]+$"))
      and (.at | type) == "number") | [.name, (.release | ltrimstr("v")), (.at | floor | tostring)] | join("\t")' \
    "$squad/sessions/$role.json" 2>/dev/null)"
  if [ -z "$record" ]; then
    echo "sessions: $role  no record: no session of this role runs a board that writes one; /restart it if it is open"
    if_open+=("$role")
    continue
  fi
  IFS=$'\t' read -r name loaded at <<<"$record"
  age=$((now_ms - at))
  if [ -z "$installed" ]; then
    echo "sessions: $role  $name runs v$loaded"
  elif [ "$age" -le "$stale_ms" ] && [ "$loaded" -lt "$installed" ]; then
    echo "sessions: $role  $name runs v$loaded, older than the installed v$installed: /restart it"
    to_restart+=("$role")
  elif [ "$age" -le "$stale_ms" ]; then
    echo "sessions: $role  $name runs v$loaded, the installed release"
  elif [ "$loaded" -lt "$installed" ]; then
    echo "sessions: $role  $name ran v$loaded until $((age / 60000)) min ago, older than the installed v$installed: /restart it if it is open"
    if_open+=("$role")
  else
    echo "sessions: $role  $name ran v$loaded until $((age / 60000)) min ago, the installed release"
  fi
done

# The roles to restart, which the commands name to the CEO.
[ -n "$installed" ] || exit 0
[ "${#to_restart[@]}" -eq 0 ] || echo "sessions: to restart: ${to_restart[*]}"
[ "${#if_open[@]}" -eq 0 ] || echo "sessions: to restart if open: ${if_open[*]}"
[ "${#to_restart[@]}" -gt 0 ] || [ "${#if_open[@]}" -gt 0 ] || echo "sessions: every open session runs v$installed"
exit 0
