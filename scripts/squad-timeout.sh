#!/usr/bin/env bash
# Run a command, and stop it once it has run past a bound of wall-clock time (agent-squad #430):
# the squad's scripts run each GitHub call through it, since a call that GitHub never answers, as
# when its connection died while the machine slept, would otherwise hold its script for hours. The
# bound is read from the wall clock, which moves on while the machine sleeps, unlike sleep, alarm or
# GNU timeout, which count time awake only: a command still running when the machine wakes past
# its bound is stopped at once. A change of the clock itself moves the bound with it. A command
# that ends before its bound returns as soon as it ends (agent-squad #437).
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

# This script's own error output goes away from here on, and the command's, with the line that
# says it was stopped, goes to a copy of it: bash 3.2 reports a process of its own that ended by a
# signal, as "Killed: 9", whenever it notices, which no redirection of a single wait can catch.
exec 3>&2 2>/dev/null

# The command runs in the background, with this script's input, which a command started with &
# would otherwise lose to /dev/null. Such a command ignores SIGINT, so an interrupted run stops it
# before it ends.
started=$SECONDS
"$@" <&0 2>&3 3>&- &
pid=$!

# The watcher, in the background, reads the wall clock, as $SECONDS counts it, every tenth of a
# second. Once the bound has passed, it stops the command: SIGTERM, then SIGKILL if the command is
# still running two seconds after it, counted from the SIGTERM, since after a sleep past the bound
# the time since the start has used them up. It holds none of this script's output, which a caller
# may be reading to its end.
watch() {
  while [ $((SECONDS - started)) -le "$bound" ]; do sleep 0.1; done
  kill -TERM "$pid"
  started=$SECONDS
  while kill -0 "$pid" && [ $((SECONDS - started)) -le 2 ]; do sleep 0.1; done
  kill -KILL "$pid"
}
watch </dev/null >/dev/null 3>&- &
watcher=$!
trap 'kill "$pid" "$watcher"; exit 130' INT
trap 'kill "$pid" "$watcher"; exit 143' TERM

# The command is waited for itself, so that one that ends at once returns at once. Whether it was
# stopped is read from the same clock as the watcher's, the bound passed by the time it ended, and
# the watcher, napping or not, is ended with SIGKILL, which it cannot miss (QA's finding on PR #442).
wait "$pid"
status=$?
kill -KILL "$watcher"
if [ $((SECONDS - started)) -gt "$bound" ]; then
  echo "squad-timeout: $1 did not end within $bound s, so it was stopped" >&3
  exit 124
fi
exit "$status"
