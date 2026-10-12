#!/usr/bin/env bash
# Check scripts/squad-latest.sh (agent-squad #302) in a scratch main checkout, with a copy of it
# beside a squad-install.sh whose upstream= line names o/r, and a gh that records what it is asked
# and answers as each case sets; nothing reaches GitHub. A check is due with no file, 24 hours
# after the last that worked, and an hour after a failed attempt; it writes the attempt before it
# asks; it writes the file in the format the board reads; a failure, a wrong answer or a gh that
# takes too long keeps the tag; a file that is not that format counts as no check; --due only
# answers; without an upstream it asks nothing; bad usage exits 2.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments
set -u

root="$(git rev-parse --show-toplevel)" || exit 2

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-latest.XXXXXX")" || exit 2
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

# The playbook's scripts, as a project has them: this one, and an installer that names o/r.
scripts="$lab/playbook/scripts"
mkdir -p "$scripts" "$lab/bin"
cp "$root/scripts/squad-latest.sh" "$scripts/"
printf '%s\n' '#!/usr/bin/env bash' 'upstream="o/r"' > "$scripts/squad-install.sh"
latest="$scripts/squad-latest.sh"
# gh, as far as squad-latest.sh is concerned: each call goes to gh.log, and its PID to gh.pid. It
# prints GH_ANSWER (v50 when unset), sleeping GH_SLEEP seconds first, and fails when GH_FAILS is set.
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
lab="$(cd "$(dirname "$0")/.." && pwd)"
echo "$*" >> "$lab/gh.log"
echo "$$" > "$lab/gh.pid"
[ -z "${GH_SLEEP:-}" ] || sleep "$GH_SLEEP"
[ -z "${GH_FAILS:-}" ] || exit 1
echo "${GH_ANSWER-v50}"
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH"

# The scratch main checkout, and its file.
checkout="$lab/project"
mkdir -p "$checkout/.agent-squad"
file="$checkout/.agent-squad/latest-release"
day=86400 hour=3600

# `known <tag or null> <seconds since checked> <seconds since attempted>` writes the file as of then.
known() {
  local now
  now="$(date +%s)"
  jq -cn --argjson tag "$1" --argjson checked "$((now - $2))" --argjson attempted "$((now - $3))" \
    '{tag: $tag, checkedAt: $checked, attemptedAt: $attempted}' > "$file"
}
# `run [--due] ...` runs the copy on the checkout, into out and code, with a fresh gh.log.
run() {
  rm -f "$lab/gh.log"
  out="$("$latest" "$@" "$checkout" 2>&1)"
  code=$?
}
# `holds <jq filter>` passes when the file satisfies the filter, `now` being the time.
# shellcheck disable=SC2317,SC2329 # invoked through check
holds() { jq -e --argjson now "$(date +%s)" "$1" "$file" >/dev/null 2>&1; }

# 1. No file: a check is due, gh is asked for o/r's latest Release, and the file holds its answer.
rm -f "$file"
run --due
check "with no file, a check is due: --due exits 0, asking nothing and writing nothing" \
  bash -c '[ "$1" -eq 0 ] && [ -z "$2" ] && [ ! -e "$3" ] && [ ! -e "$4" ]' _ "$code" "$out" "$lab/gh.log" "$file"
run
check "and a check asks gh for the upstream's latest Release, by its tag" \
  bash -c '[ "$(cat "$1")" = "api repos/o/r/releases/latest --jq .tag_name" ]' _ "$lab/gh.log"
check "and says what it found" bash -c '[ "$1" -eq 0 ] && [ "$2" = "latest release: v50, checked now" ]' _ "$code" "$out"
check "and writes the tag, checked and attempted now, in the board's format" \
  holds 'keys == ["attemptedAt", "checkedAt", "tag"] and .tag == "v50" and (now - .checkedAt) < 5 and .attemptedAt == .checkedAt'
check "leaving no file of its own beside it" bash -c '[ "$(ls -A "$1")" = latest-release ]' _ "$checkout/.agent-squad"

# 1b. Times later than now, as a clock that ran ahead leaves them, count as never (agent-squad #309).
for unit in seconds milliseconds; do
  ahead=$((10 * day))
  [ "$unit" = seconds ] || ahead=$(( ($(date +%s) + 10 * day) * 1000 - $(date +%s) ))
  known '"v50"' -"$ahead" -"$ahead"
  run --due
  check "a check and an attempt ten days ahead, in $unit, count as never: one is due" [ "$code" -eq 0 ]
done
run
check "and a run asks, and writes the time of now" \
  bash -c 'grep -q releases/latest "$1"' _ "$lab/gh.log"
check "so that the next check is due a day after now, not after that future" holds '(now - .checkedAt) < 5'

# 2. Checked less than a day ago: nothing is due, and nothing is asked.
for since in 100 $((day - 60)); do
  known '"v50"' "$since" "$since"
  cp "$file" "$lab/before"
  run --due
  check "checked $since s ago, no check is due: --due exits 1" bash -c '[ "$1" -eq 1 ] && [ -z "$2" ]' _ "$code" "$out"
  run
  check "and a run asks nothing, says what it knows, and leaves the file as it was" \
    bash -c '[ "$1" -eq 0 ] && [ "$2" = "latest release: v50, checked $3 h ago" ] && [ ! -e "$4" ] && cmp -s "$5" "$6"' \
    _ "$code" "$out" "$((since / hour))" "$lab/gh.log" "$lab/before" "$file"
