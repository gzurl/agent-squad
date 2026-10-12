#!/usr/bin/env bash
# Publish a release as a GitHub Release with its package attached (agent-squad #295), so that GitHub
# counts the package's downloads, one number per version, and nothing else: no telemetry, and nothing
# about who downloads. Run by agent-squad's CTO, once the release's tag is pushed (AGENTS.md,
# Releases). The package, agent-squad-vN.tar.gz, is the tag's tree as `git archive` writes it, the
# tree GitHub's own tarball of the tag holds. It is the Release's one asset, so that each install,
# which downloads it alone, counts once (agent-squad #330): GitHub computes its SHA-256 and keeps
# it as the asset's digest, which the installer checks before it extracts anything, and which this
# script checks against its own once the asset is up. The Release's title is the tag's message, and
# its notes are the version's CHANGELOG entry, read from the tag.
#
# Usage: release.sh [--dry-run] vN    publish vN's Release
#        release.sh --downloads         print each Release's downloads of its package
# --dry-run builds the package and the notes in a directory it names, says what it would create,
# and creates nothing.
# Exit: 0 done; 1 refused, saying why (the tag is not on origin, or already has a Release, or its
# CHANGELOG has no entry for it), gh failed, or GitHub's digest of the package is not its SHA-256;
# 2 bad usage.
set -u
repo="gzurl/agent-squad"
usage="usage: release.sh [--dry-run] vN | release.sh --downloads"

# `refuse <reason>` stops before anything is created.
refuse() { echo "release: $1" >&2; exit 1; }
# `sha256_of <file>` prints the file's SHA-256, with whichever tool the machine has.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# The downloads: each Release, newest first, with how many times its package was downloaded.
if [ "${1:-}" = --downloads ]; then
  [ $# -eq 1 ] || { echo "$usage" >&2; exit 2; }
  # shellcheck disable=SC2016 # a jq program, whose $tag is jq's
  gh api --paginate "repos/$repo/releases" \
    --jq '.[] | .tag_name as $tag | "\($tag) \([.assets[] | select(.name == "agent-squad-\($tag).tar.gz") | .download_count] | add // 0)"' \
    </dev/null || refuse "gh cannot list the Releases of $repo"
  exit 0
fi

dry_run=false
[ "${1:-}" != --dry-run ] || { dry_run=true; shift; }
if [ $# -ne 1 ] || ! [[ "$1" =~ ^v[0-9]+$ ]]; then echo "$usage" >&2; exit 2; fi
tag="$1"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "run it from a checkout of $repo"

# 1. The tag: annotated, here and on origin as the same object, and with no Release yet.
local_tag="$(git -C "$root" rev-parse -q --verify "refs/tags/$tag" 2>/dev/null)"
if [ -z "$local_tag" ] || [ "$(git -C "$root" cat-file -t "$local_tag")" != tag ]; then
  refuse "$tag is not an annotated tag in this checkout; fetch the tags, or tag the release first"
fi
remote_tag="$(git -C "$root" ls-remote origin "refs/tags/$tag" </dev/null 2>/dev/null | cut -f1)"
[ "$remote_tag" = "$local_tag" ] \
  || refuse "origin does not have $tag as this checkout has it; push the tag first"
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1 </dev/null; then
  refuse "$tag already has a Release"
fi

# 2. The notes: the version's CHANGELOG entry, from its heading to the next one, as the tag has it.
notes="$(git -C "$root" show "$tag:CHANGELOG.md" 2>/dev/null | awk -v head="## $tag " '
  index($0, head) == 1 { on = 1; next }
  on && /^## v[0-9]/ { exit }
  on { print }')"
[ -n "${notes//[[:space:]]/}" ] || refuse "CHANGELOG.md at $tag has no entry for $tag"
title="$(git -C "$root" tag -l --format='%(contents:subject)' "$tag")"

# 3. The package and the notes, built in a directory of their own.
asset="agent-squad-$tag.tar.gz"
work="${TMPDIR:-/tmp}"
work="$(mktemp -d "${work%/}/agent-squad-release.XXXXXX")" || refuse "cannot create a temporary directory"
$dry_run || trap 'rm -rf "$work"' EXIT
set -o pipefail
git -C "$root" archive --format=tar --prefix="agent-squad-$tag/" "$tag" | gzip -n > "$work/$asset" \
  || refuse "cannot build $asset from $tag"
set +o pipefail
sum="$(sha256_of "$work/$asset")"
printf '%s\n' "$notes" | sed -e '/./,$!d' > "$work/notes.md"

# 4. The Release, or what it would be.
if $dry_run; then
  echo "release: would create the Release $tag of $repo, titled \"$title\", with:"
  echo "  $asset, SHA-256 $sum, which GitHub's digest of it must then equal"
  echo "  and the notes in $work/notes.md"
  echo "release: nothing was created; the files are in $work"
  exit 0
fi
gh release create "$tag" --repo "$repo" --verify-tag --title "$title" --notes-file "$work/notes.md" \
  "$work/$asset" </dev/null || refuse "gh could not create the Release $tag"
# GitHub's digest of the package, which the installer checks it against: it must be the SHA-256.
digest="$(gh api "repos/$repo/releases/tags/$tag" \
  --jq "[.assets[] | select(.name == \"$asset\") | .digest // \"\"] | first // \"\"" </dev/null 2>/dev/null)"
if [ "$digest" != "sha256:$sum" ]; then
  refuse "created the Release $tag, but GitHub's digest of $asset is '${digest:-none}', not sha256:$sum: check the asset before anyone installs it"
fi
echo "release: created the Release $tag, with $asset, whose digest on GitHub is its SHA-256, sha256:$sum"
