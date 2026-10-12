#!/usr/bin/env bash
# Check scripts/release.sh (agent-squad #295) in a scratch repository with an origin of its own, and
# a gh that records what it is asked and answers from fixtures; nothing reaches GitHub. A tag that
# is not annotated, not on origin, or not the same object there, one that already has a Release,
# and one whose CHANGELOG has no entry are refused, and nothing is created. A dry run builds the
# package, its checksum and the notes, and creates nothing. A run creates the Release with them, and
# leaves nothing behind. --downloads prints each Release's downloads of its package.
# shellcheck disable=SC2016 # the checks' bash -c bodies take their values as arguments, unexpanded
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
release="$root/scripts/release.sh"
# This script builds a repository of its own; git's own variables, which a hook exports, would
# point every one of its commands at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-release.XXXXXX")" || exit 2
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
sha_of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

# gh, as far as release.sh is concerned. Every call goes to gh.log, one line each. `release view
# <tag>` passes when the tag is GH_RELEASED. `release create` copies the files it is given into
# created/, records its arguments in create.args, one per line, and fails when GH_CREATE_FAILS is
# set. `api --paginate repos/gzurl/agent-squad/releases --jq <filter>` runs the filter on
# releases.json, and fails when GH_API_FAILS is set.
mkdir -p "$lab/bin" "$lab/created" "$lab/tmp"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
lab="$(cd "$(dirname "$0")/.." && pwd)"
echo "$*" >> "$lab/gh.log"
case "${1:-} ${2:-}" in
  "release view") [ -n "${GH_RELEASED:-}" ] && [ "${3:-}" = "$GH_RELEASED" ] ;;
  "release create")
    [ -z "${GH_CREATE_FAILS:-}" ] || exit 1
    printf '%s\n' "$@" > "$lab/create.args"
    for arg in "$@"; do [ ! -f "$arg" ] || cp "$arg" "$lab/created/"; done ;;
  "api --paginate")
    [ -z "${GH_API_FAILS:-}" ] && [ "${3:-}" = repos/gzurl/agent-squad/releases ] && [ "${4:-}" = --jq ] || exit 1
    jq -r "$5" "$lab/releases.json" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
export PATH="$lab/bin:$PATH"

# The scratch repository: a CHANGELOG with entries for v2 and v1, a file the package leaves out by
# .gitattributes, and an origin. Tags: v2, annotated and pushed; v3, annotated but not pushed; v4,
# pushed, then made again here on another commit; v5, pushed, whose CHANGELOG has no entry for it;
# v6, a lightweight tag.
repo="$lab/repo"
git init -q -b main "$repo" && git init -q --bare -b main "$lab/origin.git" || exit 2
git -C "$repo" config user.name "Check" && git -C "$repo" config user.email check@example.com
git -C "$repo" remote add origin "$lab/origin.git"
cat > "$repo/CHANGELOG.md" <<'EOF'
# Changelog

## v2 — 2026-10-12
- **Two:** the second release.
  - With a nested line.

## v1 — 2026-10-01
- **One:** the first.
EOF
echo "kept" > "$repo/kept.txt"
echo "left out" > "$repo/left-out.txt"
echo "/left-out.txt export-ignore" > "$repo/.gitattributes"
git -C "$repo" add -A && git -C "$repo" commit -qm one || exit 2
git -C "$repo" tag -a v2 -m "Charter v2: two" && git -C "$repo" tag -a v3 -m "Charter v3: three" \
  && git -C "$repo" tag -a v4 -m "Charter v4: four" && git -C "$repo" tag -a v5 -m "Charter v5: five" \
  && git -C "$repo" tag v6 || exit 2
git -C "$repo" push -q origin main v2 v4 v5 2>/dev/null || exit 2
echo "later" >> "$repo/kept.txt" && git -C "$repo" commit -qam two || exit 2
git -C "$repo" tag -f -a v4 -m "Charter v4: four, again" >/dev/null || exit 2

# `run <command...>` runs release.sh in the scratch repository, into out and code.
run() {
  out="$(cd "$repo" && TMPDIR="$lab/tmp" "$release" "$@" 2>&1)"
  code=$?
}

# 1. Bad usage exits 2, and asks gh nothing.
for args in "" "v" "49" "--dry-run" "--dry-run v2 v3" "--downloads v2" "v2 --dry-run"; do
  rm -f "$lab/gh.log"
  # shellcheck disable=SC2086 # the arguments are split on purpose
  run $args
  check "'$args' is bad usage, exit 2" \
    bash -c '[ "$1" -eq 2 ] && [ "$2" = "usage: release.sh [--dry-run] vN | release.sh --downloads" ] && [ ! -e "$3" ]' \
    _ "$code" "$out" "$lab/gh.log"
done

