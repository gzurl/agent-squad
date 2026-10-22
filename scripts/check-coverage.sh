#!/usr/bin/env bash
# Check what ci-coverage.sh makes of what kcov records (agent-squad #180), in a scratch repository
# whose scripts are written for it, with a kcov that writes fixed records instead of running the
# tests. A copy counts for the script of the same name when it has the same lines to measure, and
# a different script of that name does not; a line counts once however many tests ran it; kcov's
# "hits/total" counts the hits; a statement over several lines counts once, run if kcov recorded
# any of its lines, and is left out if it recorded none; an empty case branch, a lone `(`, and a
# `done` or `)` with only redirections or a `&` after it count only if they ran, and a line marked
# `# coverage: excluded, <reason>` does not count; the summary lists both kinds of line not counted,
# with why (agent-squad #352). A path that holds a double quote or a backslash, which kcov writes as it is, is read, and
# a record that cannot be read even so stops the summary (agent-squad #348). The summary names a
# test that failed, lists the thinnest script first, rounds its shares, lists the lines no test
# ran, and --summary-only writes it again from the records alone. Its first line is the verdict,
# and a script below 100 % or a test that failed under kcov fails the run, exit 3, naming each: the
# coverage job fails on its own (agent-squad #507). Without kcov, with nothing recorded, or with a
# record it cannot read, it exits 1. This script runs none of the tests and touches
# neither the repository it is run from nor GitHub.
# shellcheck disable=SC2016 # the summary's backticks are Markdown, and the fixtures are code
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
coverage="$root/scripts/ci-coverage.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-coverage.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# The scratch repository: three tests, whose content does not matter, and the scripts measured.
repo="$lab/repo"
mkdir -p "$repo/scripts" "$repo/.githooks" || exit 2
git init -q "$repo" || exit 2
for test in check-gate check-handoff check-merge-gate; do echo 'exit 0' > "$repo/scripts/$test.sh"; done
printf '%s\n' '#!/usr/bin/env bash' 'echo a' 'echo b' 'echo c' 'echo d' > "$repo/scripts/squad-checks.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo one' 'echo two' 'echo three' > "$repo/.githooks/pre-push"
printf '%s\n' '#!/usr/bin/env bash' 'echo a' 'echo b' 'echo c' > "$repo/install.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo never' > "$repo/scripts/squad-tokens.sh"
# squad-merge-gate.sh: a quoted program over three lines (2-4), a statement of one line (5), a $( )
# over two lines (6-7), another (8-9), a line ended by \ (10-11), and a case with an empty branch.
cat > "$repo/scripts/squad-merge-gate.sh" <<'EOF'
#!/usr/bin/env bash
program='def f:
  . + 1;
  f'
echo one
value="$(printf '%s' x \
  | cat)"
result="$(true \
  )"
echo "$value" \
  && echo two
case "$value" in
  x) ;;
  *) echo other ;;
esac
EOF
# squad-latest.sh: a loop whose `done` takes a redirection (2-4), a subshell opened by a lone `(` and
# sent to the background by `) &` (5-7), a statement (8), a loop whose `done` sends its output
# elsewhere (9-11), a line excluded with its reason (12), and a statement (13).
cat > "$repo/scripts/squad-latest.sh" <<'EOF'
#!/usr/bin/env bash
while read -r x; do
  echo "$x"
done < /dev/null
(
  echo inside
) &
wait
for y in 1; do
  echo "$y"
done >&2
echo polled  # coverage: excluded, it runs only when a process outlives its kill
echo never
EOF
# squad-install.sh: a heredoc inside a $( ), with an apostrophe and an open parenthesis in its
# body (2-6), a statement (7), a heredoc of its own (8-10), a statement (11), a here-string, which
# opens no heredoc (12), and a statement (13).
cat > "$repo/scripts/squad-install.sh" <<'EOF'
#!/usr/bin/env bash
text="$(cat <<'BODY'
it's a line with an apostrophe
and (an open parenthesis
BODY
)"
echo "$text"
cat <<BODY
body
BODY
echo done
cat <<< done
echo after
EOF

