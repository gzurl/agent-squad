#!/usr/bin/env bash
# Check scripts/squad-timeout.sh (agent-squad #430), which bounds a command by wall-clock time. A
# command that ends in time keeps its input, output, error output and exit status; one that does not
# is stopped past its bound, with SIGKILL if it ignores SIGTERM, and the script exits 124 saying so;
# the bound counts the time the script itself was not running, as while the machine sleeps; an
# interrupted run stops the command first; bad usage exits 2, running nothing. Everything happens in
# a temporary directory.
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

# 2. A command that never ends is stopped past its bound, and the script says so.
run 1 "${endless[@]}"
check "a command that never ends is stopped after its bound: exit 124, saying so" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" = "squad-timeout: bash did not end within 1 s, so it was stopped" ] && [ "$3" -ge 1 ] && [ "$3" -le 3 ]' \
  _ "$code" "$err" "$took"
check "and it no longer runs" gone
run 1 "${deaf[@]}"
check "one that ignores SIGTERM gets SIGKILL two seconds later: exit 124" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -ge 3 ] && [ "$2" -le 5 ]' _ "$code" "$took"
check "and it no longer runs" gone

# 3. The bound is wall-clock time: squad-timeout.sh stopped past its bound, as a sleeping machine
#    stops every process, stops the command as soon as it runs again, not a bound later.
rm -f "$lab/pid"
"$timeout" 4 "${endless[@]}" 2>/dev/null &
runner=$!
started
kill -STOP "$runner"
sleep 6
start=$SECONDS
kill -CONT "$runner"
wait "$runner"
code=$?
check "stopped for longer than its bound, it stops the command once it runs again: exit 124" \
  bash -c '[ "$1" -eq 124 ] && [ "$2" -le 1 ]' _ "$code" "$((SECONDS - start))"
check "and the command no longer runs" gone

# 4. An interrupted run stops the command first. The run is started under job control, without
#    which a command started in the background ignores SIGINT.
for signal in INT:130 TERM:143; do
  rm -f "$lab/pid"
  set -m
  "$timeout" 60 "${endless[@]}" &
  runner=$!
  set +m
  started
  kill "-${signal%:*}" "$runner"
  wait "$runner"
  code=$?
  check "SIG${signal%:*} stops the command, and the run: exit ${signal#*:}" \
    bash -c '[ "$1" -eq "$2" ]' _ "$code" "${signal#*:}"
  check "and the command no longer runs" gone
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
