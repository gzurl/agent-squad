#!/usr/bin/env bash
# Install or upgrade the squad in a project, in one line (agent-squad #89):
#   curl -fsSL https://raw.githubusercontent.com/<upstream>/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/<upstream>/main/install.sh \
#     | bash -s -- --tag vN /path/to/project
# gh can fetch it too, as /squad-upgrade does:
#   gh api -H 'Accept: application/vnd.github.raw' repos/<upstream>/contents/install.sh | bash
# It picks a release tag, the latest or the one given, fetches that tag's own
# scripts/squad-install.sh and runs it on the project: an install and an upgrade alike run the
# chosen tag's installer, which writes that tag's shim in one run. Projects run this file from
# main, not from a tag, so a change to it takes effect when merged (AGENTS.md, Releases).
# Each call to GitHub, its own and those of an installer from v65 on, stops after SQUAD_GH_TIMEOUT
# seconds of wall-clock time (120 when unset, or not a whole number above 0), through a copy of
# scripts/squad-timeout.sh that it writes beside the installer, since it runs alone
# (agent-squad #435).
#
# Usage: install.sh [--tag vN] [<project main checkout>]
# Exit: the installer's own status; 2 bad usage, a missing prerequisite, or a tag it cannot
#       install. Nothing is left in TMPDIR, whatever the outcome.
#
# Piped into bash, this script is bash's standard input, read as it runs. So everything happens in
# one function, called on the last line: a download cut short defines at most part of the function
# and runs nothing. The call ends with a word the function checks, so that a last line cut short
# does nothing either, and the function first closes its standard input, so that nothing it runs
# can read the script (bash keeps reading its script from a copy it makes of the descriptor).
set -u

# The upstream repository, the one place it is named.
upstream="gzurl/agent-squad"
# The oldest release whose scripts/squad-install.sh takes `<project> <tag>`: v14 and older have none.
oldest=15
# How long each call to GitHub may take, in seconds of wall-clock time (agent-squad #435).
bound="${SQUAD_GH_TIMEOUT:-120}"
[[ "$bound" =~ ^[1-9][0-9]*$ ]] || bound=120

