#!/usr/bin/env bash
# Check that the push gate of SQUAD.md §4.2 behaves as the charter says (agent-squad #21): a
# failing check refuses the push, a passing one lets it through from a linked worktree and from the
# main checkout, a check that uses git leaves the pushing repository's commits and configuration
# alone, and a push that only deletes runs no check at all. Everything happens in a temporary
# directory: this script never touches the repository it is run from.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
# This script builds repositories of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

lab="$(mktemp -d)" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# `list <directory> <command>` makes that checkout's checks the one command given.
list() { printf '# the sandbox checks\n%s\n' "$2" > "$1/.squad/checks"; }

# `commit <directory> <message>` records whatever changed there, quietly.
commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }

# A clone of the gate under test, with a bare remote and the hook enabled.
git init -q --bare "$lab/remote.git" || exit 2
git init -q "$lab/work" || exit 2
work="$lab/work"
git -C "$work" config user.email gate@example.com
git -C "$work" config user.name "Gate check"
git -C "$work" config core.bare false
git -C "$work" remote add origin "$lab/remote.git"
mkdir -p "$work/.squad" "$work/.githooks" "$work/scripts"
cp "$root/.githooks/pre-push" "$work/.githooks/pre-push"
cp "$root/scripts/squad-checks.sh" "$work/scripts/squad-checks.sh"
chmod +x "$work/.githooks/pre-push" "$work/scripts/squad-checks.sh"
git -C "$work" config core.hooksPath .githooks
list "$work" true
commit "$work" "the sandbox" >/dev/null || exit 2
git -C "$work" push -q origin HEAD:refs/heads/main 2>/dev/null || exit 2

# A check that uses git as a project's tests do: its own repository in a temporary directory.
cat > "$work/uses-git.sh" <<'CHECK'
#!/usr/bin/env bash
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q .
# Written first, before anything that a leaked GIT_DIR would make fail: under a leak this is the
# deliberate write that lands in the repository being pushed, and the test looks for it there.
git config squadgate.stray yes
git config user.email inner@example.com
git config user.name Inner
echo inner > f.txt
git add f.txt
git commit -qm "a commit that belongs to this temporary repository"
test "$(git rev-list --count HEAD)" = 1
CHECK
chmod +x "$work/uses-git.sh"
# A check that records every time it runs, to tell a push that ran nothing from one that did.
printf '#!/usr/bin/env bash\necho ran >> "%s/ran.txt"\n' "$lab" > "$work/records.sh"
chmod +x "$work/records.sh"
commit "$work" "the checks this test uses" >/dev/null

# The worktree every agent pushes from, and where git exports GIT_DIR to the hook (#19).
git -C "$work" worktree add -q -b wt "$lab/wt" || exit 2
wt="$lab/wt"

# 1. A failing check refuses the push, from the worktree.
list "$wt" false
commit "$wt" "a failing check" >/dev/null
if git -C "$wt" push -q origin HEAD:refs/heads/wt 2>/dev/null; then
  fail "a failing check let the push through"
else
  pass "a failing check refuses the push"
fi

# 2. A passing list lets it through, from the worktree.
list "$wt" true
commit "$wt" "a passing check" >/dev/null
if git -C "$wt" push -q origin HEAD:refs/heads/wt 2>/dev/null; then
  pass "a passing check lets the push through, from a linked worktree"
else
  fail "a passing check refused the push from a linked worktree"
fi

# 3. And from the main checkout.
list "$work" true
commit "$work" "a passing check in the main checkout" >/dev/null
if git -C "$work" push -q origin HEAD:refs/heads/main 2>/dev/null; then
  pass "a passing check lets the push through, from the main checkout"
else
  fail "a passing check refused the push from the main checkout"
fi

# 4. A check that uses git leaves the repository that is pushing alone (#19). Pushed from the
#    worktree, which is the only place git hands the hook its own GIT_DIR.
list "$wt" ./uses-git.sh
commit "$wt" "a check that uses git" >/dev/null
# Taken with the commit already made: what must not change is what the push starts from.
expected_head="$(git -C "$wt" rev-parse HEAD)"
before_refs="$(git -C "$work" show-ref)"
before_bare="$(git -C "$work" config --get core.bare)"
before_stray="$(git -C "$work" config --get squadgate.stray || true)$(git -C "$wt" config --get squadgate.stray || true)"
if git -C "$wt" push -q origin HEAD:refs/heads/wt 2>/dev/null; then
  pass "a check that uses git passes and its push goes through"
else
  fail "a check that uses git could not push"
fi
after_head="$(git -C "$wt" rev-parse HEAD)"
after_bare="$(git -C "$work" config --get core.bare)"
after_stray="$(git -C "$work" config --get squadgate.stray || true)$(git -C "$wt" config --get squadgate.stray || true)"
if [ "$after_head" = "$expected_head" ]; then
  pass "the pushing worktree's HEAD is the commit it pushed, not one its checks made"
else
  fail "the checks moved the pushing worktree's HEAD: $expected_head -> $after_head"
fi
# Only the remote-tracking ref of the branch just pushed may be new.
unexpected="$(git -C "$work" show-ref | grep -v 'refs/remotes/origin/' | diff - <(echo "$before_refs" | grep -v 'refs/remotes/origin/') || true)"
if [ -z "$unexpected" ]; then
  pass "no ref of the pushing repository changed but its remote-tracking ones"
else
  fail "the checks changed refs of the pushing repository: $unexpected"
fi
if [ "$after_bare" = "$before_bare" ] && [ "$after_stray" = "$before_stray" ]; then
  pass "the pushing repository's configuration is untouched"
else
  fail "the checks wrote configuration into the pushing repository (core.bare $before_bare -> $after_bare, squadgate.stray '$before_stray' -> '$after_stray')"
fi

# 5. A push that only deletes runs no check.
list "$wt" ./records.sh
commit "$wt" "the recording check" >/dev/null
git -C "$wt" push -q origin HEAD:refs/heads/doomed 2>/dev/null
runs_before="$(wc -l < "$lab/ran.txt" 2>/dev/null || echo 0)"
git -C "$wt" push -q origin :refs/heads/doomed 2>/dev/null
runs_after="$(wc -l < "$lab/ran.txt" 2>/dev/null || echo 0)"
if [ "$runs_before" = "$runs_after" ]; then
  pass "a push that only deletes runs no check"
else
  fail "a delete-only push ran the checks"
fi

exit "$status"
