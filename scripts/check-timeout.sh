#!/usr/bin/env bash
# Check scripts/squad-timeout.sh (agent-squad #430), which bounds a command by wall-clock time. A
# command that ends in time keeps its input, output, error output and exit status, and one that ends
# at once returns at once (agent-squad #437); one that does not is stopped past its bound, with
# what it started (agent-squad #439) and SIGKILL if it ignores SIGTERM, and the script exits 124
# saying so; the command stays in the caller's process group; the bound counts the time the
# script itself was not running, as while the machine sleeps; an interrupted run stops the command
# first; bad usage exits 2, running nothing. Everything happens in a temporary directory.
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
# `check <description> <command...>` passes when the command does.
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}
# A command that never ends: it writes its PID to $lab/pid, then sleeps for a minute. `gone` passes
# when that process no longer runs.
endless=(bash -c 'echo "$$" > "$1"; exec sleep 60' _ "$lab/pid")
deaf=(bash -c 'trap "" TERM; echo "$$" > "$1"; exec sleep 60' _ "$lab/pid")
# One whose SIGTERM handler takes a second, then writes $lab/stopped and ends.
graceful=(bash -c 'trap "sleep 1; echo stopped > \"\$2\"; exit 0" TERM; echo "$$" > "$1"; while :; do sleep 0.1; done' \
  _ "$lab/pid" "$lab/stopped")
# shellcheck disable=SC2317,SC2329 # invoked through check
gone() { ! kill -0 "$(cat "$lab/pid")" 2>/dev/null; }
# `started` waits until the endless command has written its PID.
started() { until [ -s "$lab/pid" ]; do sleep 0.1; done; }
# `run <seconds> <command...>` runs squad-timeout.sh, keeping its output, error output, exit status
# and how many seconds it took.
run() {
  rm -f "$lab/pid"
  local start=$SECONDS
  out="$("$timeout" "$@" 2>"$lab/err" <<<"the caller's input")"
  code=$?
  took=$((SECONDS - start))
  err="$(cat "$lab/err")"
}

# 1. A command that ends in time: its input, output, error output and exit status are its own.
run 5 bash -c 'cat; echo "to stderr" >&2; exit 3'
check "a command that ends in time keeps its input, output and exit status" \
  bash -c '[ "$1" -eq 3 ] && [ "$2" = "the caller'\''s input" ] && [ "$3" = "to stderr" ]' _ "$code" "$out" "$err"

#    A command that ends at once returns at once, with no wait of the script's own (agent-squad
#    #437): fifty of them take three seconds at most, where a tenth of a second each would take six.
start=$SECONDS
for _ in $(seq 50); do "$timeout" 5 true || break; done
check "a command that ends at once returns at once: 50 runs within 3 s" bash -c '[ "$1" -le 3 ]' _ "$((SECONDS - start))"
#    On every bash at hand, this one and /bin/bash when it is another, as macOS's 3.2 is: a command
#    that ends at once is never taken for one stopped, even four loops of 100 at once; and one that
#    a signal ends keeps its status, with no report of the shell's, such as "Killed: 9", on the error
#    output (QA's finding on PR #442).
shells=(bash)
[ ! -x /bin/bash ] || [ "$(/bin/bash -c 'echo "$BASH_VERSION"')" = "$(bash -c 'echo "$BASH_VERSION"')" ] || shells+=(/bin/bash)
for shell in "${shells[@]}"; do
  version="$("$shell" -c 'echo "$BASH_VERSION"')"
  rm -f "$lab/not-0"
  start=$SECONDS
  for _ in 1 2 3 4; do
    for _ in $(seq 100); do "$shell" "$timeout" 5 true 2>>"$lab/loops-err" || echo "$?" >> "$lab/not-0"; done &
  done
  wait
  check "on bash $version, 400 runs of a command that ends at once, four loops at once, all exit 0 at once, saying nothing" \
    bash -c '[ ! -e "$1" ] && [ ! -s "$2" ] && [ "$3" -le 5 ]' _ "$lab/not-0" "$lab/loops-err" "$((SECONDS - start))"
  rm -f "$lab/loops-err"
  out="$("$shell" "$timeout" 5 bash -c 'kill -KILL $$' 2>"$lab/err")"
  code=$?
  check "on bash $version, a command that a signal ends keeps its status, and the shell reports nothing" \
    bash -c '[ "$1" -eq 137 ] && [ ! -s "$2" ]' _ "$code" "$lab/err"
done

# 2. A command that never ends is stopped past its bound, and the script says so.
run 1 "${endless[@]}"
check "a command that never ends is stopped after its bound: exit 124, saying so" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" = "squad-timeout: bash did not end within 1 s, so it was stopped" ] && [ "$3" -ge 1 ] && [ "$3" -le 3 ]' \
  _ "$code" "$err" "$took"
check "and it no longer runs" gone
run 1 "${deaf[@]}"
check "one that ignores SIGTERM gets SIGKILL two seconds later: exit 124" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -ge 3 ] && [ "$2" -le 6 ]' _ "$code" "$took"
check "and it no longer runs" gone

#    What the command started is stopped with it (agent-squad #439): a process it started, and the
#    transport that git starts for a remote, here an ssh that never answers, are gone after the run.
#    The command stays in this script's process group, so that a terminal it reads stays its own.
#    The process the command starts holds none of its output, which would keep this run waiting.
run 1 bash -c 'bash -c "echo \$\$ > \"\$1\"; exec sleep 60" _ "$1" >/dev/null 2>&1 & wait' _ "$lab/pid"
check "a process the command started is stopped with it: exit 124 within seconds, and it no longer runs" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -le 4 ] && ! kill -0 "$(cat "$3")" 2>/dev/null' _ "$code" "$took" "$lab/pid"
printf '#!/bin/sh\necho "$$" > %q\nexec sleep 60\n' "$lab/pid" > "$lab/ssh"
chmod +x "$lab/ssh"
rm -f "$lab/pid"
GIT_SSH_COMMAND="$lab/ssh" run 1 git ls-remote ssh://example.invalid/repo
check "a git whose ssh transport never answers is stopped with its transport: exit 124 within seconds, and neither runs" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -le 4 ] && [ -s "$3" ] && ! kill -0 "$(cat "$3")" 2>/dev/null' _ "$code" "$took" "$lab/pid"
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
check "stopped for longer than its bound, it stops the command once it runs again: exit 124" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -le 1 ]' _ "$code" "$((SECONDS - start))"
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
  check "SIG${signal%:*} stops the command, and the run: exit ${signal#*:}" \
    bash -c '[ "$1" -eq "$2" ]' _ "$code" "${signal#*:}"
  check "and the command no longer runs" gone
  check "nor what it started" bash -c '! kill -0 "$(cat "$1")" 2>/dev/null' _ "$lab/child.pid"
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
