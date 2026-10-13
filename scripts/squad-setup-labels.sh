#!/usr/bin/env bash
# Create and check the squad's labels on GitHub (agent-squad #369), from the one table that lists
# them: the *Labels* table of BOOTSTRAP.md, next to this script in the playbook. Each label of the
# table that the repository lacks is created, and each whose color or description differs is
# corrected, with `gh label create … --force`; a label that matches is left alone, so a second run
# changes nothing and says so. Names compare exactly, and colors whatever their case. It never
# deletes a label: it lists those the repository has outside the table, GitHub's defaults or the
# project's own, for the CTO to decide about with the CEO (BOOTSTRAP.md row 7). It works on the
# repository the checkout names, as gh reads it there.
#
# Usage: squad-setup-labels.sh [--check]
#   --check writes nothing: it lists each label that is missing or differs, and exits 0 only when
#   none does.
# Output: one line per label it creates or corrects (with --check, that is missing or differs),
# one per label outside the table, then a summary:
#   labels: created  🚧 status:in-progress
#   labels: corrected  🔴 P1: color f00000, where the table says F9C0C0
#   labels: missing  🚧 status:in-progress
#   labels: differs  🔴 P1: description "Urgent", where the table says "Must do next"
#   labels: not in the table, kept  bug
#   labels: 2 created, 1 corrected; the other 14 were as the table says
#   labels: every label of the table is there, as the table says
# Exit: 0 done, or with --check nothing missing or different; 1 GitHub could not be read, or a
#   label could not be written, with gh's message; 2 bad usage, or not run from a checkout of a
#   project the squad is installed in; 3 with --check, a label missing or different.
set -u
usage="usage: squad-setup-labels.sh [--check]"
check=false
case "$*" in
  "") ;;
  --check) check=true ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

# The table, from the playbook this script belongs to; and a checkout the squad is installed in.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [ -z "$common" ] || [ ! -d "$(dirname "$common")/.agent-squad/playbook" ]; then
  echo "labels: run it from a checkout of a project the squad is installed in" >&2
  exit 2
fi
bootstrap="$(dirname "$0")/../BOOTSTRAP.md"
# Every row of the table, which is every line that starts with `|` between its heading and the
# next one, after the header and the line under it. Each reads as
# `| `<name>` | `<color>` | <description> |`, one JSON object per label. A row that does not is
# refused by name, since a label the script skipped would read as there, and never be created
# (QA's finding on PR #374).
# shellcheck disable=SC2016 # the backticks are the table's, around each name and color
table="$(awk '/^## / { inside = ($0 == "## Labels") } inside && /^\|/ { if (++rows > 2) print }' "$bootstrap" 2>/dev/null \
  | jq -R '. as $row | capture("^\\| `(?<name>[^`]+)` \\| `(?<color>[0-9A-Fa-f]{6})` \\| (?<description>.*) \\|$") // {unread: $row}' | jq -s .)"
if [ "$(jq length <<<"$table")" -eq 0 ]; then
  echo "labels: no label can be read from the Labels table of $bootstrap" >&2
  exit 2
fi
unread="$(jq -r 'first(.[] | .unread // empty)' <<<"$table")"
if [ -n "$unread" ]; then
  echo "labels: a row of the Labels table of $bootstrap cannot be read, so it compared and wrote nothing: $unread" >&2
  exit 2
fi

# The repository's labels, and what each label of the table needs: nothing, to be created, or to be
# corrected, with what differs; then the labels outside the table.
repo="$(gh label list --limit 1000 --json name,color,description </dev/null)" || {
  echo "labels: cannot read the repository's labels, as gh says above" >&2
  exit 1
}
plan="$(jq -r --argjson table "$table" '
  (map({key: .name, value: .}) | from_entries) as $have
  | ($table[] | . as $want | $have[$want.name] as $got
    | if $got == null then ["missing", .name, .color, .description, ""]
      else ([if ($got.color | ascii_downcase) != ($want.color | ascii_downcase)
               then "color \($got.color), where the table says \($want.color)" else empty end,
             if ($got.description // "") != $want.description
               then "description \"\($got.description // "")\", where the table says \"\($want.description)\"" else empty end]
            | join("; ")) as $diff
        | if $diff == "" then ["same", $want.name] else ["differs", $want.name, $want.color, $want.description, $diff] end
      end),
    (.[] | select(.name | IN($table[].name) | not) | ["extra", .name])
  | join("\t")' <<<"$repo")"

created=0 corrected=0 same=0 to_fix=0 failed=0
while IFS=$'\t' read -r what name color description diff; do
  case "$what" in
    same) same=$((same + 1)) ;;
    extra) echo "labels: not in the table, kept  $name" ;;
    missing|differs)
      if $check; then
        echo "labels: $what  $name${diff:+: $diff}"
        to_fix=$((to_fix + 1))
      elif gh label create "$name" --color "$color" --description "$description" --force </dev/null >/dev/null; then
        if [ "$what" = missing ]; then
          echo "labels: created  $name"
          created=$((created + 1))
        else
          echo "labels: corrected  $name: $diff"
          corrected=$((corrected + 1))
        fi
      else
        echo "labels: FAILED  $name could not be written, as gh says above" >&2
        failed=$((failed + 1))
      fi
      ;;
  esac
done <<<"$plan"

# The summary, and the exit status it calls for.
if [ $((created + corrected + to_fix + failed)) -eq 0 ]; then
  echo "labels: every label of the table is there, as the table says"
elif $check; then
  echo "labels: $to_fix to create or correct; run squad-setup-labels.sh without --check to do it"
  exit 3
else
  echo "labels: $created created, $corrected corrected; the other $same were as the table says"
fi
[ "$failed" -eq 0 ] || { echo "labels: $failed could not be written" >&2; exit 1; }
exit 0
