#!/usr/bin/env bash
# Check scripts/squad-set-status.sh (agent-squad #367) against a stub gh that keeps one item's
# labels in a file, applies each edit to them as GitHub does, and answers the read-back from them.
# Each state of each kind is set in one edit that adds its label and removes the other three, never
# the one it adds, and leaves the other labels alone; `none` removes all four; the read-back passes
# only on exactly the state asked for. A read-back that finds two states, or a status label with
# another emoji, fails; so do a failed edit and a failed read, with gh's message. Bad usage exits 2
# with nothing sent to GitHub, and the script passes gh no input of its own. Nothing reaches GitHub.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
set_status="$root/scripts/squad-set-status.sh"

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-set-status.XXXXXX")" || exit 2
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

IN_PROGRESS="🚧 status:in-progress" IN_REVIEW="👀 status:in-review" BLOCKED="⛔ status:blocked" APPROVED="✅ status:approved"

# GitHub, as far as the script is concerned: the item's labels, one per line in $LABELS. Each call
# is logged to $CALLS, one argument per line after a `call` line, with what it read on its input.
# `gh <issue|pr> edit <n> --add-label <l> --remove-label <l>...` applies the edit, unless
# STUB_EDIT=fail, which fails as gh does on a label the repository lacks, or STUB_EDIT=ignored,
# which changes nothing, as when someone else edits the labels at the same moment. `gh api
# repos/{owner}/{repo}/issues/<n> --jq <filter>` answers with the labels, unless STUB_READ=fail.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
{ echo call; printf '%s\n' "$@"; printf 'input: %s\n' "$(cat)"; } >> "$CALLS"
case "$1 $2" in
  "issue edit"|"pr edit")
    if [ "${STUB_EDIT:-}" = fail ]; then
      echo "failed to update https://github.com/o/r/issues/$3: '⛔ status:blocked' not found" >&2
      exit 1
    fi
    [ "${STUB_EDIT:-}" != ignored ] || exit 0
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --add-label) grep -qxF -- "$2" "$LABELS" || echo "$2" >> "$LABELS" ;;
        --remove-label) grep -vxF -- "$2" "$LABELS" > "$LABELS.new"; mv "$LABELS.new" "$LABELS" ;;
        *) exit 1 ;;
      esac
      shift 2
    done
    echo "https://github.com/o/r/issues/1" ;;
  "api repos/{owner}/{repo}/issues/"*)
    if [ "${STUB_READ:-}" = fail ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
    [ "$3" = --jq ] || exit 1
    jq -R . "$LABELS" | jq -s '{labels: map({name: .})}' | jq -r "$4" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH" LABELS="$lab/labels" CALLS="$lab/calls"

# `labels <label>...` gives the item those labels; `run <args>...` runs the script on it, with an
# input of its own, into out and code, after clearing the log.
labels() { printf '%s\n' "$@" > "$LABELS"; }
run() {
  : > "$CALLS"
  out="$(echo "the caller's input" | "$set_status" "$@" 2>&1)"
  code=$?
}
# `edited_with <arg>...` passes when the script's one edit had exactly those arguments.
# shellcheck disable=SC2317,SC2329 # invoked through check
edited_with() { [ "$(sed -n '2,/^input: /p' "$CALLS" | sed '$d')" = "$(printf '%s\n' "$@")" ]; }
# `carries <label>...` passes when the item's labels are those, in any order.
# shellcheck disable=SC2317,SC2329 # invoked through check
carries() { [ "$(sort "$LABELS")" = "$(printf '%s\n' "$@" | sort)" ]; }

# 1. Each state of each kind, from an item that carries another state and labels of its own.
for kind in issue pr; do
  for state in in-progress in-review blocked approved; do
    case "$kind:$state" in issue:approved|pr:blocked) continue ;; esac
    case "$state" in
      in-progress) label="$IN_PROGRESS" ;; in-review) label="$IN_REVIEW" ;; blocked) label="$BLOCKED" ;; approved) label="$APPROVED" ;;
    esac
    others=()
    for each in "$IN_PROGRESS" "$IN_REVIEW" "$BLOCKED" "$APPROVED"; do [ "$each" = "$label" ] || others+=(--remove-label "$each"); done
    before="$IN_REVIEW"
    [ "$state" != in-review ] || before="$IN_PROGRESS"
    labels "🔴 P1" "$before" "👨🏼‍💻 owner:dev"
    run "$kind" 12 "$state"
    name="PR #12"
    [ "$kind" != issue ] || name="issue #12"
    check "$kind $state: exit 0, saying so" bash -c '[ "$1" -eq 0 ] && [ "$2" = "$3" ]' _ "$code" "$out" "status: $name is $label"
    check "$kind $state: one edit, which adds the label and removes the other three, never the one it adds" \
      edited_with "$kind" edit 12 --add-label "$label" "${others[@]}"
    check "$kind $state: then one read-back, and no other call" \
      bash -c '[ "$(grep -c "^call$" "$1")" -eq 2 ] && grep -qxF "repos/{owner}/{repo}/issues/12" "$1"' _ "$CALLS"
    check "$kind $state: the item carries the label, and its other labels as they were" carries "🔴 P1" "$label" "👨🏼‍💻 owner:dev"
  done
