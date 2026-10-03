#!/usr/bin/env bash
# Check what ci-coverage.sh makes of what kcov records (agent-squad #180), with a kcov that writes
# fixed records instead of running the tests. A copy that a test runs from a temporary directory
# counts for the repository's script of the same name when it has the same lines to measure, and
# a different script of that name does not; a line counts once however many tests ran it; kcov's
# "hits/total" form is read like a plain count; the summary names a test that failed under kcov,
# lists the thinnest script first, and adds up a total. Without kcov, or with nothing recorded, it
# exits 1. Everything happens in a temporary directory; this script runs none of the tests.
# shellcheck disable=SC2016 # the summary's backticks are Markdown, meant literally
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
coverage="$root/scripts/ci-coverage.sh"

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-coverage.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# kcov, as far as ci-coverage.sh is concerned. For check-gate.sh it records the repository's
# squad-checks.sh with line 5 run; a copy of it with the same four lines, 3 and 4 run, one written
# as "hits/total"; a different squad-checks.sh with other lines, all run; and .githooks/pre-push.
# For check-handoff.sh, which runs after it, it records line 9 of squad-checks.sh as run and line 5
# as not, and fails. For check-merge-gate.sh it records lines of squad-merge-gate.sh: 30 and 31,
# which carry on a quoted jq program, 40, which ends with a \ inside a $( ), and 63, which ends
# with a \ after it, all unrun; 41, which carries on a $( ), run; 33, which ends the program, and
# 64, which ends 63's statement, run; 50, a statement of its own, unrun; and 70, which starts a
# $( ) over six lines, run, with 75, which ends it, unrun, as kcov records some statements on their
# first line; and 84, an empty case branch, unrun. As kcov does, each record names its files past the part they share, which the
# cobertura.xml beside it gives as its <source>: "/" for check-gate.sh, whose files are in two
# places, and the scripts' directory for check-handoff.sh. KCOV_RECORDS=none makes
# it record nothing. --merge writes an index.
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
      ($r + "/scripts/squad-checks.sh"): {"3": 0, "4": 0, "5": 1, "9": 0},
      "tmp/lab/playbook/scripts/squad-checks.sh": {"3": 1, "4": "2/2", "5": 0, "9": 0},
      "tmp/lab/stub/squad-checks.sh": {"1": 5, "2": 5},
      ($r + "/.githooks/pre-push"): {"2": 1, "7": 0}}}' ;;
  *check-merge-gate.sh) echo "<sources><source>$root/</source></sources>" > "$dir/cobertura.xml"
    jq -n '{coverage: {"scripts/squad-merge-gate.sh": {"30": 0, "31": 0, "33": 1, "40": 0, "41": 5, "50": 0, "63": 0, "64": 1, "70": 2, "75": 0, "84": 0}}}' ;;
  *check-handoff.sh) echo "<sources><source>$root/scripts/</source></sources>" > "$dir/cobertura.xml"
    jq -n '{coverage: {"squad-checks.sh": {"3": 0, "5": 0, "9": "1/1"}}}'
    exit 1 ;;
  *) exit 0 ;;
esac > "$dir/codecov.json"
KCOV
chmod +x "$lab/bin/kcov"

# `summary_of <case> <expected line>` passes when the last run's summary holds that line.
summary_of() {
  if grep -qxF -- "$2" "$lab/out/summary.md" 2>/dev/null; then pass "$1"; else fail "$1: no line '$2' in: $(cat "$lab/out/summary.md" 2>/dev/null)"; fi
}

# 1. A run with the stand-in.
out="$(PATH="$lab/bin:$PATH" "$coverage" "$lab/out" 2>&1)"
code=$?
if [ "$code" -eq 0 ] && [ -f "$lab/out/report/index.html" ] && [ "$out" = "$(cat "$lab/out/summary.md")" ]; then
  pass "it exits 0, prints the summary it writes, and merges kcov's reports"
else
  fail "a run: exit $code, printed: $out"
fi
summary_of "a copy with the same lines counts, a different script of that name does not, and a line one test ran stays run" \
  '| `scripts/squad-checks.sh` (and 1 copy) | 4 | 4 | 100 % |'
summary_of "a script seen in one test only" '| `.githooks/pre-push` | 1 | 2 | 50 % |'
summary_of "a script no test ran" '| `install.sh` | 0 | 0 | not run |'
summary_of "the unrun lines of a statement written over several lines are left out, and a run one stays" \
  '| `scripts/squad-merge-gate.sh` | 4 | 5 | 80 % |'
summary_of "the total adds up the scripts" '| **Total** | **9** | **11** | **81.8 %** |'
summary_of "a test that failed under kcov is named" 'Tests that failed under kcov, so their figures may be short: `check-handoff`.'
summary_of "the lines no test ran are listed, without the lines that carry on a statement" '- `scripts/squad-merge-gate.sh`: 50'
summary_of "the list is a collapsed block" '<details><summary>The lines no test ran</summary>'
if grep -q '^- `scripts/squad-checks.sh`' "$lab/out/summary.md"; then
  fail "squad-checks.sh, whose lines all ran, is listed among the lines not run"
else
  pass "a script whose lines all ran has no line in the list"
fi
#    The thinnest scripts come first: those no test ran, then pre-push at 50 %, squad-merge-gate at
#    80 % and squad-checks at 100 %.
order="$(grep -o '^| `[^`]*`' "$lab/out/summary.md" | sed 's/^| `//; s/`$//' | tail -n 3 | tr '\n' ' ')"
if [ "$order" = ".githooks/pre-push scripts/squad-merge-gate.sh scripts/squad-checks.sh " ]; then
  pass "the thinnest script comes first"
else
  fail "the order of the last three scripts: $order"
fi

# 2. Without kcov, or with nothing recorded, it exits 1, saying why.
out="$(PATH="/usr/bin:/bin" "$coverage" "$lab/none" 2>&1)"
code=$?
if [ "$code" -eq 1 ] && [ "$out" = "ci-coverage: kcov is not installed" ]; then
  pass "without kcov it exits 1, saying so"
else
  fail "without kcov: exit $code, said: $out"
fi
out="$(KCOV_RECORDS=none PATH="$lab/bin:$PATH" "$coverage" "$lab/empty" 2>&1)"
code=$?
if [ "$code" -eq 1 ] && [[ "$out" == "ci-coverage: kcov recorded nothing in "* ]]; then
  pass "with nothing recorded it exits 1, saying so"
else
  fail "nothing recorded: exit $code, said: $out"
fi

exit "$status"
