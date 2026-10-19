#!/usr/bin/env bash
# Check that check-version.sh names each section of the charter that changed since the last tag and
# that the newest CHANGELOG entry's Upgrading item leaves out (agent-squad #460). A section is a
# numbered heading, or an item of a numbered list right under a section's own heading, as §4.1 is;
# its parent covers it, and a range covers each section between its ends. A charter changed only
# in its Version line, or whose newest entry is already tagged, takes no names. Everything happens
# in a scratch repository, so this script touches neither the repository it is run from nor GitHub.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
version="$root/scripts/check-version.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-version-checker.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# The scratch repository, tagged v1: a charter with a section that has numbered headings (§2), one
# with an unnumbered heading (§1), one with a numbered list (§3) and one with neither (§4), and its
# changelog. `charter <version>` writes that charter, at that version.
repo="$lab/repo"
git init -q "$repo" || exit 2
git -C "$repo" config user.email version@example.com
git -C "$repo" config user.name "Version check"
charter() {
  cat > "$repo/SQUAD.md" <<EOF
# Charter

> **Version:** $1 (2026-10-19).

## 1. The team
The roles.

### Quick reference by role
1. The CTO's steps.

## 2. Environment
What every agent relies on.

### 2.1 Sessions
One session per agent.

### 2.2 Accounts
One account.

## 3. Pull requests
Every change goes through one.

1. **Branch** from main.
   Bring main in with a merge.
2. **Review** before the merge.

QA never pushes.

## 4. Communication
Signatures.
EOF
}
charter 1
printf '# Changelog\n\n## v1 — 2026-10-18\n- **The first release.**\n' > "$repo/CHANGELOG.md"
git -C "$repo" add -A && git -C "$repo" commit -qm v1 && git -C "$repo" tag v1 || exit 2

# `release <upgrading item>` makes the working tree release v2, with an entry whose Upgrading item
# is the text given, none when it is empty; `edit <sed program>` then changes the charter, and
# `verdict` runs the check, with its output in $out and its exit status in $code.
release() {
  charter 2
  {
    printf '# Changelog\n\n## v2 — 2026-10-19\n- **The second release.**\n'
    [ -z "$1" ] || printf -- '- **Upgrading from v1:** %s\n' "$1"
    printf '\n## v1 — 2026-10-18\n- **The first release.**\n'
  } > "$repo/CHANGELOG.md"
}
edit() { sed -i.bak "$1" "$repo/SQUAD.md" && rm -f "$repo/SQUAD.md.bak"; }
verdict() {
  out="$(cd "$repo" && "$version" 2>&1)"
  code=$?
}
# `passes <description>` and `fails <description> <line>...` judge the last verdict: a pass prints
# the version alone; a failure prints each line given, and no other.
passes() {
  if [ "$code" -eq 0 ] && [ "$out" = "version 2" ]; then pass "$1"; else fail "$1: exit $code, said: $out"; fi
}
fails() {
  local description="$1"
  shift
  if [ "$code" -eq 1 ] && [ "$out" = "$(printf '%s\n' "$@")" ]; then
    pass "$description"
  else
    fail "$description: exit $code, said: $out"
  fi
}

# 1. Only the Version line changed: no section is named, and none needs to be.
release "nothing to do."
verdict
passes "a charter changed only in its Version line passes, whatever the item names"

# 2. A changed section passes when the item names it or its parent, and fails, naming it, when the
#    item names neither: a sibling does not cover it, nor does a child cover its parent.
release "restart the sessions, since §2.1 changes."
edit 's/One session per agent./One session per agent, from the main checkout./'
verdict
passes "a change to §2.1 passes when the item names §2.1"
release "restart the sessions, since §2 changes."
edit 's/One session per agent./One session per agent, from the main checkout./'
verdict
passes "and when it names its parent, §2"
release "restart the sessions, since §2.2 changes."
edit 's/One session per agent./One session per agent, from the main checkout./'
verdict
fails "it fails when the item names a sibling, §2.2, naming §2.1 and its parent" \
  "SQUAD.md's §2.1 changed since v1, but v2's Upgrading item names neither §2.1 nor §2"