done

# 2. none removes all four, and keeps the other labels.
for kind in issue pr; do
  labels "$IN_REVIEW" "✨ feature"
  run "$kind" 7 none
  name="PR #7"
  [ "$kind" != issue ] || name="issue #7"
  check "$kind none: exit 0, saying so" bash -c '[ "$1" -eq 0 ] && [ "$2" = "$3" ]' _ "$code" "$out" "status: $name has no status label"
  check "$kind none: one edit, which removes the four" \
    edited_with "$kind" edit 7 --remove-label "$IN_PROGRESS" --remove-label "$IN_REVIEW" --remove-label "$BLOCKED" --remove-label "$APPROVED"
  check "$kind none: the item keeps its other labels alone" carries "✨ feature"
done

# 3. gh gets no input from the caller: the script never waits on its input.
check "gh reads no input of the caller's" bash -c '! grep -q "^input: ." "$1"' _ "$CALLS"

# 4. A read-back that finds another state than the one asked for fails, naming what it found: two
#    states, left by an edit that changed nothing, a status label with another emoji, and a state
#    left where none was asked.
labels "$IN_PROGRESS" "$IN_REVIEW"
STUB_EDIT=ignored run issue 9 in-review
check "two states after the edit: exit 1, naming both" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "$3" ]' _ "$code" "$out" "status FAILED: issue #9 carries $IN_PROGRESS, $IN_REVIEW, where $IN_REVIEW was asked"
labels "🔵 status:in-review"
STUB_EDIT=ignored run pr 9 in-review
check "a status label with another emoji is not the one asked for" \
  has "status FAILED: PR #9 carries 🔵 status:in-review, where $IN_REVIEW was asked"
labels "$BLOCKED"
STUB_EDIT=ignored run issue 9 none
check "a state left where none was asked" has "status FAILED: issue #9 carries $BLOCKED, where none was asked"
labels "✨ feature"
STUB_EDIT=ignored run issue 9 blocked
check "and no state where one was asked" has "status FAILED: issue #9 carries no status label, where $BLOCKED was asked"

# 5. A failed edit fails, with gh's message, and says what the item carries; so does a failed read,
#    and both together.
labels "$IN_PROGRESS"
STUB_EDIT=fail run issue 5 blocked
check "a failed edit: exit 1, with gh's message" \
  bash -c '[ "$1" -eq 1 ] && grep -qxF "failed to update https://github.com/o/r/issues/5: '\''⛔ status:blocked'\'' not found" <<<"$2"' _ "$code" "$out"
check "and what the item carries, read back" has "status FAILED: cannot edit issue #5, as gh says above; it carries $IN_PROGRESS"
STUB_READ=fail run pr 5 approved
check "a failed read: exit 1, with gh's message, and nothing more" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "HTTP 502: Bad Gateway"$'\''\n'\''"status FAILED: cannot read the labels of PR #5, as gh says above" ]' _ "$code" "$out"
STUB_EDIT=fail STUB_READ=fail run issue 5 none
check "both: exit 1, naming both, and nothing more" \
  bash -c '[ "$1" -eq 1 ] && [ "$(tail -1 <<<"$2")" = "status FAILED: cannot edit issue #5, as gh says above; cannot read the labels of issue #5, as gh says above" ] && [ "$(grep -c "^status" <<<"$2")" -eq 1 ]' _ "$code" "$out"

# 6. Bad usage exits 2, saying why and how to use it, before anything reaches GitHub.
usage="usage: squad-set-status.sh <issue|pr> <number> <in-progress|in-review|blocked|approved|none>"
while IFS='|' read -r reason args; do
  # shellcheck disable=SC2086 # the arguments are split on purpose
  run $args
  check "'$args' is bad usage: exit 2, $reason, and nothing sent" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "status: $3"$'\''\n'\''"$4" ] && [ ! -s "$5" ]' _ "$code" "$out" "$reason" "$usage" "$CALLS"
done <<'CASES'
it takes three arguments, not 0|
it takes three arguments, not 2|issue 12
it takes three arguments, not 4|issue 12 in-review now
the kind is issue or pr, not 'issues'|issues 12 in-review
the number is a plain integer, not '12a'|issue 12a in-review
the number is a plain integer, not '#12'|pr #12 in-review
the number is a plain integer, not '$(id)'|pr $(id) in-review
the state is in-progress, in-review, blocked, approved or none, not 'review'|issue 12 review
approved is a PR's state, not an issue's (SQUAD.md §3)|issue 12 approved
blocked is an issue's state, not a PR's (SQUAD.md §3)|pr 12 blocked
CASES
run issue "" in-review
check "an empty number is bad usage too" bash -c '[ "$1" -eq 2 ] && [ ! -s "$2" ]' _ "$code" "$CALLS"

exit "$status"
