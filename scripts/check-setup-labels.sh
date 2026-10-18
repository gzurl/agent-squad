#!/usr/bin/env bash
# Check scripts/squad-setup-labels.sh (agent-squad #369) against a stub gh that keeps a repository's
# labels in a file, from a scratch checkout the squad is installed in. The labels are the real table
# of BOOTSTRAP.md, counted here on their own. A repository with no label gets them all, and a second
# run changes nothing; a wrong color or description is corrected, and a color that differs only in
# case is not; labels outside the table are listed and kept; --check writes nothing and exits 3 on a
# gap; a failed write, a failed read, bad usage, a checkout without the squad and a table that
# cannot be read each say so, with their exit status. Nothing reaches GitHub.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
setup="$root/scripts/squad-setup-labels.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-setup-labels.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }
# `check <description> <command...>` passes when the command does.
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}
# `has <line>` passes when the last run printed that line.
# shellcheck disable=SC2317,SC2329 # invoked through check
has() { grep -qxF -- "$1" <<<"$out"; }

# The table, counted here with a pattern of this check's own: every line that starts with `|`
# between its heading and the next one, after the header and the line under it, as
# "name<TAB>color<TAB>description", whether or not its name and color are in backticks. A row the
# script cannot read then fails this check (QA's finding on PR #374).
rows="$(awk '/^## / { inside = ($0 == "## Labels") } inside && /^\|/ { if (++n > 2) print }' "$root/BOOTSTRAP.md" \
  | awk -F' \\| ' '{ gsub(/^\| `?|`$/, "", $1); gsub(/`/, "", $2); sub(/ \|$/, "", $3); print $1 "\t" $2 "\t" $3 }')"
count="$(grep -c . <<<"$rows")"
check "the table of BOOTSTRAP.md has labels to check against ($count)" [ "$count" -gt 0 ]
# `row <n>` prints the name of the table's nth label, and `color_of`/`described` its color and
# description.
row() { sed -n "${1}p" <<<"$rows" | cut -f1; }
color_of() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' <<<"$rows"; }
described() { awk -F'\t' -v n="$1" '$1 == n { print $3 }' <<<"$rows"; }

# GitHub, as far as the script is concerned: the repository's labels, a JSON array in $LABELS. Each
# call is logged to $CALLS, one line, with what it read on its input. `gh label list` answers with
# them, unless STUB_LIST=fail, or STUB_LIST=hang, which never answers, its PID in $LABELS.pid;
# `gh label create <name> --color <c> --description <d> --force`
# creates or replaces one, unless its name is STUB_FAIL, which fails as gh does.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s | input: %s\n' "$*" "$(cat)" >> "$CALLS"
case "$1 $2" in
  "label list")
    [ "$*" = "label list --limit 1000 --json name,color,description" ] || exit 1
    if [ "${STUB_LIST:-}" = fail ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
    if [ "${STUB_LIST:-}" = hang ]; then echo "$$" > "$LABELS.pid"; exec sleep 60; fi
    cat "$LABELS" ;;
  "label create")
    [ "$4 $6 $8" = "--color --description --force" ] || exit 1
    if [ "$3" = "${STUB_FAIL:-}" ]; then echo "HTTP 422: Validation Failed (label $3)" >&2; exit 1; fi
    jq --arg name "$3" --arg color "$5" --arg description "$7" \
      'map(select(.name != $name)) + [{name: $name, color: $color, description: $description}]' "$LABELS" > "$LABELS.new"
    mv "$LABELS.new" "$LABELS" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH" LABELS="$lab/labels.json" CALLS="$lab/calls"

# The scratch checkout, where the squad is installed.
project="$lab/project"
git init -q "$project" && mkdir -p "$project/.agent-squad/playbook"
# `run [args]` runs the script from the checkout, with an input of its own, into out and code,
# after clearing the log; `run_in <dir> <script> [args]` runs a script from another directory.
run_in() {
  : > "$CALLS"
  out="$(cd "$1" && echo "the caller's input" | "${@:2}" 2>&1)"
  code=$?
}
run() { run_in "$project" "$setup" "$@"; }
# `table_labels` gives the repository the table's labels, as the table says.
table_labels() { jq -R 'split("\t") | {name: .[0], color: .[1], description: .[2]}' <<<"$rows" | jq -s . > "$LABELS"; }
# `writes` counts the label creations of the last run.
# shellcheck disable=SC2317,SC2329 # invoked through check
writes() { grep -c '^label create ' "$CALLS"; }
# `matches_table` passes when the repository holds every label of the table, as the table says.
# shellcheck disable=SC2317,SC2329 # invoked through check
matches_table() {
  [ "$(jq -r '.[] | [.name, .color, .description] | join("\t")' "$LABELS" | sort)" = "$(sort <<<"$rows")" ]
}