# kcov, as far as ci-coverage.sh is concerned: for each test it writes a codecov.json and, beside
# it, a cobertura.xml whose <source> is the part its files' names leave out, as kcov does. For
# check-gate.sh, with source "/": squad-checks.sh with line 4 run; a copy of it in a temporary
# directory with the same lines, 2 and 3 run, 3 written "2/2"; a different squad-checks.sh with
# other lines, all run; and pre-push, line 2 written "0/2", 3 "1/2". For check-handoff.sh, which
# runs after it, with the scripts' directory as its source: line 5 of squad-checks.sh run and 4
# not; and it fails. For check-merge-gate.sh, with the root as its source: squad-merge-gate.sh,
# whose program ran on its last line, whose first $( ) ran on its first line, whose second $( )
# was recorded nowhere, whose \ line ran on its second; install.sh, two lines of three run, and a
# copy of it whose path holds a double quote and a backslash, written as kcov writes it, with no
# escape, which ran the third; and squad-install.sh, recorded on the first line of each heredoc's
# statement, on 11 and on the here-string, with 13 unrun; and squad-latest.sh, every line run but
# those kcov never records, the excluded one and the last.
# KCOV_RECORDS=none makes it record nothing, and KCOV_RECORDS=broken writes check-gate.sh's record
# cut short. KCOV_RECORDS=full has check-gate.sh run line 2 of every script, a statement in each,
# and no test fail; full-failing does the same, but check-handoff.sh fails; full-short leaves line
# 3 of squad-checks.sh unrun. --merge writes an index. Each call's arguments go to $lab/kcov.calls, and options are
# skipped to find the output directory and the test.
mkdir -p "$lab/bin"
cat > "$lab/bin/kcov" <<'KCOV'
#!/usr/bin/env bash
if [ "$1" = --merge ]; then mkdir -p "$2" && touch "$2/index.html"; exit 0; fi
echo "$*" >> "$(dirname "$0")/../kcov.calls"
args=()
for arg; do case "$arg" in --*) ;; *) args+=("$arg") ;; esac; done
out="${args[0]}" test="${args[1]}" root="$(git rev-parse --show-toplevel)"
[ "${KCOV_RECORDS:-}" != none ] || exit 0
dir="$out/$(basename "$test").0123456789abcdef"
mkdir -p "$dir"
if [[ "${KCOV_RECORDS:-}" == full* ]]; then
  [[ "$test" == *check-gate.sh ]] || { [ "$KCOV_RECORDS" = full-failing ] && [[ "$test" == *check-handoff.sh ]] && exit 1; exit 0; }
  echo '<sources><source>/</source></sources>' > "$dir/cobertura.xml"
  jq -n --arg r "${root#/}" --arg short "$KCOV_RECORDS" '{coverage: ([
    "scripts/squad-checks.sh", ".githooks/pre-push", "install.sh", "scripts/squad-tokens.sh",
    "scripts/squad-merge-gate.sh", "scripts/squad-latest.sh", "scripts/squad-install.sh"]
    | map({key: ($r + "/" + .), value: {"2": 1}}) | from_entries
    | if $short == "full-short" then .[$r + "/scripts/squad-checks.sh"]["3"] = 0 else . end)}' > "$dir/codecov.json"
  exit 0
fi
if [ "${KCOV_RECORDS:-}" = broken ] && [[ "$test" == *check-gate.sh ]]; then
  echo '<sources><source>/</source></sources>' > "$dir/cobertura.xml"
  printf '{\n  "coverage": {\n    "scripts/squad-checks.sh": {\n' > "$dir/codecov.json"
  exit 0
