#!/usr/bin/env bash
# Check that CI runs every test the pre-push gate runs (agent-squad #177). Each scripts/check-*.sh
# of the repository is a line of .agent-squad-checks and the run: of a step of the CI workflow, and
# neither file names a scripts/check-*.sh that does not exist. The two lists are kept by hand, and
# PR #154 once added a test to the first only: CI never ran it, on the Ubuntu it runs on.
set -u
root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root" || exit 2
checks=.agent-squad-checks
ci=.github/workflows/ci.yml

found=0
# `missing <message>` reports one gap.
missing() { echo "check-ci: $1"; found=1; }

# Every test of the repository is in both lists. A step runs it when its run: line is that path
# alone.
for test in scripts/check-*.sh; do
  grep -qxF "$test" "$checks" || missing "$test is not a line of $checks"
  grep -qxE "[[:space:]]*run:[[:space:]]+${test//./\\.}[[:space:]]*" "$ci" || missing "no step of $ci runs $test"
done
# Neither list names a test that is not there.
while IFS= read -r test; do
  [ -f "$test" ] || missing "$checks names $test, which does not exist"
done < <(grep -xE 'scripts/check-[^ ]+\.sh' "$checks")
while IFS= read -r test; do
  [ -f "$test" ] || missing "$ci runs $test, which does not exist"
done < <(grep -oE 'run:[[:space:]]+scripts/check-[^ ]+\.sh' "$ci" | sed -E 's/^run:[[:space:]]+//')
exit "$found"
