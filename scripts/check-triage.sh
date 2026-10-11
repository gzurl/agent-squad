#!/usr/bin/env bash
# Check the triage workflow (agent-squad #281): an issue or a pull request opened by an account
# outside the squad gets 📥 needs-triage, and one opened from inside gets nothing. It reads
# .github/workflows/triage.yml and pins the three rules that keep a pull_request_target workflow
# safe: no code checked out, no title or body in any command, and no permission beyond writing
# issues and pull requests. Then it runs the workflow's own step, as written there, with each author
# association GitHub reports and a gh that records its calls. This script touches neither its
# repository nor GitHub.
# shellcheck disable=SC2016 # the programs given to bash -c expand their own arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
workflow="$root/.github/workflows/triage.yml"
[ -f "$workflow" ] || { echo "check-triage: $workflow is missing" >&2; exit 2; }
label="📥 needs-triage"

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-triage.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }
# `check <description> <command...>` passes when the command succeeds.
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}

# The workflow, read as text: it is this repository's own, and kept simple enough for that.
# `block <key>` prints the lines nested under a top-level key, such as `on:` or `permissions:`.
block() { awk -v key="$1:" '$0 == key { inside = 1; next } /^[^ #]/ { inside = 0 } inside && NF' "$workflow"; }
# `run_script` prints the step's run: | script, without its indentation. The workflow has one step.
run_script() {
  awk '/^ *run: \|$/ { indent = index($0, "r") - 1; inside = 1; next }
       inside && NF && (match($0, /^ */) && RLENGTH <= indent) { inside = 0 }
       inside { print substr($0, indent + 3) }' "$workflow"
}
script="$(run_script)"

# 1. When it runs: an issue or a pull request opened, nothing else.
check "it runs when an issue or a pull request is opened, and on nothing else" \
  [ "$(block on)" = "$(printf '  issues:\n    types: [opened]\n  pull_request_target:\n    types: [opened]')" ]

# 2. The three rules.
check "it checks out no code: no step uses an action, and no command fetches the repository" \
  bash -c '! grep -qE "^[[:space:]]*-?[[:space:]]*uses:|checkout|git (clone|fetch|pull)|gh (pr|repo) (checkout|clone)" "$1"' _ "$workflow"
# Every expression in the file is one of these four, and none is inside the script.
allowed='github.token
github.repository
github.event.issue.number || github.event.pull_request.number
github.event.issue.author_association || github.event.pull_request.author_association'
expressions="$(grep -oE '\$\{\{[^}]*\}\}' "$workflow" | sed -E 's/^\$\{\{ *//; s/ *\}\}$//' | LC_ALL=C sort -u)"
check "its only expressions are the token, the repository, the number and the author's association" \
  [ "$expressions" = "$(printf '%s\n' "$allowed" | LC_ALL=C sort -u)" ]
check "so no title, no body and no other text of what was opened reaches it" \
  bash -c '! grep -qE "github\.event\.[a-z_]+\.(title|body|head|user|labels)|github\.head_ref" "$1"' _ "$workflow"
check "and its script reads them only from the environment, with no expression inside it" \
  bash -c '[ -n "$1" ] && ! grep -qF "\${{" <<<"$1"' _ "$script"
check "its token may write issues and pull requests, nothing more" \
  [ "$(block permissions)" = "$(printf '  issues: write\n  pull-requests: write')" ]
check "and no job asks for other permissions" [ "$(grep -c 'permissions:' "$workflow")" -eq 1 ]

# 3. The step itself, as the workflow has it, for each association GitHub reports. Its gh records
#    each call, one argument per line, and a blank line after it.
mkdir -p "$lab/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" "" >> "%s/calls.txt"\n' "$lab" > "$lab/bin/gh"
chmod +x "$lab/bin/gh"
# `run_step <number> <association>` runs the script and prints the calls it made to gh.
run_step() {
  rm -f "$lab/calls.txt"
  PATH="$lab/bin:$PATH" GH_TOKEN=x REPO=o/r NUMBER="$1" ASSOCIATION="$2" bash -c "$script" >/dev/null 2>&1 || return
  cat "$lab/calls.txt" 2>/dev/null
}
labelled="$(printf '%s\n' api --method POST repos/o/r/issues/7/labels -f "labels[]=$label" '')"
for association in OWNER MEMBER COLLABORATOR; do
  check "an author who is $association is inside: no label" [ -z "$(run_step 7 "$association")" ]
done
for association in CONTRIBUTOR FIRST_TIME_CONTRIBUTOR FIRST_TIMER MANNEQUIN NONE; do
  check "an author who is $association is outside: $label, added once" [ "$(run_step 7 "$association")" = "$labelled" ]
done
rm -f "$lab/calls.txt"
check "a number that is not one stops the step, with no call to gh" \
  bash -c '! (PATH="$1/bin:$PATH" REPO=o/r NUMBER="7; touch $1/ran" ASSOCIATION=NONE bash -c "$2" >/dev/null 2>&1) \
    && [ ! -e "$1/calls.txt" ] && [ ! -e "$1/ran" ]' _ "$lab" "$script"

# 4. The label is the one BOOTSTRAP.md has the CTO create.
check "the label is in BOOTSTRAP.md's table of labels" grep -qF "| \`$label\` |" "$root/BOOTSTRAP.md"

exit "$status"
