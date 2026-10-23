#!/usr/bin/env bash
# Check that check-private-names.sh refuses a tracked file, by its path or its text, or a commit
# not yet on origin/main, by its message, the paths it touches or the lines it adds, that names a
# private repository of the owner, in any case and with any separator between its words, and says
# where without naming it; that it passes when none is named; that it fails when GitHub
# cannot be read, and passes, unchecked, in GitHub Actions (agent-squad #514). The names here are
# made up, and a stub gh lists them. Everything happens in a scratch repository, so this script
# touches neither the repository it is run from nor GitHub.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
check="$root/scripts/check-private-names.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)
unset GITHUB_ACTIONS SQUAD_GH_TIMEOUT

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-private-names-checker.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# The stub gh: for the owner acme's private repositories it lists two made-up names, and records
# each call in $lab/gh.calls. GH_STUB=fail makes it fail, as without a network; hang makes it never
# answer; none makes it list nothing.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$lab/gh.calls"
case "\${GH_STUB:-}" in
  fail) echo "error connecting to api.github.com" >&2; exit 1 ;;
  hang) exec sleep 30 ;;
  none) exit 0 ;;
esac
[ "\$*" = "repo list acme --visibility private --limit 1000 --json name --jq .[].name" ] \\
  || { echo "stub gh: unexpected call: \$*" >&2; exit 3; }
printf 'Secret-Garden\nhidden_lake\n'
EOF
chmod +x "$lab/bin/gh"

# The scratch repository: a commit that origin/main points at, whose message names one of them, as
# main's older messages do, then the branch's own commits.
repo="$lab/repo"
git init -q "$repo" || exit 2
git -C "$repo" config user.email names@example.com
git -C "$repo" config user.name "Names check"
git -C "$repo" remote add origin git@github.com:acme/open-thing.git
printf '# Open thing\n\nNothing private here.\n' > "$repo/README.md"
git -C "$repo" add -A && git -C "$repo" commit -qm "Credit the secret-garden project" || exit 2
git -C "$repo" update-ref refs/remotes/origin/main HEAD || exit 2

# `run [<variable>=<value>...]` runs the check in the scratch repository with the stub first on the
# PATH, its output in $out and its exit status in $code. `named` passes when the output names
# neither made-up repository, in any form.
run() {
  rm -f "$lab/gh.calls"
  out="$(cd "$repo" && env PATH="$lab/bin:$PATH" "$@" "$check" 2>&1)"
  code=$?
}
named() { grep -qiE 'secret|garden|hidden|lake' <<<"$out"; }
# `commit <file> <text> [<message>]` writes the text to that file and commits it.
commit() {
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "$2" > "$repo/$1"
  git -C "$repo" add -A && git -C "$repo" commit -qm "${3:-Add $1}"
}
# `undo` drops the branch's commits and untracked files, back to origin/main.
undo() { git -C "$repo" reset -q --hard origin/main && git -C "$repo" clean -qfd; }

# 1. None is named: a tracked file and a new commit that name neither, and one inside a longer word.
commit notes.md $'A note.\nThe unsecret-gardens and hidden-lakes are words, not names.' "Add a note"
run
if [ "$code" -eq 0 ] && [ "$out" = "private names: no tracked file, and no commit since origin/main, names one of acme's 2 private repositories" ]; then
  pass "none named, nor inside a longer word, nor in a message on origin/main: it passes, and counts them"
else
  fail "none named: exit $code, said: $out"
fi
undo

# 2. A tracked file names one, in any case, with each separator between its words.
for form in SECRET_GARDEN Secret-Garden secret.garden "Secret Garden" secretgarden "(hidden_lake)" HIDDEN-LAKE; do
  commit docs/notes.md $'Line one.\nLine two.\nSee '"$form"' for it.'
  run
  if [ "$code" -eq 1 ] && grep -qxF '  docs/notes.md:3' <<<"$out" && ! named; then
    pass "a tracked file names one as '$form': it fails, naming the file and line, not the repository"
  else
    fail "a tracked file names one as '$form': exit $code, said: $out"
  fi
  undo
done

# 2b. A tracked file's path names one: it fails, masking the name in the path, wherever it prints it.
commit docs/Secret-Garden-notes.md $'A neutral line.\nAnd hidden_lake.'
run
if [ "$code" -eq 1 ] && grep -qxF '  docs/***-notes.md (its path)' <<<"$out" && grep -qxF '  docs/***-notes.md:2' <<<"$out" \
   && ! named; then
  pass "a tracked file's path names one: it fails, the name masked in the path wherever it prints it"
else
  fail "a tracked file's path names one: exit $code, said: $out"
fi
undo

# 3. An untracked file that names one is no push's: it passes.
printf 'hidden_lake\n' > "$repo/scratch.txt"
run
if [ "$code" -eq 0 ]; then
  pass "an untracked file that names one: it passes"
