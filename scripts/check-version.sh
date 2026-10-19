#!/usr/bin/env bash
# The Version line of SQUAD.md must match the newest CHANGELOG.md entry, and the version of every
# plugin in mods/ must be that release's, N.0.0 for version N (agent-squad #206). While that entry
# is the release being written, newer than every tag, its Upgrading item names each section of
# SQUAD.md that changed since the last tag, or the section's parent: §4 covers §4.1, and §2.3 to §4
# covers each section from §2.3 to §4's last (#460).
set -u
charter="$(grep -o '^> \*\*Version:\*\* [0-9]*' SQUAD.md | grep -o '[0-9]*$')"
changelog="$(grep -o '^## v[0-9]*' CHANGELOG.md | head -1 | grep -o '[0-9]*$')"
if [ -z "$charter" ] || [ "$charter" != "$changelog" ]; then
  echo "SQUAD.md says version '$charter' but the newest CHANGELOG.md entry is v'$changelog'"
  exit 1
fi
status=0
for manifest in mods/*/.claude-plugin/plugin.json; do
  [ -f "$manifest" ] || continue
  plugin="$(jq -r '.version // "none"' "$manifest" 2>/dev/null)"
  if [ "$plugin" != "$charter.0.0" ]; then
    echo "$manifest says version '$plugin' but the release is $charter, so it must say $charter.0.0"
    status=1
  fi
done

# The sections that changed since the last tag. Once the newest entry is tagged, the changes since
# belong to the next release, which has no entry yet, and there is nothing to compare.
last="$(git tag -l 'v[0-9]*' | sed 's/^v//' | grep -x '[0-9][0-9]*' | sort -n | tail -1)"
if [ -z "$last" ]; then
  echo "no release tag to compare SQUAD.md with: fetch the tags (git fetch --tags)"
  exit 1
fi
if [ "$charter" -gt "$last" ]; then
  # `sections <side>` prints, for each line of the charter it reads, <side>, the line's number and
  # the section it is in, such as §2.4: the last numbered heading above it, so that an unnumbered
  # one, such as §1's quick reference, stays in its section. An item of a numbered list at the
  # margin, right under a section's own heading, is a section too, as §4.1 to §4.10 are, until a
  # line at the margin outside the list. The lines before §1, where the Version line is, are in none.
  sections() {
    awk -v side="$1" '
      /^## [0-9]+\. / { s = "§" $2; sub(/\.$/, "", s); top = s; listed = 1 }
      /^### / { listed = 0; if ($2 ~ /^[0-9]+\.[0-9]+$/) s = "§" $2 }
      listed && /^[0-9]+\. / { s = top "." $1; sub(/\.$/, "", s) }
      listed && s != top && /^[^[:space:]0-9]/ { s = top }
      { print side, NR, s }'
  }
  # Every line that changed: a removed one in the tag's charter, an added one in this one, as the
  # hunks of a diff without context number them; a count left out is 1.
  changed_lines() {
    git diff -U0 --no-color "v$last" -- SQUAD.md | awk '
      /^@@ / {
        split(substr($2, 2), old, ","); split(substr($3, 2), new, ",")
        for (i = 0; i < (2 in old ? old[2] : 1); i++) print "changed old", old[1] + i
        for (i = 0; i < (2 in new ? new[2] : 1); i++) print "changed new", new[1] + i
      }'
  }
  changed="$({
    git show "v$last:SQUAD.md" 2>/dev/null | sections old
    sections new < SQUAD.md
    changed_lines
  } | awk '$1 != "changed" { at[$1 " " $2] = $3; next } { print at[$2 " " $3] }' | grep . | sort -u)"

  # The Upgrading item of the newest entry, from its first line to the next item or entry, and the
  # sections it names.
  item="$(awk '/^## v/ { n++ } n == 1' CHANGELOG.md \
    | awk '/^- / { on = /^- \*\*Upgrading/ } /^## / { on = 0 } on')"
  named=" $(grep -oE '§[0-9]+(\.[0-9]+)*' <<<"$item" | tr '\n' ' ')"
  # A range names each section between its ends, in the charter's order.
  order="$(sections new < SQUAD.md | awk '$3 != "" && $3 != last { print $3; last = $3 }')"
  while read -r from _ to; do
    [ -n "$from" ] || continue
    named="$named$(awk -v from="$from" -v to="$to" '
      { line[NR] = $0; if (!($0 in first)) first[$0] = NR; final[$0] = NR }
      END { if ((from in first) && (to in final)) for (i = first[from]; i <= final[to]; i++) printf "%s ", line[i] }' <<<"$order")"
  done < <(grep -oE '§[0-9]+(\.[0-9]+)* to §[0-9]+(\.[0-9]+)*' <<<"$item")
  where="v$charter's Upgrading item"
  [ -n "$item" ] || where="v$charter's entry, which has no Upgrading item,"
  for section in $changed; do
    parent="${section%%.*}"
    case "$named" in *" $section "*) continue ;; esac
    if [ "$parent" = "$section" ]; then
      echo "SQUAD.md's $section changed since v$last, but $where does not name it"
      status=1
    else
      case "$named" in *" $parent "*) continue ;; esac
      echo "SQUAD.md's $section changed since v$last, but $where names neither $section nor $parent"
      status=1
    fi
  done
fi
[ "$status" -eq 0 ] && echo "version $charter"
exit "$status"
