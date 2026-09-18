#!/usr/bin/env bash
# The Version line of SQUAD.md must match the newest CHANGELOG.md entry.
set -u
charter="$(grep -o '^> \*\*Version:\*\* [0-9]*' SQUAD.md | grep -o '[0-9]*$')"
changelog="$(grep -o '^## v[0-9]*' CHANGELOG.md | head -1 | grep -o '[0-9]*$')"
if [ -z "$charter" ] || [ "$charter" != "$changelog" ]; then
  echo "SQUAD.md says version '$charter' but the newest CHANGELOG.md entry is v'$changelog'"
  exit 1
fi
echo "version $charter"
