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
# The command keeps this script's input, output and error output, and this script's process group,
# so that a terminal it reads stays its own. Past the bound it gets SIGTERM, with every process it
# started, and those still running two seconds later get SIGKILL (agent-squad #439). Interrupted,
# this script stops them first.
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

# `family <pid>` prints the PIDs of every process that one started, deepest first, then its own, as
# pgrep finds them: git's ssh transport, for one, outlives git when git alone is stopped. Without
# pgrep, it prints <pid> alone. `alive <pid>...` passes while one of them still runs.
family() {
  local child
  for child in $(pgrep -P "$1"); do family "$child"; done
  echo "$1"
}
alive() {
  local one
  for one; do kill -0 "$one" && return 0; done
  return 1
}

# The watcher, in the background, reads the wall clock, as $SECONDS counts it, every tenth of a
# second. Once the bound has passed, it stops the command and what it started, listed first, since
# a process whose parent has ended is no longer found under it: SIGTERM, then SIGKILL to those still
# running two seconds after it, counted from the SIGTERM, since after a sleep past the bound the
# time since the start has used them up. It holds none of this script's output, which a caller may
# be reading to its end.
watch() {
  local stopping
  while [ $((SECONDS - started)) -le "$bound" ]; do sleep 0.1; done
  stopping="$(family "$pid")"
  # shellcheck disable=SC2086 # the PIDs are split on purpose, one argument each
  kill -TERM $stopping
  started=$SECONDS
  # shellcheck disable=SC2086 # the same
  while alive $stopping && [ $((SECONDS - started)) -le 2 ]; do sleep 0.1; done
  # shellcheck disable=SC2086 # the same
  kill -KILL $stopping
}
watch </dev/null >/dev/null 3>&- &
watcher=$!
# shellcheck disable=SC2046 # the PIDs are split on purpose, one argument each
trap 'kill $(family "$pid") "$watcher"; exit 130' INT
# shellcheck disable=SC2046 # the same
trap 'kill $(family "$pid") "$watcher"; exit 143' TERM

# The command is waited for itself, so that one that ends at once returns at once. Whether it was
# stopped is read from the same clock as the watcher's, the bound passed by the time it ended (QA's
# finding on PR #442). Then the watcher is still stopping what the command started, and ends once
# that has ended; otherwise it is ended with SIGKILL, which it cannot miss, napping or not.
wait "$pid"
status=$?
if [ $((SECONDS - started)) -gt "$bound" ]; then
  wait "$watcher"
  echo "squad-timeout: $1 did not end within $bound s, so it was stopped" >&3
  exit 124
fi
kill -KILL "$watcher"
exit "$status"