fi
case "$test" in
  *check-gate.sh) echo '<sources><source>/</source></sources>' > "$dir/cobertura.xml"
    jq -n --arg r "${root#/}" '{coverage: {
      ($r + "/scripts/squad-checks.sh"): {"2": 0, "3": 0, "4": 1, "5": 0},
      "tmp/lab/playbook/scripts/squad-checks.sh": {"2": 1, "3": "2/2", "4": 0, "5": 0},
      "tmp/lab/stub/squad-checks.sh": {"1": 5, "9": 5},
      ($r + "/.githooks/pre-push"): {"2": "0/2", "3": "1/2", "4": 0}}}' ;;
  *check-handoff.sh) echo "<sources><source>$root/scripts/</source></sources>" > "$dir/cobertura.xml"
    jq -n '{coverage: {"squad-checks.sh": {"2": 0, "4": 0, "5": "1/1"}}}'
    exit 1 ;;
  *check-merge-gate.sh) echo "<sources><source>$root/</source></sources>" > "$dir/cobertura.xml"
    jq -n '{coverage: {
      "scripts/squad-merge-gate.sh": {"2": 0, "3": 0, "4": 1, "5": 0, "6": 2, "7": 0, "8": 0, "9": 0,
                                      "10": 0, "11": 1, "13": 0, "14": 0},
      "install.sh": {"2": 1, "3": 1, "4": 0},
      "scripts/squad-install.sh": {"2": 1, "6": 0, "7": 1, "8": 1, "9": 0, "11": 1, "12": 1, "13": 0},
      "scripts/squad-latest.sh": {"2": 1, "3": 1, "4": 0, "5": 0, "6": 1, "7": 0, "8": 1, "9": 1, "10": 1,
                                  "11": 0, "12": 0, "13": 0}}}' \
      | awk 'NR == 2 { print; print "    \"tmp/lab/odd \"one\" \\x/playbook/install.sh\": {";
                        print "      \"2\": 0,"; print "      \"3\": 0,"; print "      \"4\": 1"; print "    },"; next } 1' ;;
  *) exit 0 ;;
esac > "$dir/codecov.json"
KCOV
chmod +x "$lab/bin/kcov"

# `summary_of <case> <expected line>` passes when the last run's summary holds that line.
summary_of() {
  if grep -qxF -- "$2" "$lab/out/summary.md" 2>/dev/null; then
    pass "$1"
  else
    fail "$1: no line '$2' in: $(cat "$lab/out/summary.md" 2>/dev/null)"
  fi
}

# 1. A run with the stand-in.
out="$(cd "$repo" && PATH="$lab/bin:$PATH" "$coverage" "$lab/out" 2>&1)"
code=$?
if [ "$code" -eq 3 ] && [ -f "$lab/out/report/index.html" ] && [ "$out" = "$(cat "$lab/out/summary.md")" ]; then
  pass "below 100 %, it exits 3, prints the summary it writes, and merges kcov's reports"
else
  fail "a run: exit $code, printed: $out"
fi
# kcov writes its reports at the end alone, so that it reads the traces while the tests run: a
# script that removes itself as it ends, as the uninstaller's copy does, is read before it goes
# (agent-squad #473). The repository's checks are each a run.
runs="$(grep -c . "$lab/kcov.calls" 2>/dev/null)"
with="$(grep -c -- '^--output-interval=0 ' "$lab/kcov.calls" 2>/dev/null)"
tests="$(cd "$repo" && find scripts -name 'check-*.sh' | grep -c .)"
if [ "$runs" -gt 0 ] && [ "$runs" = "$tests" ] && [ "$with" = "$runs" ]; then
  pass "each test runs under kcov with --output-interval=0"
else
  fail "of $runs kcov runs, for $tests tests, $with have --output-interval=0: $(cat "$lab/kcov.calls" 2>/dev/null)"
fi
summary_of "a copy with the same lines counts, a different script of that name does not, and a line one test ran stays run" \
  '| `scripts/squad-checks.sh` (and 1 copy) | 4 | 4 | 100 % |'
