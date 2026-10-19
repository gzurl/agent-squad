#!/usr/bin/env bash
# Check scripts/squad-set-status.sh (agent-squad #367) against a stub gh that keeps one item's
# labels in a file, applies each edit to them as GitHub does, and answers the read-back from them.
# Each state of each kind is set in one edit that adds its label and removes the other three, never
# the one it adds, and leaves the other labels alone; `none` removes all four; the read-back passes
# only on exactly the state asked for. A read-back that finds two states, or a status label with
# another emoji, fails; so do a failed edit and a failed read, with gh's message. Bad usage exits 2
# with nothing sent to GitHub, and the script passes gh no input of its own. A number of the other
# kind, an issue's for a PR or the converse, is refused before anything is written (agent-squad
# #375). Nothing reaches GitHub.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-set-status.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

# The script runs from a copy beside a stub squad-plan.sh, which it calls once a state is read back
# (agent-squad #370). The stub logs each call to $PLAN_CALLS, with what it read on its input, prints
# what the real one prints, and fails when STUB_PLAN=fail.
mkdir -p "$lab/playbook/scripts" && cp "$root/scripts/squad-set-status.sh" "$root/scripts/squad-timeout.sh" "$lab/playbook/scripts/"
set_status="$lab/playbook/scripts/squad-set-status.sh"
cat > "$lab/playbook/scripts/squad-plan.sh" <<'PLAN'
#!/usr/bin/env bash
printf '%s | input: %s\n' "$*" "$(cat)" >> "$PLAN_CALLS"
echo "| 1 | #12 a row of the table |"
[ "${STUB_PLAN:-}" != fail ] || { echo "HTTP 502: Bad Gateway" >&2; echo "plan: cannot read the open issues, as gh says above" >&2; exit 1; }
echo "plan: #9 updated"
PLAN
chmod +x "$lab/playbook/scripts/squad-plan.sh"
export PLAN_CALLS="$lab/plan-calls"

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
# repos/{owner}/{repo}/issues/<n> --jq <filter>` answers with the labels, and with a pull_request
# key when ITEM_KIND is pr, as the API answers for a PR, unless STUB_READ=fail, which fails every
# read, or STUB_READ=back, which fails every read after the first, or STUB_READ=hang, which never
# answers, its PID in $lab/hung.pid.
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
    if [ "${STUB_READ:-}" = hang ]; then echo "$$" > "$(dirname "$LABELS")/hung.pid"; exec sleep 60; fi
    if [ "${STUB_READ:-}" = fail ] || { [ "${STUB_READ:-}" = back ] && [ "$(grep -c '^api$' "$CALLS")" -ge 2 ]; }; then
      echo "HTTP 502: Bad Gateway" >&2
      exit 1
    fi
    [ "$3" = --jq ] || exit 1
    jq -R . "$LABELS" | jq -s --arg kind "${ITEM_KIND:-issue}" \
      '{labels: map({name: .})} + (if $kind == "pr" then {pull_request: {}} else {} end)' | jq -r "$4" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH" LABELS="$lab/labels" CALLS="$lab/calls"

# `labels <label>...` gives the item those labels; `run <args>...` runs the script on it, with an
# input of its own, into out and code, after clearing the log. The item is of the kind the run
# names, unless ITEM_KIND says otherwise.
labels() { printf '%s\n' "$@" > "$LABELS"; }
run() {
  : > "$CALLS" && : > "$PLAN_CALLS"
  out="$(echo "the caller's input" | ITEM_KIND="${ITEM_KIND:-${1:-}}" "$set_status" "$@" 2>&1)"
  code=$?
}
# `edited_with <arg>...` passes when the script made one edit, with exactly those arguments.
# shellcheck disable=SC2317,SC2329 # invoked through check
edited_with() {
  [ "$(awk '/^call$/ { block = ""; inside = 1; next }
    inside && /^input: / { if (block ~ /^(issue|pr)\nedit\n/) printf "%s", block; inside = 0; next }
    inside { block = block $0 "\n" }' "$CALLS")" = "$(printf '%s\n' "$@")" ]
}
# `calls` prints the first word of each call the last run made, in order.
calls() { awk 'previous == "call" { printf "%s ", $0 } { previous = $0 }' "$CALLS"; }
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
    check "$kind $state: a read of its kind before the edit, a read-back after it, and no other call" \
      bash -c '[ "$1" = "api $2 api " ] && [ "$(grep -cxF "repos/{owner}/{repo}/issues/12" "$3")" -eq 2 ]' _ "$(calls)" "$kind" "$CALLS"
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
STUB_READ=back run pr 5 approved
check "a failed read-back: exit 1, with gh's message, and nothing more" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "HTTP 502: Bad Gateway"$'\''\n'\''"status FAILED: cannot read the labels of PR #5, as gh says above" ]' _ "$code" "$out"
STUB_EDIT=fail STUB_READ=back run issue 5 none
check "both: exit 1, naming both, and nothing more" \
  bash -c '[ "$1" -eq 1 ] && [ "$(tail -1 <<<"$2")" = "status FAILED: cannot edit issue #5, as gh says above; cannot read the labels of issue #5, as gh says above" ] && [ "$(grep -c "^status" <<<"$2")" -eq 1 ]' _ "$code" "$out"

