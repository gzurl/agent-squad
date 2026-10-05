#!/usr/bin/env bash
# Install or upgrade the squad in a project, in one line (agent-squad #89):
#   curl -fsSL https://raw.githubusercontent.com/<upstream>/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/<upstream>/main/install.sh \
#     | bash -s -- --tag v45 /path/to/project
# gh can fetch it too, as /squad-upgrade does:
#   gh api -H 'Accept: application/vnd.github.raw' repos/<upstream>/contents/install.sh | bash
# It picks a release tag, the latest or the one given, fetches that tag's own
# scripts/squad-install.sh and runs it on the project: an install and an upgrade alike run the
# chosen tag's installer, which writes that tag's shim in one run. Projects run this file from
# main, not from a tag, so a change to it takes effect when merged (AGENTS.md, Releases).
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

install_squad() {
  local usage tag="" project="" tags installer tool
  usage="usage: install.sh [--tag vN] [<project main checkout>]
Installs or upgrades the squad in the project (default: the current directory) from the release tag
vN (default: the latest), v$oldest or later, by running that tag's own scripts/squad-install.sh."
  # `fail <reason>` stops before anything is installed.
  fail() { echo "install.sh: $1" >&2; exit 2; }

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
  for tool in gh git jq tar; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is missing; install it and run this again"
  done
  gh auth status >/dev/null 2>&1 || fail "gh is not logged in; run gh auth login and run this again"
  gh api "repos/$upstream" --jq .full_name >/dev/null 2>&1 \
    || fail "gh cannot read $upstream; the account gh uses needs access to it"

  # The release tags are vN, compared as numbers: v10 comes after v9.
  tags="$(gh api --paginate "repos/$upstream/git/matching-refs/tags/v" --jq '.[].ref' 2>/dev/null)" \
    || fail "cannot list the release tags of $upstream"
  tags="$(sed -n 's|^refs/tags/\(v[0-9][0-9]*\)$|\1|p' <<<"$tags" | sort -n -k1.2)"
  if [ -z "$tag" ]; then
    tag="$(tail -n 1 <<<"$tags")"
    [ -n "$tag" ] || fail "$upstream has no release tag"
  fi
  grep -qxF -- "$tag" <<<"$tags" || fail "$upstream has no tag $tag"
  [ "${tag#v}" -ge "$oldest" ] \
    || fail "$tag has no installer: install.sh installs v$oldest and later"

  # The chosen tag's installer goes into a directory of this run's own, removed on every way out.
  # Its name is fixed before it exists, so that an interrupt finds in the trap exactly that
  # directory or nothing, never TMPDIR itself.
  tmp="${TMPDIR:-/tmp}"
  tmp="${tmp%/}/agent-squad-install.$$.$RANDOM$RANDOM"
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir -m 700 "$tmp" 2>/dev/null || { tmp=""; fail "cannot create a temporary directory"; }
  installer="$tmp/squad-install.sh"
  if ! gh api -H 'Accept: application/vnd.github.raw' \
    "repos/$upstream/contents/scripts/squad-install.sh?ref=$tag" > "$installer" 2>/dev/null \
    || [ ! -s "$installer" ]; then
    fail "cannot fetch scripts/squad-install.sh of $tag from $upstream"
  fi

  # The installer's own output follows, and its exit status is this script's.
  echo "install.sh: installing agent-squad $tag into $project, with $tag's own installer"
  bash "$installer" "$project" "$tag"
  exit
}

install_squad "$@" end-of-install.sh
