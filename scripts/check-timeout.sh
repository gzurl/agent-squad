#!/usr/bin/env bash
# Check scripts/squad-timeout.sh (agent-squad #430), which bounds a command by wall-clock time. A
# command that ends in time keeps its input, output, error output and exit status, and one that ends
# at once returns at once (agent-squad #437); one that does not is stopped past its bound, with
# what it started (agent-squad #439) and SIGKILL if it ignores SIGTERM, and the script exits 124
# saying so; the command stays in the caller's process group; the bound counts the time the
# script itself was not running, as while the machine sleeps; an interrupted run stops the command
# first; bad usage exits 2, running nothing. A case that fails says what it measured, and its
# bounds hold with every check running side by side (agent-squad #487). Everything happens in a
# temporary directory.
# shellcheck disable=SC2016 # the commands' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
timeout="$root/scripts/squad-timeout.sh"

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-timeout.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }
# `check <description> <command...>` passes when the command does. One that fails also prints what
# the case measured, which it leaves in $measured, so that a failure under load names the bound
# that did not hold (agent-squad #487).
measured=""
check() {
  local description="$1"
  shift
  if "$@"; then
    pass "$description"
  else
    fail "$description"
    [ -z "$measured" ] || echo "          measured: $measured" >&2
  fi
  measured=""
}
# A command that never ends: it writes its PID to $lab/pid, then sleeps for a minute.
endless=(bash -c 'echo "$$" > "$1"; exec sleep 60' _ "$lab/pid")
deaf=(bash -c 'trap "" TERM; echo "$$" > "$1"; exec sleep 60' _ "$lab/pid")
# One whose SIGTERM handler takes a second, then writes $lab/stopped and ends. Left alone, it ends
# after a minute too, so that a run that stops nothing fails instead of holding this check for good.
graceful=(bash -c 'trap "sleep 1; echo stopped > \"\$2\"; exit 0" TERM; echo "$$" > "$1"; while [ "$SECONDS" -lt 60 ]; do sleep 0.1; done' \
  _ "$lab/pid" "$lab/stopped")
# `state <pid file>` says what became of the process whose PID the file holds: "never started" while
# the file is empty, "ended" once no process has that PID, or only one that has ended and that its
# parent has not waited for yet, a zombie, which kill -0 still reaches; "still runs" otherwise.
state() {
  local pid stat
  pid="$(cat "$1" 2>/dev/null)"
  if [ -z "$pid" ]; then echo "never started"; return; fi
  if ! stat="$(ps -o stat= -p "$pid" 2>/dev/null)" || [[ "$stat" =~ ^[[:space:]]*Z ]]; then echo ended; else echo "still runs"; fi
}
# `gone [<pid file>]` passes when the process whose PID the file holds, $lab/pid by default, has
# started and ended, and leaves what became of it in $measured.
# shellcheck disable=SC2317,SC2329 # invoked through check
gone() {
  local became
  became="$(state "${1:-$lab/pid}")"
  measured="it $became"
  [ "$became" = ended ]
}
# `started` waits until the endless command has written its PID, for 30 s at most: one stopped
# before it wrote it would otherwise hold this check for good.
started() {
  local tenths=300
  until [ -s "$lab/pid" ] || [ "$tenths" -eq 0 ]; do sleep 0.1; tenths=$((tenths - 1)); done
}
# `run <seconds> <command...>` runs squad-timeout.sh, keeping its output, error output, exit status
# and how many seconds it took, which it also leaves in $measured.
run() {
  rm -f "$lab/pid"
  local start=$SECONDS
  out="$("$timeout" "$@" 2>"$lab/err" <<<"the caller's input")"
  code=$?
  took=$((SECONDS - start))
  err="$(cat "$lab/err")"
  measured="exit $code after $took s"
}

# 1. A command that ends in time: its input, output, error output and exit status are its own.
run 5 bash -c 'cat; echo "to stderr" >&2; exit 3'
check "a command that ends in time keeps its input, output and exit status" \
  bash -c '[ "$1" -eq 3 ] && [ "$2" = "the caller'\''s input" ] && [ "$3" = "to stderr" ]' _ "$code" "$out" "$err"

