#!/usr/bin/env bash
# Check scripts/squad-latest.sh (agent-squad #302) in a scratch main checkout, with a copy of it
# beside squad-timeout.sh and a squad-install.sh whose upstream= line names o/r, and a gh that
# records what it is asked and answers as each case sets; nothing reaches GitHub. A check is due
# with no file, 24 hours after the last that worked, and an hour after a failed attempt; it writes
# the attempt before it asks; it writes the file in the format the board reads; a failure, a wrong
# answer or a gh that takes too long keeps the tag, and the last says so (agent-squad #430); a file
# that is not that format counts as no check; --due only
# answers; --now, a session start's, asks whatever the last check's age (agent-squad #336); without
# an upstream it asks nothing; bad usage exits 2.
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

# The playbook's scripts, as a project has them: this one, the bound it puts on gh, and an installer
# that names o/r.
scripts="$lab/playbook/scripts"
mkdir -p "$scripts" "$lab/bin"
cp "$root/scripts/squad-latest.sh" "$root/scripts/squad-timeout.sh" "$scripts/"
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
# `run [--due | --now] ...` runs the copy on the checkout, into out and code, with a fresh gh.log.
run() {
  rm -f "$lab/gh.log"
  out="$("$latest" "$@" "$checkout" 2>&1)"
  code=$?
}
# `holds <jq filter>` passes when the file satisfies the filter, `now` being the time, and $recent
# the 30 s within which a time counts as now: room for a loaded machine, as under CI's kcov or with
# every check running at once, and far from the hour and the day the cases tell apart (agent-squad
# #468).
# shellcheck disable=SC2317,SC2329 # invoked through check
holds() { jq -e --argjson now "$(date +%s)" --argjson recent 30 "$1" "$file" >/dev/null 2>&1; }

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
  holds 'keys == ["attemptedAt", "checkedAt", "tag"] and .tag == "v50" and (now - .checkedAt) < $recent and .attemptedAt == .checkedAt'
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
check "so that the next check is due a day after now, not after that future" holds '(now - .checkedAt) < $recent'

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
check "with the time of the check" holds '.tag == "v51" and (now - .checkedAt) < $recent'

# 2b. --now, as a session start runs it, asks whatever the last check's age (agent-squad #336): a
#     minute after a check that worked, and right after a failed attempt, with a tag known or not.
# `now_asks <what> <tag or null> <seconds since checked> <seconds since attempted>` runs --now with
# the file as of then, and expects GitHub asked and its answer written.
now_asks() {
  known "$2" "$3" "$4"
  GH_ANSWER=v51 run --now
  check "--now asks GitHub after $1, says what it found, and writes it" \
    bash -c '[ "$1" -eq 0 ] && [ "$2" = "latest release: v51, checked now" ] && grep -q releases/latest "$3"' _ "$code" "$out" "$lab/gh.log"
  check "and the file holds v51, checked and attempted now" holds '.tag == "v51" and (now - .checkedAt) < $recent and .attemptedAt == .checkedAt'
}
now_asks "a check a minute ago" '"v50"' 60 60
now_asks "a failed attempt a minute ago" '"v50"' $((day + 60)) 60
now_asks "a failed attempt a minute ago, with no check that worked yet" null $((day + 60)) 60
#     Every other moment keeps its rule: a minute after that check, none is due.
run --due
check "after a --now check, none is due for the turn's end, /squad-resume or /squad-watch" [ "$code" -eq 1 ]
#     A --now that fails records the attempt, as any check does.
known '"v50"' 60 60
GH_FAILS=1 run --now
check "a --now that fails keeps the tag and records the attempt" \
  bash -c '[ "$1" = "latest release: GitHub did not tell it; the next attempt is in an hour" ]' _ "$out"
check "and its file still names v50, with the attempt now" holds '.tag == "v50" and (now - .attemptedAt) < $recent'

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
    holds '.tag == "v50" and (now - .checkedAt) > 86400 and (now - .attemptedAt) < $recent'
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

# 4. A gh that takes longer than SQUAD_LATEST_TIMEOUT is stopped, and counts as a failure, which its
#    line names (agent-squad #430). Its gh would answer after 60 s; stopped after the 1 s bound, the
#    run ends within 30 s, which a loaded machine leaves room for (agent-squad #468).
known '"v50"' $((day + 60)) $((day + 60))
started=$SECONDS
SQUAD_LATEST_TIMEOUT=1 GH_SLEEP=60 run
took=$((SECONDS - started))
if [ "$took" -le 30 ] && [ "$out" = "latest release: GitHub did not answer within 1 s; the next attempt is in an hour" ] \
  && [ "$code" -eq 0 ]; then
  pass "a gh that takes too long is stopped after the timeout, and counts as a failure, saying so"
else
  fail "a gh that takes too long: exit $code after $took s, said: $out"