summary_of "a hits/total count is read as its hits" '| `.githooks/pre-push` | 1 | 3 | 33.3 % |'
summary_of "a statement over several lines counts once, as run if any line of it ran; one recorded nowhere, and an empty case branch, are left out" \
  '| `scripts/squad-merge-gate.sh` | 3 | 5 | 60 % |'
summary_of "a heredoc belongs to its statement, its apostrophe and parenthesis read as text, and so does the end of a \$( ) around it; a here-string opens none" \
  '| `scripts/squad-install.sh` | 5 | 6 | 83.3 % |'
summary_of "a copy whose path holds a double quote and a backslash, which kcov writes with no escape, is read, and counts" \
  '| `install.sh` (and 1 copy) | 3 | 3 | 100 % |'
summary_of "a lone ( and a done or ) with only redirections or & after it count only if they ran, and a line marked excluded does not count" \
  '| `scripts/squad-latest.sh` | 6 | 7 | 85.7 % |'
summary_of "the lines not counted list an excluded line with its reason" \
  '- `scripts/squad-latest.sh` 12, excluded: it runs only when a process outlives its kill'
summary_of "and a statement kcov recorded on none of its lines, by its first line" \
  "- \`scripts/squad-merge-gate.sh\` 8: kcov recorded none of the statement's lines"
summary_of "in a collapsed block of their own" '<details><summary>The lines not counted</summary>'
summary_of "a script no test ran" '| `scripts/squad-tokens.sh` | 0 | 0 | not run |'
summary_of "the total adds up the scripts: 22 of 28 is 78.6 %" '| **Total** | **22** | **28** | **78.6 %** |'
summary_of "a test that failed under kcov is named" 'Tests that failed under kcov, so their figures may be short: `check-handoff`.'
summary_of "the summary opens with the verdict: each script below 100 %, with its lines no test ran, and each test that failed" \
  '**The coverage job fails:** below 100 % in `scripts/squad-tokens.sh` (not run), `.githooks/pre-push` (lines 2, 4), `scripts/squad-merge-gate.sh` (lines 5, 14), `scripts/squad-install.sh` (lines 13), `scripts/squad-latest.sh` (lines 13); a test failed under kcov: `check-handoff`.'
if grep -qF 'kcov recorded 1 such statement on none of its lines; whether it ran is unknown, so it is left out.' "$lab/out/summary.md" \
   && grep -qF 'so it reads lower; `scripts/ci-coverage.sh --summary-only` gives these figures back' "$lab/out/summary.md"; then
  pass "the summary says how many statements it left out, and why kcov's own report reads lower"
else
  fail "the summary's text: $(sed -n 3p "$lab/out/summary.md")"
fi
summary_of "the lines no test ran are listed by the first line of their statement" '- `scripts/squad-merge-gate.sh`: 5, 14'
summary_of "and a line excluded is not among them" '- `scripts/squad-latest.sh`: 13'
summary_of "in a collapsed block" '<details><summary>The lines no test ran</summary>'
if grep -q '^- `scripts/squad-checks.sh`' "$lab/out/summary.md"; then
  fail "squad-checks.sh, whose lines all ran, is listed among the lines not run"
else
  pass "a script whose lines all ran has no line in the list"
fi
#    The thinnest scripts come first: the one no test ran, then 33.3 %, 60 %, 83.3 %, 85.7 % and
#    100 %.
order="$(grep -o '^| `[^`]*`' "$lab/out/summary.md" | sed 's/^| `//; s/`$//' | tr '\n' ' ')"
if [ "$order" = "scripts/squad-tokens.sh .githooks/pre-push scripts/squad-merge-gate.sh scripts/squad-install.sh scripts/squad-latest.sh scripts/squad-checks.sh install.sh " ]; then
  pass "the thinnest script comes first"
else
  fail "the order of the scripts: $order"
