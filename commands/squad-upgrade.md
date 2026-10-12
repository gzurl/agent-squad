---
description: Show what a new agent-squad release changes, ask the CEO, then install it (agent-squad)
disable-model-invocation: true
---
The CEO wants to know whether to upgrade the squad in this project. Your role is your session
name.

## If you are DEV or QA
This command is the CTO's. Tell the CEO, in one line and in the CEO's language (`AGENTS.md`,
*Language*), to type `/squad-upgrade` in the CTO's session, and do nothing else.

## If you are the CTO
Work from the main checkout. The upstream repository is the one named on the `upstream=` line of
`.agent-squad/playbook/scripts/squad-install.sh`.

1. **Where the project stands.** Read the version it runs, from the last line of
   `.agent-squad/install.log` and the first line of
   `.agent-squad/playbook/scripts/squad-install.sh --check .`. Then read the latest release, the
   highest `vN` tag upstream, compared as numbers:
   `gh api repos/<upstream>/git/matching-refs/tags/v --jq '.[].ref'`. If the project already runs
   it, tell the CEO so in one line and stop.
2. **What the upgrade would change.** Read the latest release's `CHANGELOG.md`
   (`gh api -H 'Accept: application/vnd.github.raw' 'repos/<upstream>/contents/CHANGELOG.md?ref=<tag>'`),
   every entry above the version the project runs. Summarise it for the CEO, in the CEO's
   language, under three headings:
   - **Rules that change how the agents work**, with their § numbers. Once it is installed, the
     agents re-read the sections that change (step 7), and the CEO has nothing to do for that.
     Say whether the release rewrites much of the charter, the one case in which step 8
     recommends a compaction. Scripts and commands take effect at once; the squad board and any
     hook the release adds, at the restart that step 8 asks for.
   - **What the project must do:** each *By hand* item, a `.gitignore` line to commit, or a
     setting to add to a tool.
   - **Anything else the CEO should know.**
3. **Ask the CEO to confirm**, as options with a recommendation and what each costs: upgrade now
   to the latest release, upgrade later, or upgrade to a specific version (say which, and why).
   Install nothing until the CEO says yes. If the answer is no, stop there.
4. **Bring the squad to a safe point,** on the CEO's yes, before installing anything: the install
   replaces the scripts that the hooks and the pre-push gate run, and the restart that step 8 asks
   for ends whatever a session is doing. Send DEV and QA one message each: "The CEO is upgrading the
   squad and needs it at a safe point (`/squad-pause`): follow the part for every agent in
   `squad-pause.md`, in the main checkout's `.claude/commands/`, now, and tell me when you are at a
   safe point." Naming `/squad-pause` that way, in parentheses with a colon, is what lets the squad
   board show DEV and QA as paused. That part ends with each agent waiting for `/squad-resume`,
   which the CEO types once the sessions have restarted (step 8). Get to a safe point yourself too,
   as that part says, apart from this upgrade. Install only once each agent has said so, its state
   is on GitHub or it has said it works on neither, and `ListAgents` shows its session idle. A
   session that `ListAgents` shows as **waiting** is held by a question or a permission prompt in
   its own terminal, and reads no message until the CEO answers it there: name it to the CEO.
5. **Install** from the main checkout:
   `gh api -H 'Accept: application/vnd.github.raw' repos/<upstream>/contents/install.sh | bash -s -- --tag <tag> . > <file> 2>&1`,
   with `<file>` in a temporary directory, and read the exit status of that line. Read the whole
   output, never through `head` or `tail`. The status alone does not prove an install: a download
   that fails without a word leaves the output empty and the status 0.
   - **An empty output,** or a status other than 0 and 1, means nothing was installed: stop and
     report it to the CEO, with the lines that say why when there are any.
   - **Exit 1** means steps marked NOT need a decision: bring them to the CEO as options with a
     recommendation.
   - **Then verify the upgrade:** run `--check` the same way. Its first line must name `<tag>`'s
     version, and the last line of `.agent-squad/install.log` must end with `-> <tag>`. If either
     does not, or if `--check` fails an item that the installer does not list under *By hand*,
     stop and report it.

   Delete the file when you are done.
6. **Commit what the installer lists under *By hand*,** such as a `.gitignore` line or a
   template it created, through the installer's PR (§3; `BOOTSTRAP.md`, *The installer's files*).
   That PR needs no issue of its own, and its description names the release and each *By hand*
   item it records.
7. **Have the agents re-read what changed** (§7). Tell DEV and QA, one message each: the version
   installed, the rules that changed with their § numbers, and to re-read those sections now in
   the main checkout's `.agent-squad/playbook/`, taking them as superseding the text their session
   loaded, and that they stay at their safe point until `/squad-resume`. Re-read the sections
   yourself.
8. **Report to the CEO**, in the CEO's language: the version installed, `--check`'s result, the
   installer's PR, and what DEV and QA were told. Say that the rules need nothing more from the
   CEO: the agents have re-read the rules that changed, and each session loads the full text at
   its next compaction. Only when the release rewrites much of the charter, recommend that the CEO
   type `/squad-save-state` and then `/compact` in each session, the CTO's included, and say why.
   Then guide the CEO through the restart, which is the CEO's to type: a session loads the new
   release of the squad board, and any hook the release adds, only when it starts, and a session
   that restarts takes no turn until something writes to it. First run
   `"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-sessions.sh" "$(git rev-parse --path-format=absolute --git-common-dir)/.."`,
   which names, from what each session's board recorded, the sessions still on an older release
   (agent-squad #361): the roles on its `to restart` line, and those on its `to restart if open`
   line, whose sessions may be closed. Ask the CEO to type `/restart` in each of those, DEV's
   session and QA's first and yours last, and then `/squad-resume` in yours, so that you tell DEV
   and QA to carry on from the state they saved. The band marks each one too, as `DEV ⟳ v50→v53`,
   until it restarts.
