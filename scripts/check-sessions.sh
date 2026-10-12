#!/usr/bin/env bash
# Check scripts/squad-sessions.sh (agent-squad #361) in a scratch main checkout whose playbook holds
# a board's plugin.json and whose .agent-squad/sessions/ holds records as each session's board
# writes them. A session on the installed release, one older, compared as numbers, one newer, a
# record three minutes old or more, a missing record and one that is not that shape each get their
# line; the roles to restart, and those to restart if open, are named; an installed release that
# cannot be read compares nothing; bad usage exits 2. Nothing reaches GitHub or a session.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
sessions="$root/scripts/squad-sessions.sh"

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-sessions.XXXXXX")" || exit 2
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

# The scratch checkout: the installed board's plugin.json, and the records' directory.
checkout="$lab/project"
board="$checkout/.agent-squad/playbook/mods/squad-board/.claude-plugin"
records="$checkout/.agent-squad/sessions"
mkdir -p "$board" "$records"
# `installed <version>` writes the installed board's plugin.json.
installed() { printf '{"name": "squad-board", "version": "%s"}\n' "$1" > "$board/plugin.json"; }
# `record <role> <release> <seconds ago>` writes a role's record, as its board writes it.
record() {
  jq -n --arg name "$1:proj" --arg release "$2" --argjson at "$(( ($(date +%s) - $3) * 1000 ))" \
    '{name: $name, sessionId: "sid", release: $release, at: $at}' > "$records/$1.json"
}
# `run` runs the script on the checkout, into out and code.
run() {
  out="$("$sessions" "$checkout" 2>&1)"
  code=$?
}

# 1. Fresh records: the CTO on the installed v10, DEV on v9, older though "v9" sorts after "v10"
#    as text, and QA on v100, newer: DEV is named to restart.
installed 10.0.0
record CTO v10 5 && record DEV v9 5 && record QA v100 5
run
check "it exits 0, a line per role in the order CTO, DEV, QA, then the roles to restart" \
  bash -c '[ "$1" -eq 0 ] && [ "$(grep -c "^sessions: " <<<"$2")" -eq 4 ] && [ "$(sed -n "1s/^sessions: \([A-Z]*\) .*/\1/p;2s/^sessions: \([A-Z]*\) .*/\1/p;3s/^sessions: \([A-Z]*\) .*/\1/p" <<<"$2" | tr "\n" " ")" = "CTO DEV QA " ]' \
  _ "$code" "$out"
check "a session on the installed release says so" has "sessions: CTO  CTO:proj runs v10, the installed release"
check "one on an older release, compared as numbers, is to restart" has "sessions: DEV  DEV:proj runs v9, older than the installed v10: /restart it"
check "one on a newer release is not" has "sessions: QA  QA:proj runs v100, the installed release"
check "and the roles to restart are named" has "sessions: to restart: DEV"
check "and none is to restart if open" bash -c '! grep -q "if open" <<<"$1"' _ "$out"

# 2. Every record on the installed release: none to restart.
record DEV v10 5 && record QA v10 5
run
check "with every session on the installed release, it says so, and names none" \
  bash -c 'grep -qxF "sessions: every open session runs v10" <<<"$1" && ! grep -q "to restart" <<<"$1"' _ "$out"

# 3. A record three minutes old or more is a session that may be closed: an older one is to restart
#    if it is open, and one on the installed release needs nothing.
record DEV v9 600 && record QA v10 600
run
check "an older record three minutes old or more is to restart if the session is open, with its age" \
  has "sessions: DEV  DEV:proj ran v9 until 10 min ago, older than the installed v10: /restart it if it is open"
check "one on the installed release needs nothing" has "sessions: QA  QA:proj ran v10 until 10 min ago, the installed release"
check "and the role to restart if open is named, and none to restart for sure" \
  bash -c 'grep -qxF "sessions: to restart if open: DEV" <<<"$1" && ! grep -q "^sessions: to restart: " <<<"$1"' _ "$out"

# 4. A missing record, and one that is not that shape, are a session whose board writes none: an
#    older board's, or no session at all.
rm -f "$records/DEV.json" && record QA vX 5
run
for role in DEV QA; do
  check "$role, with no record or one that is not that shape, is to restart if it is open" \
    has "sessions: $role  no record: no session of this role runs a board that writes one; /restart it if it is open"
done
check "and both are named so" has "sessions: to restart if open: DEV QA"
for content in 'not json' '{"name": "QA:proj", "release": "v10"}' '{"name": 7, "release": "v10", "at": 1}' '{"name": "QA:proj", "release": 10, "at": 1}'; do
  printf '%s' "$content" > "$records/QA.json"
  run
  check "a record holding '$content' is no record" has "sessions: QA  no record: no session of this role runs a board that writes one; /restart it if it is open"
done

# 5. An installed release that cannot be read compares nothing: each record's release, and no
#    roles named.
record DEV v9 5 && record QA v10 5
for content in 'missing' '{"version": "x"}'; do
  if [ "$content" = missing ]; then rm -f "$board/plugin.json"; else printf '%s' "$content" > "$board/plugin.json"; fi
  run
  check "with an installed release that is $content, it says it cannot read it, and exits 0" \
    bash -c '[ "$1" -eq 0 ] && grep -qxF "sessions: the installed release cannot be read from .agent-squad/playbook/mods/squad-board/.claude-plugin/plugin.json; nothing compared" <<<"$2"' \
    _ "$code" "$out"
  check "and gives each record's release, naming no role to restart" \
    bash -c 'grep -qxF "sessions: DEV  DEV:proj runs v9" <<<"$1" && ! grep -q "to restart:\|every open session" <<<"$1"' _ "$out"
done

# 6. Bad usage exits 2, saying how to use it.
for args in "" "$checkout $checkout" "$lab/nowhere"; do
  # shellcheck disable=SC2086 # the arguments are split on purpose
  out="$("$sessions" $args 2>&1)"
  code=$?
  check "'${args//$lab/<lab>}' is bad usage, exit 2" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "usage: squad-sessions.sh <main checkout>" ]' _ "$code" "$out"
done

exit "$status"
