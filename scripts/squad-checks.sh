#!/usr/bin/env bash
# The checks of SQUAD.md §4.2, which the pre-push gate runs: run every check listed in
# .agent-squad-checks, at the root of the checkout, as a command of its own, print one status line
# per check, and exit non-zero when any of them failed. The checks run one after another, or side
# by side when the list has the line `# squad-checks: side by side` (agent-squad #459).
# Usage: <playbook>/scripts/squad-checks.sh, from anywhere inside the repository. <playbook> is the
#        main checkout's .agent-squad/playbook (SQUAD.md §2.4); in the agent-squad repository
#        itself, the script is scripts/squad-checks.sh.
# Exit: 0 all passed, 1 at least one failed, 2 the list is missing or empty.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root" || exit 2
list=".agent-squad-checks"

# A hook runs with git's own variables set (GIT_DIR and others). A check that uses git, such as a
# test that builds a repository in a temporary directory, would otherwise act on this repository:
# commit into it, or even reinitialise its configuration. The checks start without them.
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The project's own checks, one shell command per line. Blank lines and comments are skipped,
# indented ones included: run as commands, they would pass as checks that check nothing. A list
# saved with CRLF line endings has its carriage returns dropped: kept, they would end every command.
# The comment that opts in to running them side by side is that line alone, blanks around it aside,
# so that a release that does not know it reads it as the comment it is.
commands=()
side_by_side=no
if [ -f "$list" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [ "${trimmed%"${trimmed##*[![:space:]]}"}" = "# squad-checks: side by side" ] && side_by_side=yes
    case "$trimmed" in ''|'#'*) continue ;; esac
    commands+=("$line")
  done < "$list"
fi
if [ "${#commands[@]}" -eq 0 ]; then
  echo "checks: $list is missing or lists no command; list the project's checks there, one per line" >&2
  exit 2
fi

# The machine does not idle-sleep while the checks run, which can take longer than its idle delay:
# a sleep during a push's checks closes its connection to the remote (agent-squad #458). caffeinate
# holds that for as long as this script runs, and lets go once it ends, however it ends. Where there
# is no caffeinate, as off macOS, the attempt fails without a word and the checks run all the same.
caffeinate -i -w "$$" </dev/null >/dev/null 2>&1 &

# Each check runs on its own, so that one failing never hides behind another or behind a pipe, and
# as a job: job control gives it a process group of its own, which a stop reaches whole, and keeps
# SIGINT as a terminal leaves it, which a command started in the background without it ignores, and
# so would every test of an interruption that the check runs. $pids holds the checks started, and
# $work what the run keeps while it runs: the output of each check side by side, and a mark for
# each check that the terminal stopped.
work="$(mktemp -d "${TMPDIR:-/tmp}/squad-checks.XXXXXX")" || exit 2
trap 'rm -rf "$work"' EXIT
pids=()
# `stop [<pid>...]` ends those checks, or the checks started when none is named, with every process
# each started, as pgrep finds them under it or in its process group: SIGTERM, with SIGCONT for one
# that is stopped, so that it takes the SIGTERM, then SIGKILL to those still running two seconds
# later. kill passes while any of them is there to signal. The last job started counts too, should
# a signal come before its PID is in $pids.
# shellcheck disable=SC2317,SC2329 # run by the traps and the watch below
family() {
  local child
  for child in $(pgrep -P "$1"); do family "$child"; done
  echo "$1"
}
# shellcheck disable=SC2317,SC2329 # the same
stop() {
  local stopping pid tenths=20 running=("$@")
  [ "$#" -gt 0 ] || running=("${pids[@]}" "$!")
  stopping="$(for pid in "${running[@]}"; do family "$pid"; done)"
  # shellcheck disable=SC2086 # the PIDs are split on purpose, one argument each
  kill -TERM -- $stopping "${running[@]/#/-}" 2>/dev/null
  # shellcheck disable=SC2086 # the same
  kill -CONT -- $stopping "${running[@]/#/-}" 2>/dev/null
  # shellcheck disable=SC2086 # the same
  while [ "$tenths" -gt 0 ] && kill -0 -- $stopping "${running[@]/#/-}" 2>/dev/null; do
    sleep 0.1
    tenths=$((tenths - 1))
  done
  # shellcheck disable=SC2086 # the same
  kill -KILL -- $stopping "${running[@]/#/-}" 2>/dev/null
}
# Interrupted, hung up, as a closed terminal does, or terminated, the run stops its checks first: in
# groups of their own, the checks get none of these signals themselves (QA's finding on PR #472).
# The script waits for its checks as jobs, so a signal reaches these traps at once, whatever a check
# does with it: waiting for a check in the foreground, bash would take a SIGINT that the check ends
# normally on as handled, and go on to the next check (agent-squad #494). SIGKILL, which no trap
# catches, leaves them running.
trap 'stop; exit 130' INT
trap 'stop; exit 129' HUP
trap 'stop; exit 143' TERM
# A check apart from the terminal's process group that reads the terminal, as a pager does, or
# writes to one set with `stty tostop`, is stopped by it until it is continued, which would hold
# the run for good (QA's finding on PR #497). `watch <pid>...`, in the background, looks at those
# checks twice a second with ps, stops any that is stopped, `T`, and leaves $work/<pid>.terminal
# for it; it ends once none of them runs, or the run itself has ended. `kept <pid> <status>`
# prints that check's status, `terminal` when the watch stopped it.
# shellcheck disable=SC2317,SC2329 # run in the background below
watch() {
  local pid state
  while kill -0 "$@" 2>/dev/null && kill -0 "$$" 2>/dev/null; do
    while read -r pid state; do
      case "$state" in T*) : >"$work/$pid.terminal"; stop "$pid" ;; esac
    done <<<"$(ps -o pid=,stat= -p "$(IFS=,; echo "$*")" 2>/dev/null)"
    sleep 0.5 || return
  done
}
kept() { if [ -e "$work/$1.terminal" ]; then echo terminal; else echo "$2"; fi; }
# `watching <pid>...` starts the watch on those checks, its PID in $watcher, out of bash's table of
# jobs: ended with a signal once they have ended, it is then not reported, as bash on Linux reports
# a job killed so ("Terminated").
watching() {
  watch "$@" </dev/null >/dev/null 2>&1 &
  watcher=$!
  disown "$watcher"
}

codes=()
if [ "$side_by_side" = no ]; then
  # One after another, each check's output goes straight to the terminal.
  for i in "${!commands[@]}"; do
    echo "checks: running: ${commands[$i]}" >&2
    set -m
    bash -c "${commands[$i]}" </dev/null &
    pids=("$!")
    set +m
    watching "${pids[0]}"
    wait "${pids[0]}"
    codes+=("$(kept "${pids[0]}" "$?")")
    kill "$watcher" 2>/dev/null
  done
else
  # Side by side, each check writes to a file of its own, shown once it has ended if it failed:
  # interleaved, the output of several checks would not read.
  set -m
  for i in "${!commands[@]}"; do
    echo "checks: running: ${commands[$i]}" >&2
    bash -c "${commands[$i]}" </dev/null >"$work/$i" 2>&1 &
    pids+=("$!")
  done
  set +m
  watching "${pids[@]}"
  for i in "${!commands[@]}"; do
    wait "${pids[$i]}"
    codes+=("$(kept "${pids[$i]}" "$?")")
    if [ "${codes[$i]}" != 0 ]; then
      echo "checks: output of ${commands[$i]}:" >&2
      cat "$work/$i" >&2
    fi
  done
  kill "$watcher" 2>/dev/null
fi

# One line per check, so that a failure is read and not only counted.
failed=0
echo "checks: summary" >&2
for i in "${!commands[@]}"; do
  if [ "${codes[$i]}" = 0 ]; then
    echo "  ok      ${commands[$i]}" >&2
  elif [ "${codes[$i]}" = terminal ]; then
    echo "  FAILED  ${commands[$i]} (stopped: it read the terminal, or wrote to it under stty tostop)" >&2
    failed=1
  else
    echo "  FAILED  ${commands[$i]} (exit ${codes[$i]})" >&2
    failed=1
  fi
done
exit "$failed"
