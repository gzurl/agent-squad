#!/usr/bin/env bash
# Check that the pre-push gate of SQUAD.md §4.2 behaves as the charter says (agent-squad #21): a
# failing check refuses the push, a passing one lets it through from a linked worktree and from the
# main checkout, a check that uses git leaves the pushing repository's commits and configuration
# alone, and a push that only deletes runs no check at all. The gate finds squad-checks.sh through
# its own location (#34): the gate is tested as an installed playbook (git-ignored, nested in the
# main checkout), then at the root of a repository as this one has it, and a gate that cannot find
# its runner must refuse the push. Only a PR changes main (#59): a push to the remote's default
# branch is refused unless SQUAD_MAIN_EXCEPTION names an approved exception's issue, and branches
# and tags are not affected. A ref whose commit the remote's branches already contain carries no
# new code (#143): it goes through with no check and no checkout of it, but not to main without an
# exception, and a stale remote-tracking ref cannot vouch for a commit the remote dropped.
# Everything happens in a temporary directory: this script never touches the repository it is run
# from.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
# This script builds repositories of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)
# Nor may an exception exported in the environment of whoever runs this change the outcome.
unset SQUAD_MAIN_EXCEPTION

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-gate.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# `list <directory> <command>` makes that checkout's checks the one command given.
list() { printf '# the sandbox checks\n%s\n' "$2" > "$1/.agent-squad-checks"; }

# `commit <directory> <message>` records whatever changed there, quietly.
commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }

# `install_gate <directory>` copies the gate under test into <directory>/.githooks and
# <directory>/scripts, the layout the hook expects around itself.
install_gate() {
  mkdir -p "$1/.githooks" "$1/scripts"
  cp "$root/.githooks/pre-push" "$1/.githooks/pre-push"
  cp "$root/scripts/squad-checks.sh" "$1/scripts/squad-checks.sh"
  chmod +x "$1/.githooks/pre-push" "$1/scripts/squad-checks.sh"
}

# A clone with a bare remote and the gate installed as a playbook: git-ignored, in the main
# checkout only, reached from every worktree by an absolute path.
git init -q --bare "$lab/remote.git" || exit 2
git init -q "$lab/work" || exit 2
work="$lab/work"
git -C "$work" config user.email gate@example.com
git -C "$work" config user.name "Gate check"
git -C "$work" config core.bare false
git -C "$work" remote add origin "$lab/remote.git"
playbook="$work/.agent-squad/playbook"
install_gate "$playbook"
echo ".agent-squad/" > "$work/.gitignore"
git -C "$work" config core.hooksPath "$playbook/.githooks"
list "$work" true
commit "$work" "the sandbox" >/dev/null || exit 2
if ! git -C "$work" push -q origin HEAD:refs/heads/start 2>/dev/null; then
  fail "the first push, with a passing check, was refused: the gate cannot run from a playbook"
  exit 1
fi

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
if git -C "$work" push -q origin HEAD:refs/heads/from-main-checkout 2>/dev/null; then
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

# 6. A hook that cannot run squad-checks.sh next to it, missing or not executable, refuses every
#    push, one whose checks pass and one that only deletes, and says why: no other refusal counts.
# `refused_for_runner <description> <refspec>` pushes from the worktree and expects the hook's own
# message about its runner.
refused_for_runner() {
  local errors
  if errors="$(git -C "$wt" push -q origin "$2" 2>&1)"; then
    fail "$1 let the push through"
  elif grep -q 'is missing or not executable' <<<"$errors"; then
    pass "$1 refuses the push and says why"
  else
    fail "$1 refused the push for another reason: $errors"
  fi
}
runner="$playbook/scripts/squad-checks.sh"
list "$wt" true
commit "$wt" "a passing check, with the runner broken" >/dev/null
# A branch to delete below, pushed while the runner still works.
git -C "$wt" push -q origin HEAD:refs/heads/doomed-too 2>/dev/null
mv "$runner" "$lab/squad-checks.sh.aside"
refused_for_runner "a hook without squad-checks.sh next to it" HEAD:refs/heads/wt
refused_for_runner "a hook without squad-checks.sh, on a delete-only push," :refs/heads/doomed-too
mv "$lab/squad-checks.sh.aside" "$runner"
chmod -x "$runner"
refused_for_runner "a hook whose squad-checks.sh is not executable" HEAD:refs/heads/wt
chmod +x "$runner"
mv "$runner" "$lab/squad-checks.sh.aside"
mkdir "$runner"
refused_for_runner "a hook with a directory in place of squad-checks.sh" HEAD:refs/heads/wt
rmdir "$runner"
mv "$lab/squad-checks.sh.aside" "$runner"

