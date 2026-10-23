#!/usr/bin/env bash
# Refuse a push that names a private repository of this repository's owner (agent-squad #514): this
# repository is public, and the other squads' projects are private. It fails when a tracked file,
# or the message of a commit not yet on origin/main, names one: in any case, with `-`, `_`, `.`, a
# space or nothing between its words, and not inside a longer word. It prints each file and line,
# or each commit, and never the name, so that its output can be quoted anywhere.
# It reads the names from GitHub at each run, so that no list of them is written here: `gh repo
# list`, through squad-timeout.sh, beside it, which stops the call after SQUAD_GH_TIMEOUT seconds
# of wall-clock time (120 when unset, or not a whole number above 0). In GitHub Actions, whose token
# cannot list the owner's private repositories, it does not check: it says so, and passes.
# Exit: 0 none is named, or not checked in GitHub Actions; 1 one is named, or the owner, its
# private repositories or the commits not yet on origin/main cannot be read.
set -u
root="$(git rev-parse --show-toplevel)" || exit 1
cd "$root" || exit 1
say() { echo "private names: $*"; }

if [ "${GITHUB_ACTIONS:-}" = true ]; then
  say "not checked: GitHub Actions cannot list the owner's private repositories"
  exit 0
fi

# The owner, from origin's URL: https://github.com/<owner>/<repo>, git@github.com:<owner>/<repo>
# or ssh://git@github.com/<owner>/<repo>.
owner="$(git remote get-url origin 2>/dev/null \
  | sed -nE 's#^(https://|ssh://git@|git@)github\.com[:/]([^/]+)/[^/]+$#\2#p')"
if [ -z "$owner" ]; then
  say "origin is not a GitHub repository, so its owner is unknown and nothing was checked"
  exit 1
fi

# The owner's private repositories, one name per line; gh says why it failed on its own.
gh_seconds="${SQUAD_GH_TIMEOUT:-120}"
[[ "$gh_seconds" =~ ^[1-9][0-9]*$ ]] || gh_seconds=120
if ! names="$("$(dirname "$0")/squad-timeout.sh" "$gh_seconds" \
  gh repo list "$owner" --visibility private --limit 1000 --json name --jq '.[].name')"; then
  say "GitHub could not be read, so $owner's private repositories are unknown and nothing was checked"
  exit 1
fi
count="$(grep -c . <<<"$names")"
if [ "$count" -eq 0 ]; then
  say "$owner has no private repository to look for"
  exit 0
fi

# One pattern for every name: its words, split at `-`, `_` and `.`, joined by any one of them, a
# space or nothing, with neither a letter nor a digit on either side. A name's words hold letters
# and digits only, so none needs escaping.
names_pattern="$(awk 'NF {
    n = split(tolower($0), word, /[-_.]/); p = ""
    for (i = 1; i <= n; i++) if (word[i] != "") p = p (p == "" ? "" : "[-_. ]?") word[i]
    print p
  }' <<<"$names" | paste -sd '|' -)"
pattern="(^|[^[:alnum:]])($names_pattern)([^[:alnum:]]|$)"

# Each tracked file's lines that name one, as <file>:<line>; git grep exits 1 when none does.
found="$(git grep -n -I -i -E -e "$pattern")"
case $? in
  0|1) ;;
  *) say "the tracked files could not be read"; exit 1 ;;
esac
places="$(cut -d: -f1,2 <<<"$found" | grep .)"

# Each commit not yet on origin/main whose message names one.
if ! git rev-parse -q --verify 'origin/main^{commit}' >/dev/null; then
  say "origin/main is unknown, so the commits not yet on it are too: fetch it"
  exit 1
fi
while read -r commit; do
  [ -n "$commit" ] || continue
  git log -1 --format=%B "$commit" | grep -qiE "$pattern" && places="$places${places:+$'\n'}commit $commit"
done <<<"$(git rev-list --abbrev-commit origin/main..HEAD)"

if [ -n "$places" ]; then
  say "these name one of $owner's private repositories; the name is not printed:"
  while IFS= read -r place; do echo "  $place"; done <<<"$places"
  exit 1
fi
say "no tracked file, and no commit since origin/main, names one of $owner's $count private repositories"