# 1. A repository with no label: --check lists them all as missing and writes nothing; a run
#    creates them, each as the table says; a second run changes nothing, and says so.
echo '[]' > "$LABELS"
run --check
check "with no label, --check exits 3, and writes nothing" bash -c '[ "$1" -eq 3 ] && ! grep -q "^label create" "$2"' _ "$code" "$CALLS"
check "it lists every label of the table as missing" bash -c '[ "$(grep -c "^labels: missing  " <<<"$1")" -eq "$2" ]' _ "$out" "$count"
check "and says how to fix them" has "labels: $count to create or correct; run squad-setup-labels.sh without --check to do it"
run
check "a run creates every label: exit 0, one creation per label" bash -c '[ "$1" -eq 0 ] && [ "$2" -eq "$3" ]' _ "$code" "$(writes)" "$count"
check "each as the table says" matches_table
check "naming each" has "labels: created  $(row 1)"
check "with the summary" has "labels: $count created, 0 corrected; the other 0 were as the table says"
run
check "a second run writes nothing, exit 0, and says so" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" -eq 0 ] && [ "$3" = "labels: every label of the table is there, as the table says" ]' _ "$code" "$(writes)" "$out"
run --check
check "and --check then passes, with the same line" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" = "labels: every label of the table is there, as the table says" ]' _ "$code" "$out"

# 2. A wrong color, a wrong description, a missing one, and a color in other case, which is the same.
first="$(row 1)" second="$(row 2)" third="$(row 3)" fourth="$(row 4)"
table_labels
jq --arg a "$first" --arg b "$second" --arg c "$third" --arg d "$fourth" \
  'map(if .name == $a then .color = "000000" elif .name == $b then .description = "Old words" elif .name == $d then .color |= ascii_downcase else . end
       | select(.name != $c))' "$LABELS" > "$LABELS.new" && mv "$LABELS.new" "$LABELS"
run --check
check "--check names a wrong color, with the table's" has "labels: differs  $first: color 000000, where the table says $(color_of "$first")"
check "a wrong description, with the table's" has "labels: differs  $second: description \"Old words\", where the table says \"$(described "$second")\""
check "and a missing label" has "labels: missing  $third"
check "but not a color that differs only in case, and exits 3, writing nothing" \
  bash -c '! grep -qF "$1" <<<"$2" && [ "$3" -eq 3 ] && ! grep -q "^label create" "$4"' _ "$fourth" "$out" "$code" "$CALLS"
run
check "a run corrects and creates them: exit 0, three writes" bash -c '[ "$1" -eq 0 ] && [ "$2" -eq 3 ]' _ "$code" "$(writes)"
check "naming what it corrected" has "labels: corrected  $first: color 000000, where the table says $(color_of "$first")"
check "and what it created" has "labels: created  $third"
check "with the summary" has "labels: 1 created, 2 corrected; the other $((count - 3)) were as the table says"
check "the label in other case keeps its color" \
  bash -c '[ "$(jq -r --arg d "$1" ".[] | select(.name == \$d) | .color" "$2")" = "$(tr "[:upper:]" "[:lower:]" <<<"$3")" ]' _ "$fourth" "$LABELS" "$(color_of "$fourth")"

