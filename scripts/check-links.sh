#!/usr/bin/env bash
# Check that every relative Markdown link in the repository points at an existing file.
set -u
status=0
while IFS= read -r file; do
  # Extract link targets of the form [text](target), ignore URLs and anchors-only links.
  grep -o '\](\([^)]*\))' "$file" | sed 's/^](//; s/)$//' | while IFS= read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|'#'*) continue ;;
    esac
    path="${target%%#*}"
    [ -z "$path" ] && continue
    if [ ! -e "$(dirname "$file")/$path" ]; then
      echo "broken link in $file: $target"
      exit 1
    fi
  done || status=1
# templates/ holds skeletons whose links resolve once copied into a project.
done < <(git ls-files '*.md' | grep -v '^templates/')
exit $status