# 6b. A list whose lines are only an indented comment and blanks runs no check: the gate says it
#     lists no command and refuses the push, instead of reporting those lines as passing checks.
list "$wt" '  # an indented comment
   '
commit "$wt" "a list with no command" >/dev/null
if errors="$(git -C "$wt" push -q origin HEAD:refs/heads/wt 2>&1)"; then
  fail "a list of an indented comment and blanks let the push through"
elif grep -q 'lists no command' <<<"$errors"; then
  pass "a list of an indented comment and blanks refuses the push: it lists no command"
else
  fail "a list of an indented comment and blanks refused the push for another reason: $errors"
fi

# 6c. A list saved with CRLF line endings runs its commands without the carriage return, and a
#     CRLF list of only a comment and a blank line lists no command (#46).
printf '# the sandbox checks\r\ntrue\r\n' > "$wt/.agent-squad-checks"
commit "$wt" "a CRLF list" >/dev/null
if errors="$(git -C "$wt" push -q origin HEAD:refs/heads/wt 2>&1)"; then
  pass "a CRLF list runs its commands and lets the push through"
else
  fail "a CRLF list refused the push: $errors"
fi
printf '# only a comment\r\n\r\n' > "$wt/.agent-squad-checks"
commit "$wt" "a CRLF list with no command" >/dev/null
if errors="$(git -C "$wt" push -q origin HEAD:refs/heads/wt 2>&1)"; then
  fail "a CRLF list of a comment and a blank line let the push through"
elif grep -q 'lists no command' <<<"$errors"; then
  pass "a CRLF list of a comment and a blank line refuses the push: it lists no command"
else
  fail "a CRLF list of a comment and a blank line refused the push for another reason: $errors"
fi

# 7. The same hook at the root of a repository, as this one has it: tracked, next to scripts/, and
#    reached through a relative core.hooksPath from the worktree that pushes. The recording check
#    proves that the hook found its runner and ran the list, not only that the push went through.
install_gate "$wt"
list "$wt" ./records.sh
commit "$wt" "the gate at the root of the repository" >/dev/null
git -C "$work" config core.hooksPath .githooks
runs_before="$(wc -l < "$lab/ran.txt" 2>/dev/null || echo 0)"
if git -C "$wt" push -q origin HEAD:refs/heads/wt 2>/dev/null \
  && [ "$(wc -l < "$lab/ran.txt" 2>/dev/null || echo 0)" -gt "$runs_before" ]; then
  pass "the hook at the root of a repository finds its runner and runs the checks"
else
  fail "the hook at the root of a repository did not run the checks"
fi

# 8. Only a PR changes main (#59). The worktree's list is the recording check, so that a refusal
#    can be told apart from a failing check. `push_to <refspec> [<VAR=value>...]` commits something
#    new in the worktree and pushes it there, with the variables given in the environment; git's
#    messages are left in $errors.
push_to() {
  local refspec="$1"
  shift
  echo "$refspec" >> "$wt/pushed.txt"
  commit "$wt" "a push to $refspec" >/dev/null
  errors="$(env "$@" git -C "$wt" push -q origin "$refspec" 2>&1)"
}
runs() { wc -l < "$lab/ran.txt" 2>/dev/null | tr -d ' ' || echo 0; }

runs_before="$(runs)"
if push_to HEAD:refs/heads/main; then
  fail "a push to main went through"
elif grep -q 'only a PR' <<<"$errors" && grep -q 'SQUAD_MAIN_EXCEPTION' <<<"$errors" \
  && [ "$(runs)" = "$runs_before" ]; then
  pass "a push to main is refused before any check runs, saying how an exception is pushed"