#    A command that ends at once returns at once, with no wait of the script's own (agent-squad
#    #437): fifty of them take three seconds at most, where a tenth of a second each would take six.
start=$SECONDS
for _ in $(seq 50); do "$timeout" 5 true || break; done
took=$((SECONDS - start))
measured="$took s"
check "a command that ends at once returns at once: 50 runs within 3 s" bash -c '[ "$1" -le 3 ]' _ "$took"
#    On every bash at hand, this one and /bin/bash when it is another, as macOS's 3.2 is: a command
#    that ends at once is never taken for one stopped, even four loops of 100 at once, which its exit
#    status says, whatever the time they take under a slow tracer such as CI's kcov; and one that a
#    signal ends keeps its status, with no report of the shell's, such as "Killed: 9", on the error
#    output (QA's finding on PR #442).
shells=(bash)
[ ! -x /bin/bash ] || [ "$(/bin/bash -c 'echo "$BASH_VERSION"')" = "$(bash -c 'echo "$BASH_VERSION"')" ] || shells+=(/bin/bash)
for shell in "${shells[@]}"; do
  version="$("$shell" -c 'echo "$BASH_VERSION"')"
  rm -f "$lab/not-0"
  for _ in 1 2 3 4; do
    for _ in $(seq 100); do "$shell" "$timeout" 5 true 2>>"$lab/loops-err" || echo "$?" >> "$lab/not-0"; done &
  done
  wait
  measured="$([ -e "$lab/not-0" ] && wc -l <"$lab/not-0" | tr -d ' ' || echo 0) runs did not exit 0, and the error output has $(wc -l <"$lab/loops-err" | tr -d ' ') lines"
  check "on bash $version, 400 runs of a command that ends at once, four loops at once, all exit 0, saying nothing" \
    bash -c '[ ! -e "$1" ] && [ ! -s "$2" ]' _ "$lab/not-0" "$lab/loops-err"
  rm -f "$lab/loops-err"
  out="$("$shell" "$timeout" 5 bash -c 'kill -KILL $$' 2>"$lab/err")"
  code=$?
  measured="exit $code, and the error output has $(wc -l <"$lab/err" | tr -d ' ') lines"
  check "on bash $version, a command that a signal ends keeps its status, and the shell reports nothing" \
    bash -c '[ "$1" -eq 137 ] && [ ! -s "$2" ]' _ "$code" "$lab/err"
done

# 2. A command that never ends is stopped past its bound, and the script says so. The cases that
#    stop one allow 30 s at most: well under the 60 s it sleeps, and over what CI's kcov takes
#    (agent-squad #447). Their bound, 3 s, leaves what they stop the time to start: git's
#    transport, the slowest, started in 0.02 to 0.68 s in most runs, and once in a while past 3 s
#    on a machine loaded by other work (agent-squad #487, #491). A process that starts as its bound
#    passes can be stopped before it wrote its PID, or after the stop listed what the command had
#    started. `again <pid file> <seconds> <command...>` runs squad-timeout.sh as `run` does, and
#    when the process whose PID the file is to hold never started within that bound, once more with
#    15 s: a stop that came before it started tested nothing of squad-timeout.sh. It leaves the
#    bound of the run kept in $bound, and what both runs measured in $measured.
again() {
  local pid_file="$1" first first_bound="$2"
  shift 2
  bound="$first_bound"
  run "$bound" "$@"
  [ "$(state "$pid_file")" = "never started" ] || return 0
  first="$measured"
  bound=15
  run "$bound" "$@"
  measured="with $first_bound s, $first, it started nothing; again with $bound s, $measured"
}
again "$lab/pid" 3 "${endless[@]}"
check "a command that never ends is stopped after its bound: exit 124, saying so" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" = "squad-timeout: bash did not end within $4 s, so it was stopped" ] && [ "$3" -ge "$4" ] && [ "$3" -le 30 ]' \
  _ "$code" "$err" "$took" "$bound"
check "and it no longer runs" gone
#    The SIGKILL's two seconds are timed against the plain stop just above, which kcov slows as much
#    (QA's finding on PR #453), with the bounds' difference taken off when either ran again.
stopped_in=$took stopped_bound=$bound
again "$lab/pid" 3 "${deaf[@]}"
measured+=", where the plain stop took $stopped_in s with $stopped_bound s"
check "one that ignores SIGTERM gets SIGKILL two seconds later: exit 124" \
  bash -c 'late=$(($2 - $3 - $4 + $5)); [ "$1" -eq 124 ] && [ "$2" -le 30 ] && [ "$late" -ge 1 ] && [ "$late" -le 4 ]' \
  _ "$code" "$took" "$stopped_in" "$bound" "$stopped_bound"
check "and it no longer runs" gone

