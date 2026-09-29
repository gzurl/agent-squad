#!/usr/bin/env bash
# Check that install.sh installs as agent-squad #89 says: its usage; the latest release tag compared
# as numbers, or a --tag checked before any use; the chosen tag's own installer run on the project,
# its exit status passed on, and the tags it cannot install refused; the prerequisites checked
# before any download; a run piped into bash, whose installer reads nothing of the script, and a
# script cut short at any point, which does nothing; and TMPDIR left as it was, on success, on
# failure and on interruption. GitHub is replaced by a `gh` that serves tags and a fake installer:
# no network, and this script never touches the repository it is run from.
set -u

root="$(git rev-parse --show-toplevel)" || exit 2
script="$root/install.sh"
# This script builds directories of its own; git's own variables, which a hook exports, would
# point git at the repository being pushed (#19).
# shellcheck disable=SC2046 # the names are split on purpose, one variable each
unset $(git rev-parse --local-env-vars)

# The lab goes under TMPDIR, through a template: macOS's mktemp -d alone ignores TMPDIR.
lab="${TMPDIR:-/tmp}"
lab="$(mktemp -d "${lab%/}/squad-check-one-line.XXXXXX")" || exit 2
trap 'rm -rf "$lab"' EXIT
status=0

pass() { echo "  ok      $1" >&2; }
fail() { echo "  FAILED  $1" >&2; status=1; }

# GitHub, as far as install.sh is concerned. Every call is logged in $STUB_LAB/calls. STUB_TAGS
# lists the refs under refs/tags/ (default v9, v15, v16, v100 and names that are not release tags),
# STUB_AUTH=fail and STUB_REPO=fail make the login and the repository unreadable, STUB_CONTENTS=fail
# makes the installer's download fail, STUB_CONTENTS=empty makes it succeed with nothing, and
# STUB_CONTENTS=slow makes it wait. The installer it serves
# records its arguments and what it reads on stdin, prints a line, records that it got past it,
# may wait (STUB_INSTALLER_SLEEP) and exits with STUB_INSTALLER_EXIT. Like every tag's installer
# before v23, it does not ignore SIGPIPE itself.
mkdir -p "$lab/bin"
cat > "$lab/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LAB/calls"
case "$1 ${2:-}" in
  "auth status") [ "${STUB_AUTH:-}" != fail ] ;;
  "api repos/gzurl/agent-squad")
    [ "${STUB_REPO:-}" != fail ] && echo gzurl/agent-squad ;;
  "api --paginate")
    for tag in ${STUB_TAGS:-v9 v15 v16 v100 v101a vx v16-rc}; do echo "refs/tags/$tag"; done ;;
  "api -H")
    [ "${STUB_CONTENTS:-}" != fail ] || exit 1
    [ "${STUB_CONTENTS:-}" != empty ] || exit 0
    [ "${STUB_CONTENTS:-}" != slow ] || sleep 5
    cat <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LAB/installer-args"
if IFS= read -r line; then echo "read: $line"; else echo "nothing"; fi > "$STUB_LAB/installer-stdin"
echo "fake installer of $2"
echo finished > "$STUB_LAB/installer-finished"
[ -z "${STUB_INSTALLER_SLEEP:-}" ] || sleep "$STUB_INSTALLER_SLEEP"
exit "${STUB_INSTALLER_EXIT:-0}"
INSTALLER
    ;;
  *) exit 1 ;;
esac
GH
chmod +x "$lab/bin/gh"
export STUB_LAB="$lab"
project="$lab/project"
mkdir -p "$project" "$lab/tmp"
project="$(cd "$project" && pwd)"

