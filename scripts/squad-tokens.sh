#!/usr/bin/env bash
# Token usage per agent, read from the Claude Code transcripts on this machine (agent-squad #119).
# An agent is a session's name, such as CTO:agent-squad: its role is the side of the colon that
# reads CTO, DEV or QA, and its project the other side. A subagent counts for the session that
# started it. Each model response counts once, by its message id: a response is written once per
# content block, and a forked session copies the responses of the one it came from.
#
# By default it reports the project it runs from: the sessions launched from its main checkout,
# whatever their names. --all reports every project on the machine, one block per project, and the
# sessions whose names carry no role as "other sessions"; --project <name> reports that block only.
#
# Every run merges what the transcripts hold into .agent-squad/tokens.tsv of the main checkout,
# which git ignores, so that the history outlives Claude Code's cleanup of old transcripts, and
# the report reads that history. The transcripts are only read, and nothing leaves the machine.
# Days are UTC days, the transcripts' own; --since takes a day, or Nd for the last N days, today
# included.
#
# Usage: squad-tokens.sh [--all | --project <name>] [--since <YYYY-MM-DD | Nd>] [--by-day] [--tsv]
# Exit: 0 reported; 1 a transcript or the history could not be read, which is how a change in
#       their format shows (nothing is counted as zero); 2 bad usage, or not run from a checkout
#       of a project the squad is installed in.
set -euo pipefail

usage() { sed -n 's/^# Usage: //p' "$0" | sed 's/^/usage: /' >&2; exit 2; }
die() { echo "squad-tokens: $*" >&2; exit 1; }

# The options.
scope=here project="" since="" by_day=false tsv=false
while [ $# -gt 0 ]; do
  case "$1" in
    --all) scope=all ;;
    --project) [ $# -ge 2 ] || usage; [ -n "$2" ] || usage; scope=all project="$2"; shift ;;
    --since) [ $# -ge 2 ] || usage; since="$2"; shift
      if [[ "$since" =~ ^([1-9][0-9]*)d$ ]]; then
        since="$(jq -nr --argjson n "${BASH_REMATCH[1]}" 'now - ($n - 1) * 86400 | strftime("%Y-%m-%d")')"
      fi
      [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage ;;
    --by-day) by_day=true ;;
    --tsv) tsv=true ;;
    *) usage ;;
  esac
  shift
done

# The main checkout, reached through the git directory every worktree shares, and its history.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || { echo "squad-tokens: run it from a checkout of a project the squad is installed in" >&2; exit 2; }
root="$(cd "$common/.." && pwd -P)"
[ -d "$root/.agent-squad" ] \
  || { echo "squad-tokens: $root has no .agent-squad/: the squad is not installed there" >&2; exit 2; }
history="$root/.agent-squad/tokens.tsv"
header=$'day\tdir\tsession\tagent\tmodel\tresponses\tinput\tcache_write\tcache_read\toutput'

# Claude Code keeps a session's transcript in a directory named after the directory it was
# launched from, every character other than a letter or a digit replaced by "-".
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
here="${root//[^A-Za-z0-9]/-}"

work="$(mktemp -d)"
trap 'rm -rf "$work" "$history.$$"' EXIT

