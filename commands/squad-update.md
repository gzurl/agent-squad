---
description: Tell what a newer agent-squad release changes; it installs nothing (agent-squad)
disable-model-invocation: true
---
The CEO wants to know what a newer release of the squad would change in this project. This command
installs nothing: `/squad-upgrade` does. Your role is your session name.

## If you are DEV or QA
This command is the CTO's. Tell the CEO, in one line and in the CEO's language (`AGENTS.md`,
*Language*), to type `/squad-update` in the CTO's session, and do nothing else.

## If you are the CTO
Work from the main checkout. The upstream repository is the one named on the `upstream=` line of
`.agent-squad/playbook/scripts/squad-install.sh`. Install nothing, change nothing in the project,
and send DEV and QA nothing.

1. **Where the project stands.** Read the version it runs, from the last line of
   `.agent-squad/install.log` and the first line of
   `.agent-squad/playbook/scripts/squad-install.sh --check .`. Then read the latest release, the
   highest `vN` tag upstream, compared as numbers:
   `gh api repos/<upstream>/git/matching-refs/tags/v --jq '.[].ref'`. Run
   `.agent-squad/playbook/scripts/squad-latest.sh --now .` too, so that the squad board's notice
   names the same release (agent-squad #477). If the project already runs it, tell the CEO so in
   one line and stop.
2. **What the upgrade would change.** Read the latest release's `CHANGELOG.md`
   (`gh api -H 'Accept: application/vnd.github.raw' 'repos/<upstream>/contents/CHANGELOG.md?ref=<tag>'`),
   every entry above the version the project runs. Summarise it for the CEO, in the CEO's
   language, under three headings:
   - **Rules that change how the agents work**, with their § numbers. Once it is installed, the
     agents re-read the sections that change, and the CEO has nothing to do for that. Say whether
     the release rewrites much of the charter, the one case in which `/squad-upgrade` recommends a
     compaction. Scripts and commands take effect at once; the squad board and any hook the
     release adds, at the restart that `/squad-upgrade` asks for.
   - **What the project must do:** each *By hand* item, a `.gitignore` line to commit, a change
     to bring into a template the project keeps, or a setting to add to a tool.
   - **Anything else the CEO should know.**
3. **End with your recommendation,** in one line, and what it costs: upgrade now to the latest
   release, upgrade later, or upgrade to a specific version (say which, and why). Then say how:
   `/squad-upgrade`, typed in your session, installs the latest release, and `/squad-upgrade vN`
   installs vN, with no further question.