done
#    A day and a minute later, one is.
known '"v50"' $((day + 60)) $((day + 60))
run --due
check "checked a day and a minute ago, a check is due" [ "$code" -eq 0 ]
GH_ANSWER=v51 run
check "and a run asks, and writes the newer tag" bash -c 'grep -q releases/latest "$1"' _ "$lab/gh.log"
check "with the time of the check" holds '.tag == "v51" and (now - .checkedAt) < 5'

# 3. A failure keeps the tag and its time, records the attempt, and waits an hour.
known '"v50"' $((day + 60)) $((day + 60))
for answer in failed wrong empty two-words; do
  case "$answer" in
    failed) GH_FAILS=1 run ;;
    wrong) GH_ANSWER=latest run ;;
    empty) GH_ANSWER='' run ;;
    two-words) GH_ANSWER="v51 v52" run ;;
  esac
  check "an answer that is $answer keeps the tag and when it was checked, and records the attempt now" \
    bash -c '[ "$1" -eq 0 ] && [ "$2" = "latest release: GitHub did not tell it; the next attempt is in an hour" ]' _ "$code" "$out"
  check "so that the file still names v50, and its attempt is now" \
    holds '.tag == "v50" and (now - .checkedAt) > 86400 and (now - .attemptedAt) < 5'
  known '"v50"' $((day + 60)) $((day + 60))
done
known '"v50"' $((day + 60)) 60
run --due
check "a failed attempt a minute ago makes the next check wait" [ "$code" -eq 1 ]
known '"v50"' $((day + 60)) $((hour + 60))
run --due
check "an hour and a minute later, it is due again" [ "$code" -eq 0 ]
known null $((day + 60)) 60
run
check "before any check has worked, a run says when GitHub was last asked" \
  bash -c '[ "$1" = "latest release: not known yet; GitHub was asked 0 h ago" ] && [ ! -e "$2" ]' _ "$out" "$lab/gh.log"

# 4. A gh that takes longer than SQUAD_LATEST_TIMEOUT is stopped, and counts as a failure.
known '"v50"' $((day + 60)) $((day + 60))
started=$SECONDS
SQUAD_LATEST_TIMEOUT=1 GH_SLEEP=5 run
check "a gh that takes too long is stopped after the timeout, and counts as a failure" \
  bash -c '[ $(($3 - $4)) -lt 4 ] && [ "$1" = "latest release: GitHub did not tell it; the next attempt is in an hour" ] && [ "$2" -eq 0 ]' \
  _ "$out" "$code" "$SECONDS" "$started"
check "and is not left running" bash -c '! kill -0 "$(cat "$1")" 2>/dev/null' _ "$lab/gh.pid"

# 5. The attempt is written before gh answers, so that a session starting meanwhile asks nothing.
known '"v50"' $((day + 60)) $((day + 60))
rm -f "$lab/gh.log"
GH_SLEEP=2 "$latest" "$checkout" >/dev/null 2>&1 &
pid=$!
sleep 1
"$latest" --due "$checkout"
due_meanwhile=$?
wait "$pid"
check "while a check waits on gh, the attempt is already written, and no other is due" \
  bash -c '[ "$1" -eq 1 ] && [ "$(wc -l < "$2")" -eq 1 ]' _ "$due_meanwhile" "$lab/gh.log"

# 6. A file that is not the board's format counts as no check, and a check rewrites it.
for content in 'not json' '["v50"]' '{} {}' '{"tag": "v50", "checkedAt": "today"}' '{"tag": "50"}' ''; do
  printf '%s' "$content" > "$file"
  run --due
  check "a file holding '$content' counts as no check: one is due" [ "$code" -eq 0 ]
done
printf 'not json' > "$file"
run
check "and a check rewrites it in the board's format" holds '.tag == "v50" and (now - .checkedAt) < 5'
#    A tag that is not vN is no tag, even when its times say no check is due.
known '"latest"' 100 100
run
check "a file whose tag is not vN knows no release, though no check is due" \
  bash -c '[ "$1" = "latest release: not known yet; GitHub was asked 0 h ago" ] && [ ! -e "$2" ]' _ "$out" "$lab/gh.log"

# 7. Without an upstream to ask, it asks nothing, says so, and still records the attempt.
alone="$lab/alone"
mkdir -p "$alone" && cp "$latest" "$alone/"
known '"v50"' $((day + 60)) $((day + 60))
rm -f "$lab/gh.log"
out="$("$alone/squad-latest.sh" "$checkout" 2>&1)"
check "with no squad-install.sh beside it, it asks nothing and says why" \
  bash -c '[ "$1" = "latest release: cannot tell the upstream from $2/squad-install.sh; not checked" ] && [ ! -e "$3" ]' \
  _ "$out" "$alone" "$lab/gh.log"
check "and records the attempt, so that it tries again in an hour" holds '.tag == "v50" and (now - .attemptedAt) < 5'

# 8. Bad usage exits 2, and asks nothing.
for args in "" "--due" "$checkout $checkout" "$lab/playbook"; do
  rm -f "$lab/gh.log"
  # shellcheck disable=SC2086 # the arguments are split on purpose
  out="$("$latest" $args 2>&1)"
  code=$?
  check "'${args//$lab/<lab>}' is bad usage, exit 2" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "usage: squad-latest.sh [--due] <main checkout>" ] && [ ! -e "$3" ]' \
    _ "$code" "$out" "$lab/gh.log"
done

exit "$status"