# `run <args...>` runs install.sh from the project's directory with the stub first on PATH and
# TMPDIR in the lab, after clearing the stub's records; its stdout and stderr land in $out and $err.
run() {
  rm -f "$lab/calls" "$lab/installer-args" "$lab/installer-stdin"
  (cd "$project" && PATH="$lab/bin:$PATH" TMPDIR="$lab/tmp" "$script" "$@" \
    >"$lab/out" 2>"$lab/err" </dev/null)
  code=$?
  out="$(cat "$lab/out")" err="$(cat "$lab/err")"
}
# `installed <tag>` passes when the fake installer ran with the project and that tag.
installed() { [ "$(cat "$lab/installer-args" 2>/dev/null)" = "$project"$'\n'"$1" ]; }
# `left_in_tmp` lists what TMPDIR holds besides the test's own file; `tmp_clean` passes when that
# is nothing and the test's file is still there.
left_in_tmp() { find "$lab/tmp" -mindepth 1 -maxdepth 1 ! -name keep-me | tr '\n' ' '; }
tmp_clean() { [ -z "$(left_in_tmp)" ] && [ -f "$lab/tmp/keep-me" ]; }
echo "not install.sh's" > "$lab/tmp/keep-me"
# `refused <case> <message> <args...>` expects exit 2, the message on stderr and no installer run.
refused() {
  local name="$1" message="$2"
  shift 2
  run "$@"
  if [ "$code" -eq 2 ] && grep -qF -- "$message" <<<"$err" && [ ! -e "$lab/installer-args" ]; then
    pass "$name: refused, exit 2, saying why"
  else
    fail "$name: exit $code, stderr: $err"
  fi
}

# 1. Usage: --help prints it, naming the oldest tag installed; a bad argument gets it on stderr.
run --help
if [ "$code" -eq 0 ] && grep -qF 'usage: install.sh [--tag vN] [<project main checkout>]' <<<"$out" \
  && grep -qF 'v15 or later' <<<"$out" && [ ! -e "$lab/calls" ]; then
  pass "--help prints the usage, naming v15, and asks GitHub nothing"
else
  fail "--help: exit $code, stdout: $out"
fi
refused "an unknown option" "unknown option --bogus" --bogus
refused "two projects" "one project at a time" "$project" "$project"
refused "--tag without a value" "--tag needs a value" --tag

# 2. Without --tag, the latest release tag, compared as numbers: v100 after v16 and v9, and names
#    that are not vN ignored. A --tag that is not vN is refused before GitHub is asked anything.
run
if [ "$code" -eq 0 ] && installed v100; then
  pass "without --tag, the latest vN as a number (v100, not v9 or v16), into the current directory"
else
  fail "without --tag: exit $code, installer args: $(cat "$lab/installer-args" 2>/dev/null)"
fi
for bad in '19' 'v' 'v1;touch x' 'v1 2' '-v1' 'V19' 'v19 '; do
  refused "--tag '$bad'" "is not a release tag" --tag "$bad" "$project"
  [ ! -e "$lab/calls" ] || fail "--tag '$bad': GitHub was asked: $(cat "$lab/calls")"
done

# 3. The chosen tag's own installer runs on the project with that tag, its output shown after a
#    line that says what is happening, and its exit status is install.sh's. A tag that is not
#    there, or older than the installer, is refused before any download.
run --tag v16 "$project"
if [ "$code" -eq 0 ] && installed v16 && grep -qF 'ref=v16' "$lab/calls" \
  && [ "$(head -1 <<<"$out")" = "install.sh: installing agent-squad v16 into $project, with v16's own installer" ] \
  && [ "$(sed -n 2p <<<"$out")" = "fake installer of v16" ]; then
  pass "--tag v16 runs v16's installer on the project, after one line saying so"
else
  fail "--tag v16: exit $code, stdout: $out"
fi
#    An installation already in place does not change which installer runs: the chosen tag's, not
#    the one in the project's playbook, so that an upgrade runs the new tag's installer.
mkdir -p "$project/.agent-squad/playbook/scripts"
printf '#!/usr/bin/env bash\ntouch "%s/installed-ran"\n' "$lab" \
  > "$project/.agent-squad/playbook/scripts/squad-install.sh"
chmod +x "$project/.agent-squad/playbook/scripts/squad-install.sh"
run --tag v16 "$project"
if [ "$code" -eq 0 ] && installed v16 && [ ! -e "$lab/installed-ran" ]; then
  pass "over an installed playbook, --tag v16 runs v16's installer, not the installed one"
else
  fail "over an installed playbook: exit $code, the installed installer ran: $([ -e "$lab/installed-ran" ] && echo yes || echo no)"
