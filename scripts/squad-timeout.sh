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

# The command runs in the background, with this script's input, which a command started with &
# would otherwise lose to /dev/null. Such a command ignores SIGINT, so an interrupted run stops it
# before it ends.
started=$SECONDS
"$@" <&0 &
pid=$!

# The watcher, in the background, reads the wall clock, as $SECONDS counts it, every tenth of a
# second. Once the bound has passed, it stops the command, and exits 0. Told by SIGUSR1 that the
# command ended first, it exits 1, at once: its naps run in the background, so that a signal cuts
# one short. It holds none of this script's output, which a caller may be reading to its end.
watch() {
  local nap=""
  trap '[ -z "$nap" ] || kill "$nap" 2>/dev/null; exit 1' USR1
  while [ $((SECONDS - started)) -le "$bound" ]; do
    sleep 0.1 &
    nap=$!
    wait "$nap"
  done
  # Stopping it now: a SIGUSR1 from here on changes nothing. The two seconds before SIGKILL count
  # from the SIGTERM: after a sleep past the bound, the time since the start has used them up.
  trap '' USR1
  kill -TERM "$pid" 2>/dev/null
  started=$SECONDS
  while kill -0 "$pid" 2>/dev/null && [ $((SECONDS - started)) -le 2 ]; do sleep 0.1; done
  kill -KILL "$pid" 2>/dev/null
  exit 0
}
watch </dev/null >/dev/null 2>&1 &
watcher=$!
trap 'kill "$pid" "$watcher" 2>/dev/null; exit 130' INT
trap 'kill "$pid" "$watcher" 2>/dev/null; exit 143' TERM

# The command is waited for itself, so that one that ends at once returns at once. Then the
# watcher says whether it stopped it. Each wait keeps the shell's own report of a process ended by a
# signal, such as "Killed: 9", off the command's error output.
wait "$pid" 2>/dev/null
status=$?
kill -USR1 "$watcher" 2>/dev/null
if wait "$watcher" 2>/dev/null; then
  echo "squad-timeout: $1 did not end within $bound s, so it was stopped" >&2
  exit 124
fi
exit "$status"
