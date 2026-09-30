---
description: Show what a new agent-squad release changes, ask the CEO, then install it (agent-squad)
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
     agents re-read the sections that change (step 6), and the CEO has nothing to do for that.
     Say whether the release rewrites much of the charter, the one case in which step 7
     recommends a compaction. Scripts, hooks and commands take effect at once.
   - **What the project must do:** each *By hand* item, a `.gitignore` line to commit, or a
     setting to add to a tool.
   - **Anything else the CEO should know.**
3. **Ask the CEO to confirm**, as options with a recommendation and what each costs: upgrade now
   to the latest release, upgrade later, or upgrade to a specific version (say which, and why).
   Install nothing until the CEO says yes. If the answer is no, stop there.
4. **Install**, on the CEO's yes, from the main checkout:
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
5. **Commit what the installer lists under *By hand*,** such as a `.gitignore` line or a
   template it created, through the installer's PR (§3; `BOOTSTRAP.md`, *The installer's files*).
   That PR needs no issue of its own, and its description names the release and each *By hand*
   item it records.
6. **Have the agents re-read what changed** (§7). Tell DEV and QA, one message each: the version
   installed, the rules that changed with their § numbers, and to re-read those sections now in
   the main checkout's `.agent-squad/playbook/`, taking them as superseding the text their session
   loaded. Re-read them yourself.
7. **Report to the CEO**, in the CEO's language: the version installed, `--check`'s result, the
   installer's PR, and what DEV and QA were told. Say that nothing else is needed from the CEO: the
   agents have re-read the rules that changed, and each session loads the full text at its next
   compaction. Only when the release rewrites much of the charter, recommend that the CEO type
   `/squad-save-state` and then `/compact` in each session, the CTO's included, and say why.