fi
rm -rf "$project/.agent-squad"
for installer_exit in 1 2 7; do
  export STUB_INSTALLER_EXIT="$installer_exit"
  run --tag v16 "$project"
  unset STUB_INSTALLER_EXIT
  if [ "$code" -eq "$installer_exit" ]; then
    pass "an installer that exits $installer_exit makes install.sh exit $installer_exit"
  else
    fail "an installer that exits $installer_exit made install.sh exit $code"
  fi
done
refused "--tag v42, which upstream does not have" "has no tag v42" --tag v42 "$project"
refused "--tag v9, older than the installer" "v9 has no installer: install.sh installs v15 and later" \
  --tag v9 "$project"
grep -qF 'contents' "$lab/calls" && fail "--tag v9: the installer was downloaded anyway"
export STUB_TAGS="v8 v9 vx"
refused "no tag with an installer" "v9 has no installer" "$project"
export STUB_TAGS=" "
refused "no release tag at all" "has no release tag" "$project"
unset STUB_TAGS
for contents in fail empty; do
  export STUB_CONTENTS="$contents"
  refused "an installer download that comes back $contents" \
    "cannot fetch scripts/squad-install.sh of v16" --tag v16 "$project"
  unset STUB_CONTENTS
done

# 4. The prerequisites stop it, one line each, before anything is downloaded. A PATH of links to
#    the tools install.sh uses stands in for the machine, less the tool under test.
mkdir -p "$lab/tools"
for tool in bash env sed sort tail grep mkdir rm cat git jq tar; do
  ln -s "$(command -v "$tool")" "$lab/tools/$tool"
done
ln -s "$lab/bin/gh" "$lab/tools/gh"
# `without <tool>` runs install.sh with the tools' PATH, less that tool.
without() {
  local path="$lab/path-without-$1"
  mkdir -p "$path" && cp -P "$lab/tools/"* "$path/" && rm -f "$path/$1"
  rm -f "$lab/calls" "$lab/installer-args"
  (cd "$project" && PATH="$path" TMPDIR="$lab/tmp" bash "$script" --tag v16 >"$lab/out" 2>"$lab/err" </dev/null)
  code=$?
  err="$(cat "$lab/err")"
}
without nothing
if [ "$code" -eq 0 ] && installed v16; then
  pass "with only the tools it needs on PATH, install.sh runs"
else
  fail "with only the tools it needs on PATH: exit $code, stderr: $err"
fi
for tool in gh git jq tar; do
  without "$tool"
  if [ "$code" -eq 2 ] && [ "$err" = "install.sh: $tool is missing; install it and run this again" ] \
    && ! grep -q 'api' "$lab/calls" 2>/dev/null; then
    pass "without $tool: one line saying so, exit 2, nothing downloaded"
  else
    fail "without $tool: exit $code, stderr: $err"
  fi
done
export STUB_AUTH=fail
refused "gh not logged in" "gh is not logged in" --tag v16 "$project"
grep -q '^api' "$lab/calls" && fail "gh not logged in: GitHub was asked anyway"
unset STUB_AUTH
export STUB_REPO=fail
refused "an upstream gh cannot read" "gh cannot read gzurl/agent-squad" --tag v16 "$project"
grep -q 'matching-refs\|contents' "$lab/calls" && fail "an unreadable upstream: tags or installer asked anyway"
unset STUB_REPO

# 5. Piped into bash, as the one-line install runs it: the installer runs, and reads nothing from
#    its stdin, not even a line that follows the script in the pipe.
rm -f "$lab/calls" "$lab/installer-args" "$lab/installer-stdin"
{ cat "$script"; echo 'echo "the line after the script"'; } \
  | (cd "$project" && PATH="$lab/bin:$PATH" TMPDIR="$lab/tmp" bash -s -- --tag v16 "$project" >"$lab/out" 2>&1)
if installed v16 && [ "$(cat "$lab/installer-stdin" 2>/dev/null)" = nothing ]; then
  pass "piped through bash -s --: the installer runs with its arguments and reads nothing of the script"
else
  fail "piped: installer args: $(cat "$lab/installer-args" 2>/dev/null); it read: $(cat "$lab/installer-stdin" 2>/dev/null)"
