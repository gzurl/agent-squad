#!/usr/bin/env bash
# Local gate of SQUAD.md §4: run every check listed in .agent-squad-checks, at the root of the
# checkout, as a command of its own, print one status line per check, and exit non-zero when any of
# them failed.
# Usage: scripts/squad-checks.sh   (from anywhere inside the repository; the pre-push hook runs it)
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
commands=()
if [ -f "$list" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "${line#"${line%%[![:space:]]*}"}" in ''|'#'*) continue ;; esac
    commands+=("$line")
  done < "$list"
fi
if [ "${#commands[@]}" -eq 0 ]; then
  echo "checks: $list is missing or lists no command; list the project's checks there, one per line" >&2
  exit 2
fi

# Each check runs on its own, so that one failing never hides behind another or behind a pipe.
codes=()
for command in "${commands[@]}"; do
  echo "checks: running: $command" >&2
  bash -c "$command" </dev/null
  codes+=("$?")
done

# One line per check, so that a failure is read and not only counted.
failed=0
echo "checks: summary" >&2
for i in "${!commands[@]}"; do
  if [ "${codes[$i]}" -eq 0 ]; then
    echo "  ok      ${commands[$i]}" >&2
  else
    echo "  FAILED  ${commands[$i]} (exit ${codes[$i]})" >&2
    failed=1
  fi
done
exit "$failed"
