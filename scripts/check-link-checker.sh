#!/usr/bin/env bash
# Check that check-links.sh catches what it says it catches (agent-squad #176): a Markdown link or
# image, an HTML src or href, and an anchor, each broken on its own, fail it, naming the file and
# the target; each of them whole passes, and so do URLs, which it does not fetch. Anchors are
# compared with the headings' ids as GitHub computes them, emoji and repeated headings included,
# and with the id and name attributes of HTML tags. Everything happens in a scratch repository, so
# this script touches neither the repository it is run from nor GitHub.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
links="$root/scripts/check-links.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-link-checker.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# The scratch repository: a guide with headings, an image, a licence, and templates/, which the
# check leaves out. Its README.md is rewritten by each case.
repo="$lab/repo"
mkdir -p "$repo/docs" "$repo/img" "$repo/templates" || exit 2
git init -q "$repo" || exit 2
cat > "$repo/docs/guide.md" <<'EOF'
# The guide

## 🛠️ Install

## Section two

## Notes

## Notes

<a id="custom-spot"></a>

```
## Not a heading, inside a fence
```
EOF
printf 'png' > "$repo/img/team.png"
echo "MIT" > "$repo/LICENSE"
echo "[resolves once copied](../nowhere.md)" > "$repo/templates/skeleton.md"

# `check <case> <expected: pass, or the line it must print> <README.md's content>` runs the check
# in the scratch repository, with that README.md tracked, and compares its exit and output.
check() {
  printf '%s\n' "$3" > "$repo/README.md"
  git -C "$repo" add -A >/dev/null
  local out code
  out="$(cd "$repo" && "$links" </dev/null 2>&1)"
  code=$?
  if [ "$2" = pass ]; then
    if [ "$code" -eq 0 ] && [ -z "$out" ]; then pass "$1: passes"; else fail "$1: exit $code, said: $out"; fi
  elif [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -qxF -- "$2"; then
    pass "$1: fails, saying: $2"
  else
    fail "$1: exit $code, expected '$2', said: $out"
  fi
}

# 1. Every kind of link, whole, passes; URLs are left alone; templates/ is not checked.
check "Markdown links and images, HTML src and href, anchors and URLs, all whole" pass '# Readme
[guide](docs/guide.md) and ![team](img/team.png), <img src="img/team.png" alt="team">
<a href="LICENSE">licence</a>, <a href='"'"'docs/guide.md'"'"'>single quotes</a>
[install](docs/guide.md#️-install), [again](docs/guide.md#notes-1), [spot](docs/guide.md#custom-spot)
<a href="#readme">top</a>, [web](https://example.com/x), <img src="https://example.com/b.svg">
[mail](mailto:a@example.com), [line](LICENSE#L1)'

# 2. Each broken link fails on its own, naming the file and the target.
check "a broken Markdown link" "README.md: no such file: docs/missing.md" '[x](docs/missing.md)'
check "a broken Markdown image" "README.md: no such file: img/missing.png" '![x](img/missing.png)'
check "a broken HTML image" "README.md: no such file: img/teamX.png" '<img src="img/teamX.png" alt="x">'
check "a broken HTML link" "README.md: no such file: NOTICE" '<a href="NOTICE">notice</a>'
check "a broken anchor in the same file" "README.md: no heading or id #-faq in README.md" '# Readme
[faq](#-faq)'
check "a broken HTML anchor in the same file" "README.md: no heading or id #built-by-its-own-squad in README.md" '## 🏗️ Built by its own squad
<a href="#built-by-its-own-squad">the badge</a>'
check "a broken anchor in another file" "README.md: no heading or id #section-three in docs/guide.md" '[x](docs/guide.md#section-three)'
check "a heading inside a code fence is no anchor" "README.md: no heading or id #not-a-heading-inside-a-fence in docs/guide.md" \
  '[x](docs/guide.md#not-a-heading-inside-a-fence)'
check "a third Notes is not there" "README.md: no heading or id #notes-2 in docs/guide.md" '[x](docs/guide.md#notes-2)'

# 3. GitHub's ids: an emoji goes and its variation selector stays, so the anchor without it fails
#    and the one with it passes; a repeated heading gets -1.
check "an emoji heading's id keeps its variation selector" pass '## 🏗️ Built by its own squad
<a href="#️-built-by-its-own-squad">the badge</a>'
check "a repeated heading's second id ends in -1" pass '## Notes
## Notes
[second](#notes-1)'

# 4. Several broken links are all reported, not only the first.
printf '%s\n' '[a](a.md) [b](b.md)' > "$repo/README.md"
git -C "$repo" add -A >/dev/null
out="$(cd "$repo" && "$links" </dev/null 2>&1)"
if [ "$(printf '%s\n' "$out" | grep -c 'no such file')" -eq 2 ]; then
  pass "every broken link is reported"
else
  fail "two broken links: said: $out"
fi

exit "$status"