release "restart the sessions, since §2.1 changes."
edit 's/What every agent relies on./What every agent relies on, always./'
verdict
fails "a change to §2's own text fails when the item names its child, §2.1" \
  "SQUAD.md's §2 changed since v1, but v2's Upgrading item does not name it"
#    A line added alone makes a hunk that leaves its count out (QA's finding on PR #470).
release "restart the sessions, since §2 changes."
edit '/^Signatures.$/s/$/\
In bold./'
verdict
fails "a single line added to §4 fails when the item names §2 only" \
  "SQUAD.md's §4 changed since v1, but v2's Upgrading item does not name it"

# 3. A line under an unnumbered heading is in the section above it, and an item of a numbered list
#    right under a section's heading is a section, which the text after the list is not.
release "re-read §3."
edit "s/1. The CTO's steps./1. The CTO's steps, in order./"
verdict
fails "a change under §1's unnumbered heading is §1's" \
  "SQUAD.md's §1 changed since v1, but v2's Upgrading item does not name it"
release "re-read §3.2."
edit 's/   Bring main in with a merge./   Bring main in with a merge, never a rebase./; s/QA never pushes./QA never pushes to a branch of DEV./'
verdict
fails "the second line of §3's first item is §3.1's, and the text after the list is §3's" \
  "SQUAD.md's §3 changed since v1, but v2's Upgrading item does not name it" \
  "SQUAD.md's §3.1 changed since v1, but v2's Upgrading item names neither §3.1 nor §3"
release "re-read §3.1 and §3's last line."
edit 's/   Bring main in with a merge./   Bring main in with a merge, never a rebase./; s/QA never pushes./QA never pushes to a branch of DEV./'
verdict
passes "and both pass when the item names them"

# 4. A removed line is in the section the tag's charter had it in, and a range covers each section
#    between its ends, in the charter's order.
release "re-read §2.2 to §3."
edit '/^Signatures.$/d'
verdict
fails "a removed line of §4 fails when the item's range, §2.2 to §3, ends before it" \
  "SQUAD.md's §4 changed since v1, but v2's Upgrading item does not name it"
release "re-read §2.2 to §4."
edit '/^Signatures.$/d; s/One account./One shared account./; s/2. \*\*Review\*\* before the merge./2. **Review** before every merge./'
verdict
passes "and changes to §2.2, §3.2 and §4 pass when it is §2.2 to §4"
#    The item's lines are read as one, as an item wrapped at the margin needs: a range that the
#    wrapping splits still covers its sections (QA's finding on PR #470).
release "re-read the sections from §2.2
  to §4."
edit '/^Signatures.$/d; s/One account./One shared account./; s/2. \*\*Review\*\* before the merge./2. **Review** before every merge./'
verdict
passes "and so they do when the item's wrapping splits the range across two lines"

# 5. An entry with no Upgrading item fails for every section that changed, saying it has none.
release ""
edit 's/Signatures./Signatures, in bold./'
verdict
fails "an entry with no Upgrading item fails, saying so" \
  "SQUAD.md's §4 changed since v1, but v2's entry, which has no Upgrading item, does not name it"

# 6. Once the newest entry is tagged, a later change belongs to the next release, which has no entry
#    yet: the check passes. Without any tag, it fails, and says to fetch the tags.
release "nothing to do."
git -C "$repo" add -A && git -C "$repo" commit -qm v2 && git -C "$repo" tag v2 || exit 2
edit 's/Signatures./Signatures, in bold./'
verdict
passes "once the newest entry is tagged, a change after it passes"
git -C "$repo" tag -d v1 v2 >/dev/null
verdict
if [ "$code" -eq 1 ] && [ "$out" = "no release tag to compare SQUAD.md with: fetch the tags (git fetch --tags)" ]; then
  pass "without any tag, the check fails and says to fetch the tags"
else
  fail "without any tag: exit $code, said: $out"
fi

exit "$status"