fi

# 2. --summary-only writes the same summary from the records alone, without kcov, from the root the
#    run recorded: from CI's artifact, the records name the runner's paths. It runs here in a copy
#    of the repository elsewhere, as a checkout of the commit CI measured would be.
cp "$lab/out/summary.md" "$lab/first.md"
rm -f "$lab/out/summary.md"
cp -R "$repo" "$lab/elsewhere" || exit 2
out="$(cd "$lab/elsewhere" && PATH="$(dirname "$(command -v jq)"):/usr/bin:/bin" "$coverage" --summary-only "$lab/out" 2>&1)"
code=$?
if [ "$code" -eq 3 ] && cmp -s "$lab/first.md" "$lab/out/summary.md"; then
  pass "--summary-only writes the same summary again, without kcov, from another checkout, and fails as it"
else
  fail "--summary-only: exit $code, said: $out"
fi

# 2b. The verdict (agent-squad #507): every script at 100 % and no test failed passes, exit 0, and
#     says so first; one test that failed, or one line no test ran, fails the run, exit 3, naming it.
# `verdict <case> <records> <exit> <first line>` runs the stand-in with those records, and passes
# when the run exits so and its summary's verdict reads so.
verdict() {
  local case="$1" records="$2" want="$3" says="$4" out code
  rm -rf "$lab/v-$records"
  out="$(cd "$repo" && KCOV_RECORDS="$records" PATH="$lab/bin:$PATH" "$coverage" "$lab/v-$records" 2>&1)"
  code=$?
  if [ "$code" -eq "$want" ] && [ "$(sed -n 3p "$lab/v-$records/summary.md" 2>/dev/null)" = "$says" ]; then
    pass "$case"
  else
    fail "$case: exit $code, its verdict: $(sed -n 3p "$lab/v-$records/summary.md" 2>/dev/null), said: $out"
  fi
}
verdict "every script at 100 %, no test failed: exit 0, and the summary says so first" full 0 \
  'Every measured script is fully run, and no test failed under kcov.'
verdict "every script at 100 %, but a test failed under kcov: exit 3, naming it" full-failing 3 \
  '**The coverage job fails:** a test failed under kcov: `check-handoff`.'
verdict "one line no test ran, no test failed: exit 3, naming the script and the line" full-short 3 \
  '**The coverage job fails:** below 100 % in `scripts/squad-checks.sh` (lines 3).'

# 3. Without kcov, with nothing recorded, with no run to summarise, or with bad usage, it exits
#    non-zero, saying why.
# `refused <case> <code> <message start> <command...>` runs the command in the scratch repository.
refused() {
  local case="$1" want="$2" says="$3" out code
  shift 3
  out="$(cd "$repo" && "$@" 2>&1)"
  code=$?
  if [ "$code" -eq "$want" ] && [[ "$out" == "$says"* ]]; then
    pass "$case: exit $want, saying so"
  else
    fail "$case: exit $code, said: $out"
  fi
}
refused "without kcov" 1 "ci-coverage: kcov is not installed" env PATH="/usr/bin:/bin" "$coverage" "$lab/none"
refused "with nothing recorded" 1 "ci-coverage: kcov recorded nothing in " \
  env KCOV_RECORDS=none PATH="$lab/bin:$PATH" "$coverage" "$lab/empty"
refused "with a record that cannot be read even so, which it names" 1 \
  "ci-coverage: kcov wrote records that cannot be read: runs/check-gate/check-gate.sh.0123456789abcdef/codecov.json" \
  env KCOV_RECORDS=broken PATH="$lab/bin:$PATH" "$coverage" "$lab/broken"
refused "--summary-only where no run was" 1 "ci-coverage: $lab/nothing/runs holds no run of this script" \
  "$coverage" --summary-only "$lab/nothing"
refused "without a directory" 2 "usage: ci-coverage.sh" "$coverage"

exit "$status"