install_squad() {
  local usage tag="" project="" tags installer tool
  usage="usage: install.sh [--tag vN] [<project main checkout>]
Installs or upgrades the squad in the project (default: the current directory) from the release tag
vN (default: the latest), v$oldest or later, by running that tag's own scripts/squad-install.sh."
  # `fail <reason> [<status>]` stops before anything is installed. When the status is 124, that of a
  # call to GitHub that got no answer within the bound, that silence is the reason.
  fail() {
    [ "${2:-0}" -ne 124 ] || set -- "GitHub did not answer within $bound s, so nothing was installed; run this again"
    echo "install.sh: $1" >&2
    exit 2
  }

  exec </dev/null
  # Output whose reader has gone, as when this is piped into head, must not stop an install
  # halfway (agent-squad #96): ignored here, SIGPIPE stays ignored in the installer it runs, the
  # older tags' included, and a write that fails loses a line, not the steps after it.
  trap '' PIPE
  # The last argument is the word the last line passes; without it, the script was cut short.
  if [ "$#" -eq 0 ] || [ "${!#}" != end-of-install.sh ]; then
    fail "this copy of install.sh is incomplete, so it did nothing; download it again"
  fi
  set -- "${@:1:$#-1}"

  # Arguments. A tag is checked before any use: it ends up in a URL and a command line.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) echo "$usage"; exit 0 ;;
      --tag)
        [ "$#" -ge 2 ] || fail "--tag needs a value"$'\n'"$usage"
        tag="$2"
        [[ "$tag" =~ ^v[0-9]+$ ]] || fail "'$tag' is not a release tag (vN)"
        shift 2 ;;
      -*) fail "unknown option $1"$'\n'"$usage" ;;
      *)
        [ -z "$project" ] || fail "one project at a time"$'\n'"$usage"
        project="$1"
        shift ;;
    esac
  done
  project="${project:-$PWD}"
  project="$(CDPATH='' cd -- "$project" 2>/dev/null && pwd)" || project="${project%/}"

  # Prerequisites, before anything is downloaded: the tools, gh's login, and access to upstream.
  # The tools are found by type -P, which the gh function below does not stand in for.
  for tool in gh git jq tar; do
    type -P "$tool" >/dev/null 2>&1 || fail "$tool is missing; install it and run this again"
  done

  # This run's own directory, removed on every way out. Its name is fixed before it exists, so that
  # an interrupt finds in the trap exactly that directory or nothing, never TMPDIR itself. A name
  # already taken is left alone; one that was free is this run's, so the trap removes whatever mkdir
  # leaves there, even when mkdir fails. The directory is closed to others by the umask, not by
  # mkdir -m: GNU mkdir sets that mode once the directory exists, which fails on NTFS under Git Bash
  # (agent-squad #404, as #277 was for the installer's own self-test).
  tmp="${TMPDIR:-/tmp}"
  tmp="${tmp%/}/agent-squad-install.$$.$RANDOM$RANDOM"
  { [ ! -e "$tmp" ] && [ ! -L "$tmp" ]; } || fail "cannot create a temporary directory: $tmp exists"
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  (umask 077 && mkdir "$tmp") 2>/dev/null || fail "cannot create a temporary directory"

  # The bound on each call to GitHub: scripts/squad-timeout.sh, written there, which the installer
  # finds beside itself too. It is that file, byte for byte, as a check of this repository keeps it.
  cat > "$tmp/squad-timeout.sh" <<'SQUAD-TIMEOUT' || fail "cannot write $tmp/squad-timeout.sh"
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
SQUAD-TIMEOUT
  chmod +x "$tmp/squad-timeout.sh" || fail "cannot make $tmp/squad-timeout.sh executable"
  gh() { "$tmp/squad-timeout.sh" "$bound" gh "$@"; }

  gh auth status >/dev/null 2>&1 || fail "gh is not logged in; run gh auth login and run this again" "$?"
  gh api "repos/$upstream" --jq .full_name >/dev/null 2>&1 \
    || fail "gh cannot read $upstream; the account gh uses needs access to it" "$?"

  # The release tags are vN, compared as numbers: v10 comes after v9.
  tags="$(gh api --paginate "repos/$upstream/git/matching-refs/tags/v" --jq '.[].ref' 2>/dev/null)" \
    || fail "cannot list the release tags of $upstream" "$?"
  tags="$(sed -n 's|^refs/tags/\(v[0-9][0-9]*\)$|\1|p' <<<"$tags" | sort -n -k1.2)"
  if [ -z "$tag" ]; then
    tag="$(tail -n 1 <<<"$tags")"
    [ -n "$tag" ] || fail "$upstream has no release tag"
  fi
  grep -qxF -- "$tag" <<<"$tags" || fail "$upstream has no tag $tag"
  [ "${tag#v}" -ge "$oldest" ] \
    || fail "$tag has no installer: install.sh installs v$oldest and later"

  # The chosen tag's installer goes into this run's directory.
  installer="$tmp/squad-install.sh"
  gh api -H 'Accept: application/vnd.github.raw' \
    "repos/$upstream/contents/scripts/squad-install.sh?ref=$tag" > "$installer" 2>/dev/null \
    || fail "cannot fetch scripts/squad-install.sh of $tag from $upstream" "$?"
  [ -s "$installer" ] || fail "cannot fetch scripts/squad-install.sh of $tag from $upstream"

  # The installer's own output follows, and its exit status is this script's.
  echo "install.sh: installing agent-squad $tag into $project, with $tag's own installer"
  bash "$installer" "$project" "$tag"
  exit
}

install_squad "$@" end-of-install.sh
