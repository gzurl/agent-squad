---
description: Install a newer agent-squad release, the latest or vN, with no question (agent-squad)
disable-model-invocation: true
argument-hint: "[vN]"
---
The CEO typed `/squad-upgrade`, which is the decision to upgrade the squad in this project: install
without asking again. What the CEO typed after it: "$ARGUMENTS". Nothing there means the latest
release; `vN` names the release to install. `/squad-update` tells what a release changes, and need
not come first. Your role is your session name.

## If you are DEV or QA
This command is the CTO's. Tell the CEO, in one line and in the CEO's language (`AGENTS.md`,
*Language*), to type `/squad-upgrade` in the CTO's session, and do nothing else.

## If you are the CTO
Work from the main checkout. The upstream repository is the one named on the `upstream=` line of
`.agent-squad/playbook/scripts/squad-install.sh`.

1. **Which release.** Read the version the project runs, from the last line of
   `.agent-squad/install.log` and the first line of
   `.agent-squad/playbook/scripts/squad-install.sh --check .`. Then read the release tags upstream,
   the `vN` tags compared as numbers: `gh api repos/<upstream>/git/matching-refs/tags/v --jq '.[].ref'`.
   With nothing after the command, the release to install is the latest. A release the CEO named
   must be `v` followed by digits, and one of those tags; anything else, tell the CEO so in one line
   and stop. If the project already runs the release to install, tell the CEO so in one line and
   stop. A named release older than the one the project runs is installed too, since the CEO named
   it, and step 7 says that the project went back.
2. **What it changes,** for the steps below. Read the `CHANGELOG.md` of the release to install
   (`gh api -H 'Accept: application/vnd.github.raw' 'repos/<upstream>/contents/CHANGELOG.md?ref=<tag>'`),
   every entry above the version the project runs: the rules that change, with their § numbers,
   for step 6; each *By hand* item, for step 5; whether the release rewrites much of the charter,
   and the headlines, for step 7. Ask the CEO nothing: typing the command was the yes.
3. **Bring the squad to a safe point** before installing anything: the install replaces the
   scripts that the hooks and the pre-push gate run, and the restart that step 7 asks for ends
   whatever a session is doing. Send DEV and QA one message each: "The CEO is upgrading the
   squad and needs it at a safe point (`/squad-pause`): follow the part for every agent in
   `squad-pause.md`, in the main checkout's `.claude/commands/`, now, and tell me when you are at a
   safe point." It ends with "Sent at <time>; if you read this more than 10 minutes later, ask me
   whether it still holds before acting.", where `<time>` is `date '+%Y-%m-%d %H:%M'` when you
   send it, as every relayed step-away message does (§6). Naming `/squad-pause` that way, in
   parentheses with a colon, is what lets the squad board show DEV and QA as paused. That part ends
   with each agent waiting for `/squad-resume`, which the CEO types once the sessions have restarted
   (step 7). Get to a safe point yourself too, as that part says, apart from this upgrade. Install
   only once each agent has said so, its state is on GitHub or it has said it works on neither, and
   `ListAgents` shows its session idle. A session that `ListAgents` shows as **waiting** is held by
   a question or a permission prompt in its own terminal, and reads no message until the CEO answers
   it there: name it to the CEO.
4. **Install** from the main checkout:
   `gh api -H 'Accept: application/vnd.github.raw' repos/<upstream>/contents/install.sh | bash -s -- --tag <tag> . > <file> 2>&1`,
   with `<file>` in a temporary directory, and read the exit status of that line. Read the whole
   output, never through `head` or `tail`. The status alone does not prove an install: a download
   that fails without a word leaves the output empty and the status 0.
   - **An empty output,** or a status other than 0 and 1, means nothing was installed: stop and
     report it to the CEO, with the lines that say why when there are any.
   - **Exit 1** means the installer left steps not installed, marked NOT, which need a decision:
     stop, and bring them to the CEO as options with a recommendation.
   - **Then verify the upgrade:** run `--check` the same way. Its first line must name `<tag>`'s
     version, and the last line of `.agent-squad/install.log` must end with `-> <tag>`. If either
     does not, or if `--check` fails an item that the installer does not list under *By hand*,
     stop and report it.
   - **Then the labels** (agent-squad #369): run
     `.agent-squad/playbook/scripts/squad-setup-labels.sh --check`, which compares the repository's
     labels with the new release's table. On exit 3, a label the release adds or changes is missing
     or differs: run the script without `--check`, which creates or corrects it, and keep the
     lines it printed for step 7. If that run exits 1, report in step 7 the labels it could not
     write, and run it again later. On exit 1 from `--check`, GitHub could not be read: report it
     in step 7, and run the script again later. The labels it lists as not in the table are the
     project's own: leave them.

   Delete the file when you are done. When this step stops, tell the CEO too that DEV and QA wait
   at their safe point, and that `/squad-resume` brings them back.
5. **Commit what the installer lists under *By hand*,** such as a `.gitignore` line or a
   template it created, through the installer's PR (§3; `BOOTSTRAP.md`, *The installer's files*).
   That PR needs no issue of its own, and its description names the release and each *By hand*
   item it records.
6. **Have the agents re-read what changed** (§7). Tell DEV and QA, one message each: the version
   installed, the rules that changed with their § numbers, and to re-read those sections now in
   the main checkout's `.agent-squad/playbook/`, taking them as superseding the text their session
   loaded, and that they stay at their safe point until `/squad-resume`. Re-read the sections
   yourself.
7. **Report to the CEO**, in the CEO's language: the version installed, and whether the project went
   back to it, `--check`'s result, the installer's PR, the labels created or corrected, and what DEV
   and QA were told. Say that the rules need nothing more from the CEO: the agents have re-read the
   rules that changed, and each session loads the full text at its next compaction. Only when the
   release rewrites much of the charter, recommend that the CEO type `/squad-save-state` and then
   `/compact` in each session, the CTO's included, and say why.
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
   End with the version installed and its release's headlines: the bold opening of each item of its
   `CHANGELOG.md` entry, but for its *Upgrading from* item, one line each; for an upgrade across
   several releases, each release's, the newest first.
