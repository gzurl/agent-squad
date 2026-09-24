# agent-squad

The working method of a three-agent software team — **CTO**, **DEV** and **QA**, each a Claude Code
session — directed by a human **CEO**. Born in the `rogue-trader` project; maintained here so that
every project runs the same, versioned method.

## What is here
| Path | What | Copied into projects? |
|---|---|---|
| `SQUAD.md` | The charter: roles, workflow, PR lifecycle, communication | yes |
| `BOOTSTRAP.md` | One-time setup runbook for the CTO | yes |
| `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md` | Issue and PR templates | yes |
| `.claude/settings.json`, `scripts/squad-handoff.sh` | Context-compaction hooks and handoff snapshot | yes |
| `scripts/squad-merge-gate.sh` | The §4.9 merge gate, checked by API; exits non-zero so that it stops the merge | yes |
| `scripts/squad-checks.sh`, `.githooks/pre-push` | The §4 local gate: the project's checks, each on its own, run before every push | yes |
| `.squad/checks` | This repository's own list of checks; every project writes its own | no |
| `templates/AGENTS.md`, `templates/openspec/` | Skeletons the CTO fills per project | as a starting point |
| `.github/workflows/ci.yml`, `scripts/check-links.sh`, `scripts/check-version.sh` | This repository's own CI | no |

## How to use it
1. Create the project repository; copy the files of the latest tag into it (`BOOTSTRAP.md`, row 0).
2. Launch three sessions from the main checkout, named `CTO:<project>`, `DEV:<project>`, `QA:<project>`.
3. Tell the CTO: *read `SQUAD.md` and follow it*. It runs `BOOTSTRAP.md` and creates the rest.

## How it evolves
Upstream first (`SQUAD.md`, section 7): improvements are issues and PRs **here**, reviewed with the
same protocol; projects then copy the new tag in one commit. Project copies are never edited.
Versions are tags `vN` matching the `Version:` line of `SQUAD.md`; see `CHANGELOG.md`.