# 3. Labels outside the table are listed and kept, and fail nothing; a label with no description
#    differs from the table's.
table_labels
jq --arg a "$first" 'map(if .name == $a then .description = null else . end)
  + [{name: "bug", color: "d73a4a", description: "Something isn'"'"'t working"}, {name: "wontfix", color: "ffffff", description: ""}]' \
  "$LABELS" > "$LABELS.new" && mv "$LABELS.new" "$LABELS"
run
check "labels outside the table are listed as kept" \
  bash -c 'grep -qxF "labels: not in the table, kept  bug" <<<"$1" && grep -qxF "labels: not in the table, kept  wontfix" <<<"$1"' _ "$out"
check "and kept: never deleted" bash -c '[ "$(jq "[.[] | select(.name == \"bug\" or .name == \"wontfix\")] | length" "$1")" -eq 2 ]' _ "$LABELS"
check "a label with no description is corrected" has "labels: corrected  $first: description \"\", where the table says \"$(described "$first")\""
check "and the run exits 0" [ "$code" -eq 0 ]
run --check
check "with only labels outside the table, --check passes" [ "$code" -eq 0 ]

# 4. A label that cannot be written: the others are written, gh's message shown, exit 1.
echo '[]' > "$LABELS"
STUB_FAIL="$second" run
check "a failed write: exit 1, with gh's message" \
  bash -c '[ "$1" -eq 1 ] && grep -qxF "HTTP 422: Validation Failed (label $2)" <<<"$3"' _ "$code" "$second" "$out"
check "naming the label" has "labels: FAILED  $second could not be written, as gh says above"
check "after writing the others" bash -c '[ "$(jq length "$1")" -eq $(($2 - 1)) ]' _ "$LABELS" "$count"
check "and saying how many failed" bash -c '[ "$(tail -1 <<<"$1")" = "labels: 1 could not be written" ]' _ "$out"

# 5. Labels that cannot be read: exit 1, gh's message, nothing written.
STUB_LIST=fail run
check "a failed read: exit 1, with gh's message, and nothing more" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "HTTP 502: Bad Gateway"$'\''\n'\''"labels: cannot read the repository'\''s labels, as gh says above" ]' _ "$code" "$out"
#    A read that never answers is stopped after SQUAD_GH_TIMEOUT seconds of wall-clock time, saying
#    so above the same line (agent-squad #435).
started=$SECONDS
STUB_LIST=hang SQUAD_GH_TIMEOUT=1 run
check "a read that never answers: exit 1 after the bound, saying so, and nothing left running" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" -le 5 ] && [ "$3" = "squad-timeout: gh did not end within 1 s, so it was stopped"$'\''\n'\''"labels: cannot read the repository'\''s labels, as gh says above" ] \
    && ! kill -0 "$(cat "$4")" 2>/dev/null' _ "$code" "$((SECONDS - started))" "$out" "$LABELS.pid"

# 6. gh gets no input from the caller: the script never waits on its input.
table_labels && run
check "gh reads no input of the caller's" bash -c '[ -s "$1" ] && ! grep -q "| input: ." "$1"' _ "$CALLS"

# 7. Bad usage, a checkout without the squad, and a table that cannot be read: exit 2, saying so,
#    before anything reaches GitHub.
for args in "--chek" "--check --check" "check"; do
  # shellcheck disable=SC2086 # the arguments are split on purpose
  run $args
  check "'$args' is bad usage: exit 2, and nothing sent" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "usage: squad-setup-labels.sh [--check]" ] && [ ! -s "$3" ]' _ "$code" "$out" "$CALLS"
done
mkdir -p "$lab/bare" && git init -q "$lab/plain"
for dir in "$lab/bare" "$lab/plain"; do
  run_in "$dir" "$setup"
  check "from ${dir#"$lab/"}, no checkout the squad is installed in: exit 2, and nothing sent" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "labels: run it from a checkout of a project the squad is installed in" ] && [ ! -s "$3" ]' _ "$code" "$out" "$CALLS"
done
mkdir -p "$lab/playbook/scripts" && cp "$setup" "$lab/playbook/scripts/"
for bootstrap in missing "# Bootstrap"$'\n'"## Labels"$'\n'"none here"; do
  [ "$bootstrap" = missing ] || printf '%s\n' "$bootstrap" > "$lab/playbook/BOOTSTRAP.md"
  run_in "$project" "$lab/playbook/scripts/squad-setup-labels.sh"
  check "a table that cannot be read ($([ "$bootstrap" = missing ] && echo missing || echo empty)): exit 2, and nothing sent" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "labels: no label can be read from the Labels table of $3/scripts/../BOOTSTRAP.md" ] && [ ! -s "$4" ]' \
    _ "$code" "$out" "$lab/playbook" "$CALLS"
done
# A row that does not read as the table's shape, its name or its color out of backticks, is refused
# by name, and nothing is compared: the label would otherwise never be created, with --check saying
# every label is there (QA's finding on PR #374).
for bad in '| 🆕 new | `112233` | A new label |' '| `🆕 new` | 112233 | A new label |'; do
  awk -v bad="$bad" '{ print } /status:blocked/ { print bad }' "$root/BOOTSTRAP.md" > "$lab/playbook/BOOTSTRAP.md"
  run_in "$project" "$lab/playbook/scripts/squad-setup-labels.sh" --check
  check "a row out of the table's shape ($bad): exit 2, naming it, and nothing sent" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "labels: a row of the Labels table of $3/scripts/../BOOTSTRAP.md cannot be read, so it compared and wrote nothing: $4" ] && [ ! -s "$5" ]' \
      _ "$code" "$out" "$lab/playbook" "$bad" "$CALLS"
done

exit "$status"