fi
#    Cut short at the end of any line but the last, or at any character of the last line, the
#    script asks GitHub nothing and runs no installer.
size="$(wc -c < "$script" | tr -d ' ')"
last_line_start="$(( $(head -n "$(( $(wc -l < "$script") - 1 ))" "$script" | wc -c) ))"
cuts="$(LC_ALL=C awk '{ n += length($0) + 1; print n }' "$script" | sed '$d'; seq "$((last_line_start + 1))" "$((size - 2))")"
acted=""
count=0
for cut in $cuts; do
  rm -f "$lab/calls" "$lab/installer-args"
  head -c "$cut" "$script" \
    | (cd "$project" && PATH="$lab/bin:$PATH" TMPDIR="$lab/tmp" bash -s -- --tag v16 "$project" >/dev/null 2>&1)
  count=$((count + 1))
  if [ -e "$lab/calls" ] || [ -e "$lab/installer-args" ]; then acted="$acted $cut"; fi
done
if [ "$count" -gt 50 ] && [ -z "$acted" ]; then
  pass "cut short at any of $count points, the script asks GitHub nothing and installs nothing"
else
  fail "cut short, the script acted at byte(s):$acted (of $count cuts)"
fi

#    Output whose reader has gone, as when the one-line install is piped into head, stops neither
#    install.sh nor the installer it runs, which inherits the ignored SIGPIPE (#96). The output
#    goes to a FIFO whose only reader is closed before install.sh starts, so every write fails.
rm -f "$lab/calls" "$lab/installer-args" "$lab/installer-finished"
mkfifo "$lab/no-reader.fifo" || exit 2
exec 5<>"$lab/no-reader.fifo"
exec 6>"$lab/no-reader.fifo"
exec 5<&-
(cd "$project" && PATH="$lab/bin:$PATH" TMPDIR="$lab/tmp" "$script" --tag v16 "$project" >&6 2>&6 </dev/null)
code=$?
exec 6>&-
if [ "$code" -eq 0 ] && installed v16 && [ -e "$lab/installer-finished" ]; then
  pass "with no reader for its output, install.sh runs the installer through to its end, exit 0"
else
  fail "with no reader for its output: exit $code, the installer finished: $([ -e "$lab/installer-finished" ] && echo yes || echo no)"
fi

# 6. TMPDIR is left as it was: after the runs above, which succeeded and failed, and after runs
#    interrupted while the installer downloads and while it runs. Each gets its own process group,
#    which is what a Ctrl-C signals, and is interrupted at a state, not after a delay.
if tmp_clean; then
  pass "after every run above, TMPDIR holds nothing of install.sh's"
else
  fail "TMPDIR holds: $(left_in_tmp)"
fi
# `interrupted_while <what> <state file> <pattern>` runs install.sh, waits until the state file
# matches the pattern, interrupts it, and passes when it exited 130 and left TMPDIR clean.
interrupted_while() {
  local what="$1" state="$2" pattern="$3" pid tries=0
  rm -f "$lab/calls" "$lab/installer-args"
  set -m
  (cd "$project" && PATH="$lab/bin:$PATH" TMPDIR="$lab/tmp" "$script" --tag v16 "$project" \
    >/dev/null 2>&1 </dev/null) &
  pid=$!
  set +m
  until grep -qF -- "$pattern" "$state" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 1000 ] || ! kill -0 "$pid" 2>/dev/null; then
      kill -KILL -- "-$pid" 2>/dev/null
      fail "interrupted while $what: that state was never reached"
      return
    fi
    sleep 0.01
  done
  kill -INT -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  code=$?
  if [ "$code" -eq 130 ] && tmp_clean; then
    pass "interrupted while $what: exit 130, and TMPDIR holds nothing of install.sh's"
  else
    fail "interrupted while $what: exit $code, TMPDIR holds: $(left_in_tmp)"
  fi
}
export STUB_CONTENTS=slow
interrupted_while "the installer downloads" "$lab/calls" "contents"
unset STUB_CONTENTS
export STUB_INSTALLER_SLEEP=5
interrupted_while "the installer runs" "$lab/installer-args" "$project"
unset STUB_INSTALLER_SLEEP

# 7. The upstream repository is named once in install.sh, so that moving it changes one line.
named="$(grep -c 'gzurl/agent-squad' "$script")"
if [ "$named" -eq 1 ]; then
  pass "install.sh names the upstream repository on one line"
else
  fail "install.sh names gzurl/agent-squad on $named lines"
fi

exit "$status"
