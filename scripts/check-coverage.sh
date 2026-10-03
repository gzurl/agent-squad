#!/usr/bin/env bash
# Check what ci-coverage.sh makes of what kcov records (agent-squad #180), in a scratch repository
# whose scripts are written for it, with a kcov that writes fixed records instead of running the
# tests. A copy counts for the script of the same name when it has the same lines to measure, and
# a different script of that name does not; a line counts once however many tests ran it; kcov's
# "hits/total" counts the hits; a statement over several lines counts once, run if kcov recorded
# any of its lines, and is left out if it recorded none; an empty case branch counts only if it
# ran. The summary names a test that failed, lists the thinnest script first, rounds its shares,
# lists the lines no test ran, and --summary-only writes it again from the records alone. Without
# kcov, or with nothing recorded, it exits 1. This script runs none of the tests and touches
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
# was recorded nowhere, whose \ line ran on its second; install.sh, two lines of three run; and
# squad-install.sh, recorded on the first line of each heredoc's statement, on 11 and on the
# here-string, with 13 unrun.
# KCOV_RECORDS=none makes it record nothing; --merge writes an index.
mkdir -p "$lab/bin"
cat > "$lab/bin/kcov" <<'KCOV'
#!/usr/bin/env bash
if [ "$1" = --merge ]; then mkdir -p "$2" && touch "$2/index.html"; exit 0; fi
out="$2" test="$3" root="$(git rev-parse --show-toplevel)"
[ "${KCOV_RECORDS:-}" != none ] || exit 0
dir="$out/$(basename "$test").0123456789abcdef"
mkdir -p "$dir"
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
      "scripts/squad-install.sh": {"2": 1, "6": 0, "7": 1, "8": 1, "9": 0, "11": 1, "12": 1, "13": 0}}}' ;;
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
if [ "$code" -eq 0 ] && [ -f "$lab/out/report/index.html" ] && [ "$out" = "$(cat "$lab/out/summary.md")" ]; then
  pass "it exits 0, prints the summary it writes, and merges kcov's reports"
else
  fail "a run: exit $code, printed: $out"
fi
summary_of "a copy with the same lines counts, a different script of that name does not, and a line one test ran stays run" \
  '| `scripts/squad-checks.sh` (and 1 copy) | 4 | 4 | 100 % |'
summary_of "a hits/total count is read as its hits" '| `.githooks/pre-push` | 1 | 3 | 33.3 % |'
summary_of "a statement over several lines counts once, as run if any line of it ran; one recorded nowhere, and an empty case branch, are left out" \
  '| `scripts/squad-merge-gate.sh` | 3 | 5 | 60 % |'
summary_of "a heredoc belongs to its statement, its apostrophe and parenthesis read as text, and so does the end of a \$( ) around it; a here-string opens none" \
  '| `scripts/squad-install.sh` | 5 | 6 | 83.3 % |'
summary_of "a share is rounded, not cut: two of three is 66.7 %" '| `install.sh` | 2 | 3 | 66.7 % |'
summary_of "a script no test ran" '| `scripts/squad-tokens.sh` | 0 | 0 | not run |'
summary_of "the total adds up the scripts: 15 of 21 is 71.4 %" '| **Total** | **15** | **21** | **71.4 %** |'
summary_of "a test that failed under kcov is named" 'Tests that failed under kcov, so their figures may be short: `check-handoff`.'
if grep -qF 'kcov recorded 1 such statement on none of its lines; whether it ran is unknown, so it is left out.' "$lab/out/summary.md" \
   && grep -qF 'so it reads lower; `scripts/ci-coverage.sh --summary-only` gives these figures back' "$lab/out/summary.md"; then
  pass "the summary says how many statements it left out, and why kcov's own report reads lower"
else
  fail "the summary's text: $(sed -n 3p "$lab/out/summary.md")"
fi
summary_of "the lines no test ran are listed by the first line of their statement" '- `scripts/squad-merge-gate.sh`: 5, 14'
summary_of "in a collapsed block" '<details><summary>The lines no test ran</summary>'
if grep -q '^- `scripts/squad-checks.sh`' "$lab/out/summary.md"; then
  fail "squad-checks.sh, whose lines all ran, is listed among the lines not run"
else
  pass "a script whose lines all ran has no line in the list"
fi
#    The thinnest scripts come first: the one no test ran, then 33.3 %, 60 %, 66.7 %, 83.3 % and
#    100 %.
order="$(grep -o '^| `[^`]*`' "$lab/out/summary.md" | sed 's/^| `//; s/`$//' | tr '\n' ' ')"
if [ "$order" = "scripts/squad-tokens.sh .githooks/pre-push scripts/squad-merge-gate.sh install.sh scripts/squad-install.sh scripts/squad-checks.sh " ]; then
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
if [ "$code" -eq 0 ] && cmp -s "$lab/first.md" "$lab/out/summary.md"; then
  pass "--summary-only writes the same summary again, without kcov, from another checkout"
else
  fail "--summary-only: exit $code, said: $out"
fi

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
refused "--summary-only where no run was" 1 "ci-coverage: $lab/nothing/runs holds no run of this script" \
  "$coverage" --summary-only "$lab/nothing"
refused "without a directory" 2 "usage: ci-coverage.sh" "$coverage"

exit "$status"