# 6. A number of the other kind is refused before anything is written (agent-squad #375): the
#    API answers issues/<n> for a PR too, and gh issue edit would edit it. So is an item whose kind
#    cannot be read.
labels "$IN_REVIEW"
ITEM_KIND="pr" run issue 372 none
check "an issue command on a PR's number: exit 1, saying so" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "status FAILED: #372 is a PR, not an issue; nothing was written" ]' _ "$code" "$out"
check "after one read, and no edit" bash -c '[ "$1" = "api " ]' _ "$(calls)"
check "the PR keeps its state" carries "$IN_REVIEW"
ITEM_KIND="issue" run pr 367 approved
check "a PR command on an issue's number: exit 1, saying so, and no edit" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "status FAILED: #367 is an issue, not a PR; nothing was written" ] && [ "$3" = "api " ]' _ "$code" "$out" "$(calls)"
STUB_READ=fail run issue 5 none
check "an item whose kind cannot be read: exit 1, with gh's message, and no edit" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "HTTP 502: Bad Gateway"$'\''\n'\''"status FAILED: cannot read issue #5, as gh says above; nothing was written" ] && [ "$3" = "api " ]' _ "$code" "$out" "$(calls)"
#    A read that never answers is stopped after SQUAD_GH_TIMEOUT seconds of wall-clock time, saying
#    so above the same line, and nothing is written (agent-squad #435).
started=$SECONDS
STUB_READ=hang SQUAD_GH_TIMEOUT=1 run issue 5 none
# Within 30 s: well under its stub's 60 s, and over what CI's kcov takes (agent-squad #447).
check "a read that never answers: exit 1 after the bound, saying so, no edit, and nothing left running" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" -le 30 ] && [ "$3" = "squad-timeout: gh did not end within 1 s, so it was stopped"$'\''\n'\''"status FAILED: cannot read issue #5, as gh says above; nothing was written" ] \
    && [ "$4" = "api " ] && ! kill -0 "$(cat "$5")" 2>/dev/null' _ "$code" "$((SECONDS - started))" "$out" "$(calls)" "$lab/hung.pid"

# 7. The plan's table follows a state read back, and only then (agent-squad #370): squad-plan.sh
#    --update runs once, with no input of the caller's, and prints nothing. Its failure is one
#    warning, and the state's exit status stands.
labels "$IN_PROGRESS"
run issue 12 in-review
check "a state read back: squad-plan.sh --update runs once, with no input, and prints nothing" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" = "status: issue #12 is $3" ] && [ "$(cat "$4")" = "--update | input: " ]' _ "$code" "$out" "$IN_REVIEW" "$PLAN_CALLS"
STUB_PLAN=fail run issue 12 none
check "a failed table update: exit 0 still, the state's line, then one warning" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" = "status: issue #12 has no status label"$'\''\n'\''"status: warning: the plan'\''s table could not be updated; the next update corrects it" ]' _ "$code" "$out"
for failing in "STUB_EDIT=ignored issue 12 in-review" "ITEM_KIND=pr issue 12 none" "STUB_EDIT=fail issue 12 none" "STUB_READ=back pr 12 approved" "issue 12 review"; do
  labels "$IN_PROGRESS"
  # The words: an assignment for the stubs, or none, then the arguments.
  read -ra env_and_args <<<"$failing"
  if [[ "${env_and_args[0]}" == *=* ]]; then
    export "${env_and_args[0]?}" && run "${env_and_args[@]:1}" && unset "${env_and_args[0]%%=*}"
  else
    run "${env_and_args[@]}"
  fi
  check "no table update after a run that fails ($failing)" bash -c '[ "$1" -ne 0 ] && [ ! -s "$2" ]' _ "$code" "$PLAN_CALLS"
done

# 8. Bad usage exits 2, saying why and how to use it, before anything reaches GitHub.
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