else
  fail "a push to main was refused, but not by the rule, or after running the checks: $errors"
fi

for exception in '#12' 12; do
  runs_before="$(runs)"
  if push_to HEAD:refs/heads/main SQUAD_MAIN_EXCEPTION="$exception" \
    && grep -q 'exception the CEO approved on #12' <<<"$errors" && [ "$(runs)" -gt "$runs_before" ]; then
    pass "SQUAD_MAIN_EXCEPTION=$exception lets the push to main through, names the issue and runs the checks"
  else
    fail "SQUAD_MAIN_EXCEPTION=$exception did not let the push to main through as announced: $errors"
  fi
done

for exception in abc '#' 12a 012 0 '#-1' '1 2'; do
  if push_to HEAD:refs/heads/main SQUAD_MAIN_EXCEPTION="$exception"; then
    fail "SQUAD_MAIN_EXCEPTION='$exception' let the push to main through"
  elif grep -q 'is not an issue number' <<<"$errors"; then
    pass "SQUAD_MAIN_EXCEPTION='$exception' is not an issue number, and the push to main is refused"
  else
    fail "SQUAD_MAIN_EXCEPTION='$exception' refused the push for another reason: $errors"
  fi
done

if push_to HEAD:refs/heads/a-branch && push_to HEAD:refs/heads/a-branch SQUAD_MAIN_EXCEPTION=abc; then
  pass "a branch push is not affected, whatever SQUAD_MAIN_EXCEPTION holds"
else
  fail "a branch push was refused: $errors"
fi

echo "a release" >> "$wt/pushed.txt"
commit "$wt" "a commit that only the tag carries to the remote" >/dev/null
git -C "$wt" tag -a v99 -m "a release" HEAD
runs_before="$(runs)"
if errors="$(git -C "$wt" push -q origin refs/tags/v99 2>&1)" && [ "$(runs)" -gt "$runs_before" ]; then
  pass "a tag on a new commit is not a push to main: it goes through, after the checks"
else
  fail "a tag push was refused, or ran no check: $errors"
fi

echo "two refs" >> "$wt/pushed.txt"
commit "$wt" "a push to a branch and to main at once" >/dev/null
if errors="$(git -C "$wt" push -q origin HEAD:refs/heads/a-branch HEAD:refs/heads/main 2>&1)"; then
  fail "a push to a branch and to main at once went through"
else
  pass "a push to a branch and to main at once is refused"
fi

# The protected branch is the remote's default one when git knows it, as git records it for origin.
git -C "$work" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
if push_to HEAD:refs/heads/trunk; then
  fail "a push to the remote's default branch, trunk, went through"
elif grep -q 'only a PR' <<<"$errors"; then
  pass "a push to the remote's default branch, when it is not main, is refused"
else
  fail "a push to trunk was refused for another reason: $errors"
fi
if push_to HEAD:refs/heads/main; then
  pass "and main, then an ordinary branch, is not protected"
else
  fail "a push to main was refused although the remote's default branch is trunk: $errors"
fi
git -C "$work" symbolic-ref --delete refs/remotes/origin/HEAD

# 9. A ref whose commit is already on the remote carries no new code (#143): the gate lets it
#    through as it does a deletion, with no check run and no look at uncommitted changes. What
#    counts is the remote's branches as the remote lists them at the push, so that a stale
#    remote-tracking ref can only make the gate refuse. A ref with a new commit still has to be
#    the checked-out one, and the protected branch still takes a PR, whatever the commit.
old="$(git -C "$wt" rev-parse refs/remotes/origin/a-branch)"
git -C "$wt" tag -a v1 -m "a past release" "$old"
echo "more work" >> "$wt/pushed.txt"
commit "$wt" "new work that the remote does not have" >/dev/null
echo "not committed" >> "$wt/pushed.txt"
runs_before="$(runs)"
if errors="$(git -C "$wt" push -q origin refs/tags/v1 2>&1)" && [ "$(runs)" = "$runs_before" ]; then
  pass "an annotated tag on a commit already on the remote goes through from another checkout, with no check run and a dirty tree"
else
  fail "a tag on a commit already on the remote was refused, or ran the checks: $errors"