# 1. Each transcript gives one record: its directory, its session, the time of its last entry, the
#    session's latest name, and each response it holds, the most complete record of each when a
#    response is written several times. Each line is parsed on its own, so that a broken line
#    cannot run into the next; one that is not JSON, or an entry that lacks a field the script
#    needs, stops it.
# shellcheck disable=SC2016 # a jq program: its $names are jq's
read_transcript='
def lacks:
  if .message.id | type != "string" then "message.id"
  elif .message.model | type != "string" then "message.model"
  elif (.timestamp | type != "string") or (.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$") | not)
    then "a UTC timestamp"
  elif .message.usage | type != "object" then "message.usage"
  else first(("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens") as $k
             | select(.message.usage[$k] | type != "number") | "message.usage.\($k)") // null
  end;
def size: [.o, .i + .cw + .cr];
reduce (inputs | select(length > 0) | try fromjson catch error("a line that is not JSON")) as $e
  ({last: "", title: null, responses: {}};
  if ($e.timestamp | type) == "string" and $e.timestamp > .last then .last = $e.timestamp else . end
  | if $e.type == "custom-title" then
      if ($e.customTitle | type) == "string" then .title = $e.customTitle
      else error("a custom-title entry without customTitle") end
    elif $e.type == "assistant" and $e.message.model != "<synthetic>" then
      ($e | lacks) as $missing
      | if $missing then error("a response without \($missing)") else
          {id: $e.message.id, model: $e.message.model, day: $e.timestamp[0:10],
           i: $e.message.usage.input_tokens, cw: $e.message.usage.cache_creation_input_tokens,
           cr: $e.message.usage.cache_read_input_tokens, o: $e.message.usage.output_tokens} as $r
          | .responses[$r.id] |= (if . == null or ($r | size) > (. | size) then $r else . end)
        end
    else . end)
| {dir: $dir, session: $session, file: $file, last, title, responses: [.responses[]]}'

shopt -s nullglob
transcripts=("$projects"/*/*.jsonl "$projects"/*/*/subagents/*.jsonl)
[ ${#transcripts[@]} -gt 0 ] || echo "squad-tokens: no Claude Code transcripts in $projects" >&2
for f in "${transcripts[@]}"; do
  rel="${f#"$projects"/}"
  dir="${rel%%/*}"
  case "$rel" in
    */subagents/*) session="${rel#*/}"; session="${session%%/*}" ;;
    *) session="$(basename "$f" .jsonl)" ;;
  esac
  # A session appends to its transcript while this runs: a last line with no newline yet is
  # still being written, and is left for the next run.
  if [ -n "$(tail -c 1 "$f")" ]; then sed '$d' "$f"; else cat "$f"; fi \
    | jq -nRc --arg dir "$dir" --arg session "$session" --arg file "$rel" "$read_transcript" \
      >>"$work/transcripts" 2>"$work/error" \
    || die "cannot read $f: $(sed -e 's/^jq: error (at <stdin>:\([0-9]*\)): /line \1: /' "$work/error" | head -1)"
done
touch "$work/transcripts"

# 2. Per day, session, agent and model, the transcripts' totals. A response that several
#    transcripts hold counts once: its most complete record, and among equal ones the record of
#    the transcript whose last entry is latest, which Claude Code keeps longest.
jq -nc '
[inputs] as $files
| ($files | map(select(.file | test("/subagents/") | not) | {key: .session, value: .title}) | from_entries) as $titles
| [$files[] | {dir, session, file, last} as $f | .responses[] | . + $f]
| group_by(.id)
| map(sort_by([.o, .i + .cw + .cr, .last, .file]) | last)
| map(.agent = (($titles[.session] // "(untitled)") | gsub("[\\t\\r\\n]"; " ")))
| group_by([.day, .dir, .session, .agent, .model])[]
| {day: .[0].day, dir: .[0].dir, session: .[0].session, agent: .[0].agent, model: .[0].model,
   responses: length, input: (map(.i) | add), cache_write: (map(.cw) | add),
   cache_read: (map(.cr) | add), output: (map(.o) | add)}' "$work/transcripts" >"$work/fresh"

# 3. The history kept so far. A file this script did not write stops it rather than be overwritten.
if [ -f "$history" ]; then
  [ "$(head -n 1 "$history")" = "$header" ] || die "$history does not start with the header this script writes"
  tail -n +2 "$history" | jq -Rc '
    split("\t") as $c
    | if ($c | length) == 10 and ($c[5:] | all(test("^[0-9]+$"))) then
        {day: $c[0], dir: $c[1], session: $c[2], agent: $c[3], model: $c[4],
         responses: ($c[5] | tonumber), input: ($c[6] | tonumber), cache_write: ($c[7] | tonumber),
         cache_read: ($c[8] | tonumber), output: ($c[9] | tonumber)}
      else error("a row that does not read day, dir, session, agent, model and five counts") end' \
    >"$work/stored" 2>"$work/error" \
    || die "cannot read $history: $(sed -e 's/^jq: error (at <stdin>:\([0-9]*\)): /row \1: /' "$work/error" | head -1)"
else
  : >"$work/stored"
fi

# 4. The merge, per day and session: the transcripts' rows replace the stored ones unless the
#    stored ones count more responses, which means some of that session's transcripts are gone.
#    A session no longer on the machine keeps its stored rows; a renamed one moves its whole day.
jq -nr --slurpfile stored "$work/stored" --slurpfile fresh "$work/fresh" --arg header "$header" '
def by_day_session: group_by([.day, .session]) | map({key: "\(.[0].day) \(.[0].session)", value: .}) | from_entries;
def count: map(.responses) | add // 0;
($stored | by_day_session) as $s | ($fresh | by_day_session) as $f
| $header,
  ([($s + $f | keys[]) as $k | if ($f[$k] // [] | count) >= ($s[$k] // [] | count) then $f[$k][] else $s[$k][] end]
   | sort_by([.day, .dir, .session, .agent, .model])[]
   | [.day, .dir, .session, .agent, .model, .responses, .input, .cache_write, .cache_read, .output] | @tsv)' \
  >"$history.$$"
mv "$history.$$" "$history"

# 5. The report, from the merged history: one block per project, its agents in the order CTO, DEV,
#    QA and then the sessions without a role, and a subtotal; then the subtotals per role, the
#    other sessions and the total. --by-day repeats it for each day; --tsv prints one row per agent.
tail -n +2 "$history" | jq -Rnr --arg scope "$scope" --arg here "$here" --arg name "$(basename "$root")" \
  --arg project "$project" --arg since "$since" --argjson by_day "$by_day" --argjson tsv "$tsv" '
def parse_name:
  first(capture("^(?<role>CTO|DEV|QA):(?<project>.+)$"), capture("^(?<project>.+):(?<role>CTO|DEV|QA)$"),
        {role: null, project: null});
def rank: {"CTO": 0, "DEV": 1, "QA": 2}[.role // ""] // 3;
def total($label; $kind):
  {kind: $kind, label: $label, responses: (map(.responses) | add // 0), input: (map(.input) | add // 0),
   cache_write: (map(.cache_write) | add // 0), cache_read: (map(.cache_read) | add // 0),
   output: (map(.output) | add // 0), models: (map(.models[]) | unique)};
def agents:
  group_by(.agent) | map(total(.[0].agent; "row") + {project: .[0].project, role: .[0].role});
def text: {kind: "text", label: .};
def report:
  (map(select(.project != null)) | group_by(.project)) as $blocks
  | (map(select(.project == null))) as $others
  | [($blocks[] | sort_by([rank, .label]) as $a
       | {kind: "head", label: $a[0].project}, $a[], ($a | total("subtotal"; "sub"))),
     (if $blocks != [] then {kind: "head", label: "By role"},
        (map(select(.role != null)) | group_by(.role) | sort_by(.[0] | rank)[] | total(.[0].role; "row"))
      else empty end),
     (if $others != [] then {kind: "head", label: "Other sessions"},
        ($others | sort_by(.label)[]), ($others | total("subtotal"; "sub")) else empty end),
     total("Total"; "total")];
[inputs | split("\t")
 | {day: .[0], dir: .[1], agent: .[3], model: .[4], responses: (.[5] | tonumber), input: (.[6] | tonumber),
    cache_write: (.[7] | tonumber), cache_read: (.[8] | tonumber), output: (.[9] | tonumber)}
 | select(.day >= $since)
 | select($scope == "all" or .dir == $here)
 | (.agent | parse_name) as $n
 | .role = $n.role
 | .project = (if $scope == "here" then $name else $n.project end)
 | select($project == "" or .project == $project)
 | .models = [.model]] as $rows
| if $rows == [] then
    "No token usage recorded" + (if $project != "" then " for project \($project)"
      elif $scope == "here" then " for \($name) (Claude Code directory \($here))" else "" end)
      + (if $since != "" then " since \($since)" else "" end) + "."
    | if $tsv then . else text | [.kind, .label] | @tsv end
  elif $tsv then
    ((if $by_day then ["day"] else [] end) + ["project", "role", "agent", "responses", "input",
      "cache_write", "cache_read", "output", "models"] | @tsv),
    ($rows | (if $by_day then group_by(.day) else [.] end)[] | (.[0].day) as $day
     | agents | (map(select(.project != null)) | sort_by([.project, rank, .label]))
                + (map(select(.project == null)) | sort_by(.label))
     | .[] | (if $by_day then [$day] else [] end)
       + [.project // "", .role // "", .label, .responses, .input, .cache_write, .cache_read, .output,
          (.models | join(","))] | @tsv)
  else
    ("Token usage " + (if $project != "" then "of project \($project)" elif $scope == "here" then "of \($name)"
       else "of every project on this machine" end)
       + ", \($rows | map(.day) | min) → \($rows | map(.day) | max) (UTC days)." | text),
    ($rows | (if $by_day then group_by(.day) else [.] end)[]
     | ("" | text), (if $by_day then "== \(.[0].day) ==" | text else empty end), {kind: "columns"},
       (agents | report[]))
    | [.kind, .label, .responses, ((.input // 0) + (.cache_write // 0) + (.cache_read // 0)), .cache_read,
       .output, ((.models // []) | join(", "))] | @tsv
  end' >"$work/report"

# The plain report is aligned here, its first column as wide as its longest label; TSV passes as is.
if $tsv; then
  cat "$work/report"
else
  awk -F'\t' '
    { kind[NR] = $1; label[NR] = ($1 == "row" || $1 == "sub" ? "  " : "") $2
      for (c = 3; c <= 7; c++) cell[NR, c] = $c
      if ($1 != "text" && length(label[NR]) > width) width = length(label[NR]) }
    END {
      if (width < 5) width = 5
      fmt = "%-" width "s  %9s  %10s  %6s  %9s  %s\n"
      for (r = 1; r <= NR; r++) {
        if (kind[r] == "text" || kind[r] == "head") { print label[r]; continue }
        if (kind[r] == "columns") { printf fmt, "Agent", "Responses", "Input", "Cached", "Output", "Models"; continue }
        input = cell[r, 4]
        cached = input > 0 ? sprintf("%d %%", int(cell[r, 5] * 100 / input)) : "-"
        printf fmt, label[r], cell[r, 3], sprintf("%.1f M", input / 1e6), cached, sprintf("%.2f M", cell[r, 6] / 1e6), cell[r, 7]
      }
    }' "$work/report"
fi
