#!/usr/bin/env bash
# Measure how much of the squad's scripts this repository's tests run (agent-squad #180), in CI.
# Each scripts/check-*.sh runs under kcov, which follows the bash scripts it starts and records the
# lines each one ran. The tests also run copies of the scripts, from an installed playbook or a
# tag's tarball in a temporary directory: a copy counts for the repository's script of the same
# name when kcov found exactly the same lines to measure in both, which a different script of that
# name (the pre-push shim, a stub installer) does not have.
#
# A statement written over several lines (a quoted jq or awk program, a $( ), lines ended by \ or
# |, a heredoc) counts as one line, run when kcov recorded any of its lines: kcov measures each of
# them but records a run statement on one only, the first or the last, and some on none (an
# assignment from a $( ) whose one command spans lines). Such a statement that kcov recorded
# nowhere is left out, and the summary says how many were. An empty case branch, which kcov can
# never record, counts only if it ran.
#
# Usage: ci-coverage.sh <output directory>
# It writes there summary.md, which CI adds to the job's summary: the total, one line per script,
# thinnest first, and the lines no test ran in each. Also report/, kcov's HTML report of every test
# merged into one, and runs/, each test's own report and output. No figure fails it, and a test
# that fails under kcov is named in the summary.
# Exit: 0 measured; 1 kcov is missing or recorded nothing.
set -u
out="${1:?usage: ci-coverage.sh <output directory>}"
command -v kcov >/dev/null 2>&1 || { echo "ci-coverage: kcov is not installed" >&2; exit 1; }
root="$(git rev-parse --show-toplevel)" || exit 1
cd "$root" || exit 1
mkdir -p "$out/runs" || exit 1
out="$(cd "$out" && pwd -P)"

# The scripts measured: what the playbook runs, and the one-line installer.
measured=(scripts/squad-*.sh .githooks/pre-push install.sh)