#    What the command started is stopped with it (agent-squad #439): a process it started, and the
#    transport that git starts for a remote, here an ssh that never answers, are gone after the run.
#    The command stays in this script's process group, so that a terminal it reads stays its own.
#    The process the command starts holds none of its output, which would keep this run waiting.
again "$lab/pid" 3 bash -c 'bash -c "echo \$\$ > \"\$1\"; exec sleep 60" _ "$1" >/dev/null 2>&1 & wait' _ "$lab/pid"
became="$(state "$lab/pid")"
measured+=", and its child $became"
check "a process the command started is stopped with it: exit 124 within seconds, and it no longer runs" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -le 30 ] && [ "$3" = ended ]' _ "$code" "$took" "$became"
printf '#!/bin/sh\necho "$$" > %q\nexec sleep 60\n' "$lab/pid" > "$lab/ssh"
chmod +x "$lab/ssh"
rm -f "$lab/pid"
GIT_SSH_COMMAND="$lab/ssh" again "$lab/pid" 3 git ls-remote ssh://example.invalid/repo
became="$(state "$lab/pid")"
measured+=", and its transport $became"
check "a git whose ssh transport never answers is stopped with its transport: exit 124 within seconds, and neither runs" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -le 30 ] && [ "$3" = ended ]' _ "$code" "$took" "$became"
run 5 sh -c 'ps -o pgid= -p "$$"'
check "the command runs in the caller's process group" \
  bash -c '[ "$(tr -d " " <<<"$1")" = "$(ps -o pgid= -p "$2" | tr -d " ")" ]' _ "$out" "$$"

# 3. The bound is wall-clock time: squad-timeout.sh stopped past its bound, with the command and
#    the watcher it started, as a sleeping machine stops every process, stops the command as soon as
#    they run again, not a bound later. `freeze <signal>` sends the signal to the runner and to the
#    processes it started.
# shellcheck disable=SC2046 # the PIDs are split on purpose, one argument each
freeze() { kill "-$1" "$runner" $(pgrep -P "$runner"); }
rm -f "$lab/pid"
"$timeout" 4 "${endless[@]}" 2>/dev/null &
runner=$!
started
freeze STOP
sleep 6
start=$SECONDS
freeze CONT
wait "$runner"
code=$?
took=$((SECONDS - start))
measured="exit $code, $took s after it ran again"
#    Within 2 s of running again, where a bound counted from that moment would take 4.
check "stopped for longer than its bound, it stops the command once it runs again: exit 124" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -le 2 ]' _ "$code" "$took"
check "and the command no longer runs" gone
#    Its two seconds after SIGTERM count from the SIGTERM, not from the start, which a stop past
#    the bound has used up: a command stopped with it gets them to end by itself (QA's finding on
#    PR #432).
rm -f "$lab/pid" "$lab/stopped"
"$timeout" 2 "${graceful[@]}" 2>/dev/null &
runner=$!
started
freeze STOP
sleep 6
freeze CONT
wait "$runner"
code=$?
measured="exit $code, and the command's SIGTERM handler $([ -s "$lab/stopped" ] && echo ended || echo "did not end")"
check "stopped with it past the bound, a command still has two seconds after SIGTERM to end: exit 124" \
  bash -c '[ "$1" -eq 124 ] && [ "$(cat "$2")" = stopped ]' _ "$code" "$lab/stopped"
check "and the command no longer runs" gone

# 4. An interrupted run stops the command first, with what it started (QA's finding on PR #444):
#    the command here starts a process, which writes its PID to $lab/child.pid, then writes its
#    own. The run is started under job control, without which a command started in the background
#    ignores SIGINT.
parent=(bash -c 'bash -c "echo \$\$ > \"\$1\"; exec sleep 60" _ "$1" >/dev/null 2>&1 &
  until [ -s "$1" ]; do sleep 0.1; done; echo "$$" > "$2"; wait' _ "$lab/child.pid" "$lab/pid")
for signal in INT:130 TERM:143; do
  rm -f "$lab/pid" "$lab/child.pid"
  set -m
  "$timeout" 60 "${parent[@]}" &
  runner=$!
  set +m
  started
  kill "-${signal%:*}" "$runner"
  wait "$runner"
  code=$?
  measured="exit $code"
  check "SIG${signal%:*} stops the command, and the run: exit ${signal#*:}" \
    bash -c '[ "$1" -eq "$2" ]' _ "$code" "${signal#*:}"
  check "and the command no longer runs" gone
  check "nor what it started" gone "$lab/child.pid"
done

# 5. Bad usage exits 2, and runs nothing: no bound, no command, or a bound that is not a whole
#    number of seconds above 0.
usage_is() {
  check "$1 is bad usage: exit 2, and nothing run" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "usage: squad-timeout.sh <seconds> <command> [<argument>...]" ] && [ ! -e "$3" ]' \
    _ "$code" "$err" "$lab/ran"
}
run
usage_is "no argument"
run 5
usage_is "a bound alone"
for bound in 0 1x -1 ""; do
  run "$bound" touch "$lab/ran"
  usage_is "a bound of '$bound'"
done

exit "$status"