fi
git -C "$wt" checkout -q -- pushed.txt

git -C "$wt" tag -a v2 -m "an unreleased commit" HEAD
echo "later work" >> "$wt/pushed.txt"
commit "$wt" "the checkout moves on" >/dev/null
if errors="$(git -C "$wt" push -q origin refs/tags/v2 2>&1)"; then
  fail "a tag on a new commit that is not checked out went through"
elif grep -q 'is not the checked-out commit' <<<"$errors"; then
  pass "a tag on a new commit that is not checked out is still refused"
else
  fail "a tag on a new commit was refused for another reason: $errors"
fi

git -C "$wt" tag -a v3 -m "another past release" "$old"
runs_before="$(runs)"
if errors="$(git -C "$wt" push -q origin refs/tags/v3 HEAD:refs/heads/a-branch 2>&1)" \
  && [ "$(runs)" -gt "$runs_before" ]; then
  pass "an old tag pushed with the checked-out new commit runs the checks"
else
  fail "an old tag pushed with a new commit did not run the checks, or was refused: $errors"
fi

runs_before="$(runs)"
# Forced, so that git's own fast-forward rule does not refuse it before the gate has its say.
if errors="$(git -C "$wt" push -q origin "+$old:refs/heads/main" 2>&1)"; then
  fail "pointing main at a commit already on the remote went through without an exception"
elif grep -q 'only a PR' <<<"$errors" && [ "$(runs)" = "$runs_before" ]; then
  pass "pointing main at a commit already on the remote is still refused without an exception"
else
  fail "pointing main at an existing commit was refused for another reason: $errors"
fi

# A branch the remote no longer has, though the local remote-tracking ref still names it: its
# commit is new to the remote again, so its tag is treated as new code.
echo "gone" >> "$wt/pushed.txt"
commit "$wt" "a commit only a doomed branch carries" >/dev/null
git -C "$wt" push -q origin HEAD:refs/heads/doomed-branch 2>/dev/null || exit 2
doomed="$(git -C "$wt" rev-parse HEAD)"
git -C "$lab/remote.git" update-ref -d refs/heads/doomed-branch
git -C "$wt" tag -a v4 -m "a tag on a commit the remote dropped" "$doomed"
echo "moving on" >> "$wt/pushed.txt"
commit "$wt" "the checkout moves on again" >/dev/null
if git -C "$wt" rev-parse -q --verify refs/remotes/origin/doomed-branch >/dev/null \
  && ! errors="$(git -C "$wt" push -q origin refs/tags/v4 2>&1)" \
  && grep -q 'is not the checked-out commit' <<<"$errors"; then
  pass "a stale remote-tracking ref does not let a commit the remote dropped through unchecked"
else
  fail "a commit only a stale remote-tracking ref knows went through, or was refused otherwise: $errors"
fi

# 10. A tree whose tracked files have uncommitted changes is refused before any check runs: the
#     checks would test those changes, not the commit being pushed (#184). An untracked file does
#     not count, since no check sees it as part of the commit.
echo "pushed from a dirty tree" >> "$wt/pushed.txt"
commit "$wt" "a commit pushed while a tracked file changes" >/dev/null
echo "not committed" >> "$wt/pushed.txt"
runs_before="$(runs)"
if ! errors="$(git -C "$wt" push -q origin HEAD:refs/heads/dirty 2>&1)" \
  && grep -qF 'tracked files have uncommitted changes' <<<"$errors" && [ "$(runs)" = "$runs_before" ]; then
  pass "a tree with uncommitted changes to tracked files is refused, saying so, before any check runs"
else
  fail "a dirty tree went through, ran a check, or was refused for another reason: $errors"
fi
git -C "$wt" checkout -q -- pushed.txt
echo "not tracked" > "$wt/untracked.txt"
if git -C "$wt" push -q origin HEAD:refs/heads/dirty 2>/dev/null && [ "$(runs)" -gt "$runs_before" ]; then
  pass "an untracked file does not stop the push, and the checks run"
else
  fail "an untracked file stopped the push, or no check ran"
fi
rm -f "$wt/untracked.txt"

exit "$status"
