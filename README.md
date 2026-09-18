# agent-squad

The working method of a three-agent software team — **CTO**, **DEV** and **QA**, each a Claude Code
session — directed by a human **CEO**. Born in the `rogue-trader` project; maintained here so that
every project runs the same, versioned method.

## What is here
| Path | What | Copied into projects? |
|---|---|---|
| `SQUAD.md` | The charter: roles, workflow, PR lifecycle, communication | yes |
| `BOOTSTRAP.md` | One-time setup runbook for the CTO | yes |
| `.github/` | Issue and PR templates | yes |
| `.claude/settings.json`, `scripts/squad-handoff.sh` | Context-compaction hooks and handoff snapshot | yes |
| `scripts/squad-merge-gate.sh` | The §4.9 merge gate, checked by API; exits non-zero so that it stops the merge | yes |
| `templates/AGENTS.md`, `templates/openspec/` | Skeletons the CTO fills per project | as a starting point |

## How to use it
1. Create the project repository; copy the files of the latest tag into it (`BOOTSTRAP.md`, row 0).
2. Launch three sessions from the main checkout, named `CTO:<project>`, `DEV:<project>`, `QA:<project>`.
3. Tell the CTO: *read `SQUAD.md` and follow it*. It runs `BOOTSTRAP.md` and creates the rest.

## How it evolves
Upstream first (`SQUAD.md`, section 7): improvements are issues and PRs **here**, reviewed with the
same protocol; projects then copy the new tag in one commit. Project copies are never edited.
Versions are tags `vN` matching the `Version:` line of `SQUAD.md`; see `CHANGELOG.md`.
