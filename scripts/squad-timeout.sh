#!/usr/bin/env bash
# Run a command, and stop it once it has run past a bound of wall-clock time (agent-squad #430):
# the squad's scripts run each GitHub call through it, since a call that GitHub never answers, as
# when its connection died while the machine slept, would otherwise hold its script for hours. The
# bound is read from the wall clock, which moves on while the machine sleeps, unlike sleep, alarm or
# GNU timeout, which count time awake only: a command still running when the machine wakes past
# its bound is stopped at once. A change of the clock itself moves the bound with it.
#
# Usage: squad-timeout.sh <seconds> <command> [<argument>...]
# The command keeps this script's input, output and error output. Past the bound it gets SIGTERM,
# and SIGKILL if it is still running two seconds later; it is the command that is stopped, not
# processes it started. Interrupted, this script stops the command first.
# Exit: the command's own; 124 when it was stopped, as GNU timeout's, after a line on stderr that
#   says so; 2 bad usage.
set -u
usage="usage: squad-timeout.sh <seconds> <command> [<argument>...]"
if [ $# -lt 2 ] || ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then echo "$usage" >&2; exit 2; fi
bound="$1"
shift

# The command runs in the background, with this script's input, which a command started with &
# would otherwise lose to /dev/null. Such a command ignores SIGINT, so an interrupted run stops it
# before it ends.
started=$SECONDS
"$@" <&0 &
pid=$!
trap 'kill "$pid" 2>/dev/null; exit 130' INT
trap 'kill "$pid" 2>/dev/null; exit 143' TERM

# `ended_within <seconds>` waits until the command ends, and fails once <seconds> have passed since
# the start: it reads the wall clock, as $SECONDS counts it, every tenth of a second.
ended_within() {
  while kill -0 "$pid" 2>/dev/null; do
    [ $((SECONDS - started)) -le "$1" ] || return 1
    sleep 0.1
  done
}
if ended_within "$bound"; then
  wait "$pid"
  exit
fi
kill -TERM "$pid" 2>/dev/null
ended_within $((bound + 2)) || kill -KILL "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
echo "squad-timeout: $1 did not end within $bound s, so it was stopped" >&2
exit 124