else
  fail "an untracked file that names one: exit $code, said: $out"
fi
undo

# 4. A commit not yet on origin/main names one in its message: it fails, naming the commit.
commit other.md "Nothing here." $'Add other.md\n\nFor the Hidden Lake project.'
named_commit="$(git -C "$repo" rev-parse --short HEAD)"
commit more.md "Nor here." "Add more.md"
run
if [ "$code" -eq 1 ] && [ "$(grep -c '^  ' <<<"$out")" = 1 ] && grep -qxF "  commit $named_commit" <<<"$out" && ! named; then
  pass "a new commit's message names one: it fails, naming that commit alone, not the repository"
else
  fail "a new commit's message names one: exit $code, said: $out"
fi
undo

# 4b. A commit not yet on origin/main adds a line that names one, and the next removes it: GitHub
#     keeps both after the squash (QA's finding on PR #518). It fails, naming the first alone.
commit notes.md "See secret garden."
added="$(git -C "$repo" rev-parse --short HEAD)"
commit notes.md "See nothing." "Reword notes.md"
run
if [ "$code" -eq 1 ] && [ "$(grep -c '^  ' <<<"$out")" = 1 ] && grep -qxF "  commit $added" <<<"$out" && ! named; then
  pass "a new commit adds a line that names one, which the next removes: it fails, naming that commit"
else
  fail "a line added, then removed: exit $code, said: $out"
fi
undo

# 4c. A commit adds an empty file at a path that names one, and the next deletes it: both touch the
#     path, and it fails, naming the two.
mkdir -p "$repo/docs" && : > "$repo/docs/hidden-lake.md"
git -C "$repo" add -A && git -C "$repo" commit -qm "Add an empty page"
empty="$(git -C "$repo" rev-parse --short HEAD)"
git -C "$repo" rm -q docs/hidden-lake.md && git -C "$repo" commit -qm "Drop the empty page"
dropped="$(git -C "$repo" rev-parse --short HEAD)"
run
if [ "$code" -eq 1 ] && [ "$(grep -c '^  ' <<<"$out")" = 2 ] && grep -qxF "  commit $empty" <<<"$out" \
   && grep -qxF "  commit $dropped" <<<"$out" && ! named; then
  pass "new commits add, then delete, a path that names one: it fails, naming both"
else
  fail "a path added, then deleted: exit $code, said: $out"
fi
undo

# 5. GitHub cannot be read: gh fails, or never answers within SQUAD_GH_TIMEOUT.
for stub in fail hang; do
  run GH_STUB="$stub" SQUAD_GH_TIMEOUT=1
  if [ "$code" -eq 1 ] && grep -qF "private names: GitHub could not be read, so acme's private repositories are unknown and nothing was checked" <<<"$out"; then
    pass "gh that does $stub: it fails, and says GitHub could not be read"
  else
    fail "gh that does $stub: exit $code, said: $out"
  fi
done

# 6. In GitHub Actions it does not check, even with one named, and asks GitHub nothing.
commit docs/notes.md "See secret-garden."
run GITHUB_ACTIONS=true
if [ "$code" -eq 0 ] && [ "$out" = "private names: not checked: GitHub Actions cannot list the owner's private repositories" ] \
   && [ ! -e "$lab/gh.calls" ]; then
  pass "in GitHub Actions: it passes, says it did not check, and asks GitHub nothing"
else
  fail "in GitHub Actions: exit $code, gh called: $([ -e "$lab/gh.calls" ] && echo yes || echo no), said: $out"
fi
undo

# 7. The owner has no private repository: it passes, and says so.
run GH_STUB=none
if [ "$code" -eq 0 ] && [ "$out" = "private names: acme has no private repository to look for" ]; then
  pass "no private repository: it passes, and says so"
else
  fail "no private repository: exit $code, said: $out"
fi

# 8. Neither the owner nor the new commits can be told: origin is not on GitHub, or origin/main is
#    unknown. Each fails, saying why.
git -C "$repo" remote set-url origin https://example.com/acme/open-thing.git
run
if [ "$code" -eq 1 ] && grep -qF "origin is not a GitHub repository" <<<"$out" && [ ! -e "$lab/gh.calls" ]; then
  pass "origin not on GitHub: it fails, and says so"
else
  fail "origin not on GitHub: exit $code, said: $out"
fi
git -C "$repo" remote set-url origin https://github.com/acme/open-thing
git -C "$repo" update-ref -d refs/remotes/origin/main
run
if [ "$code" -eq 1 ] && grep -qF "origin/main is unknown" <<<"$out"; then
  pass "origin/main unknown: it fails, and says to fetch it"
else
  fail "origin/main unknown: exit $code, said: $out"
fi

exit "$status"