# 2. What is refused: exit 1, saying why, and no Release created.
# `refused <case> <message> <tag>` runs release.sh on the tag and passes when it exits 1 saying so.
refused() {
  run "$3"
  if [ "$code" -eq 1 ] && [ "$out" = "release: $2" ] && [ ! -e "$lab/create.args" ]; then
    pass "$1: exit 1, saying so, nothing created"
  else
    fail "$1: exit $code, said: $out"
  fi
}
refused "a tag that does not exist" "v9 is not an annotated tag in this checkout; fetch the tags, or tag the release first" v9
refused "a lightweight tag" "v6 is not an annotated tag in this checkout; fetch the tags, or tag the release first" v6
refused "a tag origin does not have" "origin does not have v3 as this checkout has it; push the tag first" v3
refused "a tag origin has as another object" "origin does not have v4 as this checkout has it; push the tag first" v4
refused "a tag whose CHANGELOG has no entry for it" "CHANGELOG.md at v5 has no entry for v5" v5
GH_RELEASED=v2 refused "a tag that already has a Release" "v2 already has a Release" v2
out="$(cd "$lab" && "$release" v2 2>&1)"
code=$?
check "outside a checkout it exits 1, saying so" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "release: run it from a checkout of gzurl/agent-squad" ]' _ "$code" "$out"

# 3. A dry run: the package, its checksum and the notes, in the directory it names; no Release.
rm -f "$lab/gh.log"
run --dry-run v2
dir="$(sed -n 's/^release: nothing was created; the files are in //p' <<<"$out")"
check "a dry run exits 0, and names its directory" bash -c '[ "$1" -eq 0 ] && [ -d "$2" ]' _ "$code" "$dir"
check "and says what it would create" grep -qxF 'release: would create the Release v2 of gzurl/agent-squad, titled "Charter v2: two", with:' <<<"$out"
check "and creates no Release" bash -c '! grep -q "^release create" "$1"' _ "$lab/gh.log"
mkdir -p "$lab/unpacked" "$lab/archived"
tar -xzf "$dir/agent-squad-v2.tar.gz" -C "$lab/unpacked" 2>/dev/null
git -C "$repo" archive v2 | tar -xf - -C "$lab/archived"
check "the package holds the tag's tree under agent-squad-v2/, as git archive writes it" \
  diff -r "$lab/archived" "$lab/unpacked/agent-squad-v2"
check "which leaves out what .gitattributes marks export-ignore" [ ! -e "$lab/unpacked/agent-squad-v2/left-out.txt" ]
check "its checksum file names the package with its SHA-256" \
  bash -c '[ "$(cat "$1/agent-squad-v2.tar.gz.sha256")" = "$2  agent-squad-v2.tar.gz" ]' _ "$dir" "$(sha_of "$dir/agent-squad-v2.tar.gz")"
check "and the notes are v2's entry, without its heading or the next one" \
  bash -c '[ "$(cat "$1/notes.md")" = "$(printf -- "- **Two:** the second release.\n  - With a nested line.")" ]' _ "$dir"

# 4. A run: the Release, with the package, its checksum and the notes, and nothing left behind.
rm -f "$lab/gh.log"
run v2
check "a run exits 0, saying what it created" \
  bash -c '[ "$1" -eq 0 ] && grep -qF "release: created the Release v2, with agent-squad-v2.tar.gz (SHA-256 " <<<"$2"' _ "$code" "$out"
check "with gh release create, on the tag that must exist, titled by its message" \
  bash -c '[ "$(head -n 9 "$1" | tr "\n" " ")" = "release create v2 --repo gzurl/agent-squad --verify-tag --title Charter v2: two --notes-file " ]' \
  _ "$lab/create.args"
check "and the same package a dry run builds, byte for byte" cmp -s "$dir/agent-squad-v2.tar.gz" "$lab/created/agent-squad-v2.tar.gz"
check "with its checksum and its notes" \
  bash -c 'cmp -s "$1/agent-squad-v2.tar.gz.sha256" "$2/agent-squad-v2.tar.gz.sha256" && cmp -s "$1/notes.md" "$2/notes.md"' _ "$dir" "$lab/created"
rm -rf "$dir"
check "and leaves nothing in its temporary directory" [ -z "$(ls -A "$lab/tmp")" ]
rm -f "$lab/create.args"
GH_CREATE_FAILS=1 run v2
check "a Release gh cannot create exits 1, saying so" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "release: gh could not create the Release v2" ]' _ "$code" "$out"

# 5. The downloads: each Release's package, and 0 for a Release without one.
cat > "$lab/releases.json" <<'EOF'
[{"tag_name": "v51", "assets": [{"name": "agent-squad-v51.tar.gz", "download_count": 7},
                                {"name": "agent-squad-v51.tar.gz.sha256", "download_count": 3}]},
 {"tag_name": "v50", "assets": []}]
EOF
run --downloads
check "--downloads prints each Release's downloads of its package, its checksum aside" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" = "$(printf "v51 7\nv50 0")" ]' _ "$code" "$out"
GH_API_FAILS=1 run --downloads
check "and exits 1 when gh cannot list them, saying so" \
  bash -c '[ "$1" -eq 1 ] && [ "$2" = "release: gh cannot list the Releases of gzurl/agent-squad" ]' _ "$code" "$out"

exit "$status"
