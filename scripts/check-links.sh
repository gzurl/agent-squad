#!/usr/bin/env bash
# Check that every relative link in the repository's Markdown resolves (agent-squad #176):
# - the targets of Markdown links and images, [text](target) and ![alt](target), and of the src
#   and href attributes of HTML tags, are files that exist;
# - an anchor, #id alone or after a Markdown file's path, names one of that file's headings or an
#   id or name attribute of one of its HTML tags.
# URLs, and anchors into files that are not Markdown (LICENSE#L1), are not checked. templates/ holds
# skeletons whose links resolve once copied into a project, and is left out.
#
# A heading's id is the one GitHub gives it: its text, lowercased in every alphabet, without every
# character that is not a letter, a mark, a number, an underscore, a space or a hyphen, spaces made
# hyphens; a repeated id gets -1, -2 and so on. An emoji is dropped, and the variation selector
# that often follows it is a mark and stays: "## 🛠️ Install" is #️-install, not #-install. Only
# ATX headings that start at the line's first column are read (# to ######, then a space or a
# tab); setext headings, underlined with = or -, and headings inside fenced code blocks are not.
# jq lowercases ASCII only, so perl does it.
set -u
root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root" || exit 2

# `anchors <file>` prints the anchors a Markdown file defines, one per line. The awk patterns spell
# out their repetitions, since mawk, Ubuntu's awk, may not know {m,n}.
anchors() {
  awk '/^ ? ? ?(```|~~~)/ { fenced = !fenced; next }
    !fenced && /^(#|##|###|####|#####|######)[ \t]/' "$1" \
    | perl -CS -pe '$_ = lc' \
    | jq -nRr 'reduce (inputs
        | sub("^#+[ \t]+"; "") | sub("[ \t]+#*[ \t]*$"; "")
        | gsub("\\[(?<text>[^]]*)\\]\\([^)]*\\)"; "\(.text)")
        | gsub("[^\\p{L}\\p{M}\\p{N}\\p{Pc} -]"; "") | gsub(" "; "-")) as $id
        ({seen: {}, ids: []};
          (.seen[$id] // 0) as $n
          | .ids += [if $n == 0 then $id else "\($id)-\($n)" end] | .seen[$id] = $n + 1)
      | .ids[]'
  grep -oE "(id|name)=[\"'][^\"']+[\"']" "$1" | sed -E "s/^(id|name)=[\"']//; s/[\"']$//"
}

# `targets <file>` prints the targets of a Markdown file's links and images, Markdown and HTML.
targets() {
  grep -o '\](\([^)]*\))' "$1" | sed 's/^](//; s/)$//; s/ ".*"$//'
  grep -oE "(src|href)=(\"[^\"]*\"|'[^']*')" "$1" | sed -E "s/^(src|href)=.//; s/.$//"
}

# `broken <file> <target>` prints why a target of the file does not resolve, or nothing.
broken() {
  local file="$1" target="$2" path dest anchor ids
  path="${target%%#*}"
  case "$target" in *'#'*) anchor="${target#*#}" ;; *) anchor="" ;; esac
  if [ -n "$path" ]; then
    case "$path" in
      /*) dest="${path#/}" ;;
      *) dest="$(dirname "$file")/$path"; dest="${dest#./}" ;;
    esac
    [ -e "$dest" ] || { echo "$file: no such file: $target"; return; }
  else
    dest="$file"
  fi
  case "$dest" in *.md|*.MD|*.markdown) ;; *) return ;; esac
  [ -n "$anchor" ] || return
  # The anchors are read whole before grep looks at them: grep -q in a pipe stops reading at the
  # first match, and GNU sed, upstream, then complains of a broken pipe.
  ids="$(anchors "$dest")"
  grep -qxF -- "$anchor" <<<"$ids" || echo "$file: no heading or id #$anchor in $dest"
}

found=0
while IFS= read -r file; do
  while IFS= read -r target; do
    # A URL, of any scheme, is not a file of the repository.
    [[ -z "$target" || "$target" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]] && continue
    reason="$(broken "$file" "$target")"
    [ -z "$reason" ] || { echo "$reason"; found=1; }
  done < <(targets "$file")
done < <(git ls-files '*.md' | grep -v '^templates/')
exit "$found"