# 1. Each test under kcov, which keeps the bash files whose path contains /<name> of a measured
#    script: the scripts, their copies, and other files of those names, which step 2 tells apart.
patterns="$(printf '/%s,' "${measured[@]##*/}")"
failed=()
for test in scripts/check-*.sh; do
  name="$(basename "$test" .sh)"
  kcov --include-pattern="${patterns%,}" "$out/runs/$name" "$test" \
    >"$out/runs/$name.log" 2>&1 </dev/null || failed+=("$name")
done
# kcov writes a codecov.json per script it ran and, for some tests, a merged one too: reading
# every one is safe, since a line counts as run when any record says so.
recorded=()
while IFS= read -r file; do recorded+=("$file"); done < <(find "$out/runs" -name codecov.json)
[ ${#recorded[@]} -gt 0 ] || { echo "ci-coverage: kcov recorded nothing in $out/runs" >&2; exit 1; }

# 2. Per script, across every test and every copy with the same lines: the lines kcov measures,
#    and those that ran at least once. kcov writes a line's hits as a number, or as "hits/total".
#    It names each file by its path past the part all the run's files share, which it gives as the
#    <source> of the cobertura.xml beside each record: "/" when a test ran files from both the
#    repository and a temporary directory, the scripts' directory when it ran only those.
# `with_source <codecov.json>` prints the record with that common part.
with_source() {
  local source
  source="$(sed -n 's|.*<source>\(.*\)</source>.*|\1|p' "$(dirname "$1")/cobertura.xml" 2>/dev/null | head -n 1)"
  jq -c --arg source "$source" '{source: $source, coverage}' "$1"
}
# `continued <script>` prints, one per line, "c <n>" for each line after which the statement goes
# on (inside a quote or a $( ), before a heredoc's end, after a trailing \, | or &&), and
# "e <n>" for each empty case branch.
continued() {
  perl - "$1" <<'PERL'
use strict; use warnings;
my (@stack, @pending, $heredoc);
while (my $line = <>) {
  chomp $line;
  if ($heredoc) {
    my ($term, $strip) = @$heredoc;
    my $text = $strip ? ($line =~ s/^\t+//r) : $line;
    if ($text eq $term) { $heredoc = shift @pending; } else { print "c $.\n"; }
    next;
  }
  my @c = split //, $line;
  my $last = '';
  for (my $i = 0; $i < @c; $i++) {
    my $ch = $c[$i];
    my $ctx = @stack ? $stack[-1] : 'T';
    if ($ctx eq 'S') { pop @stack if $ch eq "'"; next; }
    if ($ch eq '\\') { $last = '\\' if $i == $#c; $i++; next; }
    if ($ctx eq 'D') {
      if ($ch eq '"') { pop @stack; }
      elsif ($ch eq '$' && ($c[$i + 1] // '') eq '(') { push @stack, 'C'; $i++; }
      next;
    }
    last if $ch eq '#' && ($i == 0 || $c[$i - 1] =~ /[\s;(]/);
    if ($ch eq "'") { push @stack, 'S'; }
    elsif ($ch eq '"') { push @stack, 'D'; }
    elsif ($ch eq '$' && ($c[$i + 1] // '') eq '(') { push @stack, 'C'; $i++; }
    elsif ($ctx eq 'C' && $ch eq '(') { push @stack, 'C'; }
    elsif ($ctx eq 'C' && $ch eq ')') { pop @stack; }
    elsif ($ch eq '<' && join('', @c[$i .. $#c]) =~ /^<<(-?)\s*(['"]?)(\w+)\2/) {
      push @pending, [$3, $1 eq '-'];
      $i += length($&) - 1;
    }
  }
  (my $code = $line) =~ s/\s+$//;
  my $continues = @stack || $last eq '\\' || (!@stack && $code =~ /(\||&&)$/ && $code !~ /^\s*#/);
  my $empty_branch = $code =~ /^\s*[^\s#][^#]*\)\s*;;$/ && $code !~ /\)\s*\S.*;;$/;
  print "c $.\n" if $continues;
  print "e $.\n" if $empty_branch && !$continues;
  $heredoc = shift @pending if @pending;
}
PERL
}
shape="$(for script in "${measured[@]}"; do
  continued "$script" | jq -Rs --arg s "$script" '
    split("\n") | map(select(. != "") | split(" ")) as $marks
    | {($s): {continued: [$marks[] | select(.[0] == "c") | .[1] | tonumber],
              empty: [$marks[] | select(.[0] == "e") | .[1] | tonumber]}}'
done | jq -s 'add')"
for record in "${recorded[@]}"; do with_source "$record"; done \
  | jq -s -r --arg root "$root" --arg failed "${failed[*]}" --argjson shape "$shape" '
  def hits: if type == "number" then . else tostring | split("/")[0] | tonumber end;
  def basename: split("/") | last;
  def pct($r; $m): if $m == 0 then "not run" else "\($r * 1000 / $m | round / 10) %" end;
  # path -> {line: ran?}, every test merged.
  (map(.source as $source | .coverage | to_entries[] | .key |= $source + .) | group_by(.key)
   | map({key: .[0].key, value: (map(.value | with_entries(.value |= (hits > 0))) | reduce .[] as $m ({};
       reduce ($m | to_entries[]) as $l (.; .[$l.key] = ((.[$l.key] // false) or $l.value))))})
   | from_entries) as $files
  | [$ARGS.positional[] as $script | ($root + "/" + $script) as $path
     | if $files[$path] == null then {script: $script, measured: 0, ran: 0}
       else ($files[$path] | keys) as $all
         | [$files | to_entries[] | select((.key | basename) == ($script | basename) and (.value | keys) == $all)]
           as $copies
         | [$all[] | . as $l | select(any($copies[]; .value[$l])) | tonumber] as $hit
         | $shape[$script].continued as $continued | $shape[$script].empty as $empty
         # A line belongs to the statement that starts at the first line of its run of continued
         # lines, and the statement ran when any of its lines did. An empty case branch counts
         # only if it ran.
         | [$all[] | tonumber as $l
            | select((any($empty[]; . == $l) | not) or any($hit[]; . == $l))
            | {line: $l, start: ($l | until((. - 1) as $p | any($continued[]; . == $p) | not; . - 1))}]
         | group_by(.start)
         | map({start: .[0].start, ran: any(.[]; .line as $l | any($hit[]; . == $l)),
                multi: any(.[]; .line as $l | any($continued[]; . == $l))})
         | [.[] | select(.ran or (.multi | not))] as $statements
         | {script: $script, measured: ($statements | length), copies: (($copies | length) - 1),
            ran: ([$statements[] | select(.ran)] | length), left_out: (length - ($statements | length)),
            unrun: [$statements[] | select(.ran | not) | .start]}
       end]
  | sort_by(if .measured == 0 then -1 else .ran / .measured end) as $rows
  | ($rows | map(.ran) | add) as $ran | ($rows | map(.measured) | add) as $all
  | ($rows | map(.left_out // 0) | add) as $left_out
  | "## Test coverage of the scripts",
  "",
  "The lines of each script that `scripts/check-*.sh` ran, measured with kcov. A copy that a test runs from a temporary directory counts for the script it copies, and a statement written over several lines counts as one line. \(if $left_out == 1 then "kcov recorded 1 such statement on none of its lines; whether it ran is unknown, so it is left out." else "kcov recorded \($left_out) such statements on none of their lines; whether they ran is unknown, so they are left out." end)",
  "",
  "| Script | Lines run | Lines measured | Coverage |",
  "|---|--:|--:|--:|",
  "| **Total** | **\($ran)** | **\($all)** | **\(pct($ran; $all))** |",
  ($rows[] | "| `\(.script)`\(if (.copies // 0) > 0 then " (and \(.copies) cop\(if .copies == 1 then "y" else "ies" end))" else "" end) | \(.ran) | \(.measured) | \(pct(.ran; .measured)) |"),
  (if $failed == "" then empty else "", "Tests that failed under kcov, so their figures may be short: `\($failed)`." end),
  "",
  "<details><summary>The lines no test ran</summary>",
  "",
  ($rows[] | select((.unrun // []) != []) | "- `\(.script)`: \(.unrun | map(tostring) | join(", "))"),
  "",
  "</details>"
' --args "${measured[@]}" >"$out/summary.md" || exit 1

# 3. kcov's own report, every test merged into one.
kcov --merge "$out/report" "$out"/runs/*/ >/dev/null 2>&1 || echo "ci-coverage: kcov could not merge the reports" >&2
cat "$out/summary.md"