fi
check "and keeps the tag" holds '.tag == "v50" and (now - .attemptedAt) < $recent and (now - .checkedAt) > 86400'
check "and is not left running" bash -c '! kill -0 "$(cat "$1")" 2>/dev/null' _ "$lab/gh.pid"

# 5. The attempt is written before gh answers, so that a session starting meanwhile asks nothing.
#    gh here answers after 60 s, and `--due` is asked every tenth of a second until it says that no
#    check is due, for 30 s at most, while gh still waits: an attempt written only once gh answered
#    keeps a check due all that time, where a loaded machine needs at most a second or two to write
#    it (agent-squad #498). gh's sleep is then ended, so that gh answers and the run ends as it
#    would, leaving no file behind.
known '"v50"' $((day + 60)) $((day + 60))
rm -f "$lab/gh.log" "$lab/gh.pid"
SQUAD_LATEST_TIMEOUT=120 GH_SLEEP=60 "$latest" "$checkout" >/dev/null 2>&1 &
pid=$!
due_meanwhile=0
for _ in $(seq 300); do
  "$latest" --due "$checkout" && due_meanwhile=0 || due_meanwhile=$?
  [ "$due_meanwhile" -eq 0 ] || break
  sleep 0.1
done
gh_waits="$(kill -0 "$(cat "$lab/gh.pid" 2>/dev/null)" 2>/dev/null && echo yes || echo no)"
# shellcheck disable=SC2046 # the PIDs are split on purpose, one argument each
kill $(pgrep -P "$(cat "$lab/gh.pid" 2>/dev/null)" 2>/dev/null) 2>/dev/null
wait "$pid" 2>/dev/null
if [ "$due_meanwhile" -eq 1 ] && [ "$gh_waits" = yes ] && [ "$(wc -l < "$lab/gh.log")" -eq 1 ]; then
  pass "while a check waits on gh, the attempt is already written, and no other is due"
else
  fail "while a check waits on gh: --due exited $due_meanwhile within 30 s, gh still waiting: $gh_waits, gh called $(wc -l < "$lab/gh.log" 2>/dev/null | tr -d ' ') times"
fi

# 6. A file that is not the board's format counts as no check, and a check rewrites it.
for content in 'not json' '["v50"]' '{} {}' '{"tag": "v50", "checkedAt": "today"}' '{"tag": "50"}' ''; do
  printf '%s' "$content" > "$file"
  run --due
  check "a file holding '$content' counts as no check: one is due" [ "$code" -eq 0 ]
done
printf 'not json' > "$file"
run
check "and a check rewrites it in the board's format" holds '.tag == "v50" and (now - .checkedAt) < $recent'
#    A tag that is not vN is no tag, even when its times say no check is due.
known '"latest"' 100 100
run
check "a file whose tag is not vN knows no release, though no check is due" \
  bash -c '[ "$1" = "latest release: not known yet; GitHub was asked 0 h ago" ] && [ ! -e "$2" ]' _ "$out" "$lab/gh.log"

# 6b. A file it cannot replace, here a directory in its place that it cannot write into, is left
#     as it is, and the temporary file it wrote is not left beside it (agent-squad #246).
rm -f "$file" && mkdir "$file" && chmod a-w "$file"
GH_ANSWER=v51 run
chmod u+w "$file"
check "with a latest-release it cannot replace, a check says what it found, and leaves no file of its own" \
  bash -c '[ "$1" = "latest release: v51, checked now" ] && [ -d "$2" ] && [ -z "$(ls -A "$2")" ] \
    && [ "$(ls -A "$3")" = latest-release ]' _ "$out" "$file" "$checkout/.agent-squad"
rmdir "$file"

# 7. Without an upstream to ask, it asks nothing, says so, and still records the attempt.
alone="$lab/alone"
mkdir -p "$alone" && cp "$latest" "$alone/"
known '"v50"' $((day + 60)) $((day + 60))
rm -f "$lab/gh.log"
out="$("$alone/squad-latest.sh" "$checkout" 2>&1)"
check "with no squad-install.sh beside it, it asks nothing and says why" \
  bash -c '[ "$1" = "latest release: cannot tell the upstream from $2/squad-install.sh; not checked" ] && [ ! -e "$3" ]' \
  _ "$out" "$alone" "$lab/gh.log"
check "and records the attempt, so that it tries again in an hour" holds '.tag == "v50" and (now - .attemptedAt) < $recent'

# 8. Bad usage exits 2, and asks nothing.
for args in "" "--due" "--now" "$checkout $checkout" "$lab/playbook"; do
  rm -f "$lab/gh.log"
  # shellcheck disable=SC2086 # the arguments are split on purpose
  out="$("$latest" $args 2>&1)"
  code=$?
  check "'${args//$lab/<lab>}' is bad usage, exit 2" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "usage: squad-latest.sh [--due | --now] <main checkout>" ] && [ ! -e "$3" ]' \
    _ "$code" "$out" "$lab/gh.log"
done

exit "$status"
