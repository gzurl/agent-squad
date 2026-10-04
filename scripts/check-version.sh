#!/usr/bin/env bash
# The Version line of SQUAD.md must match the newest CHANGELOG.md entry, and the version of every
# plugin in mods/ must be that release's, N.0.0 for version N (agent-squad #206).
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
[ "$status" -eq 0 ] && echo "version $charter"
exit "$status"
