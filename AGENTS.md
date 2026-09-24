# AGENTS.md — agent-squad

Conventions for every agent working in this repository. `CLAUDE.md` is a symlink to this file.
Owner: CTO.

Team roles, the review and merge protocol, the worktree policy and the rules about what may be
pushed directly to `main` live in [SQUAD.md](SQUAD.md). Read it once at the start of a session.
This file does not restate those rules; it only adds what is specific to this repository.

## Language
The CEO's language is Spanish: messages between agents, and with the CEO, are written in it.
Everything in the repository or on GitHub stays in English.

## This is the upstream
This repository is where the method is maintained. The portable files that §7 of `SQUAD.md` lists
are **edited here, through PRs** reviewed like any other; §7's "never edited" applies to the copies
in projects. The CTOs of other projects also open issues and PRs here: before opening one, check
the open issues (for instance [#23](https://github.com/gzurl/agent-squad/issues/23)) and tell
`CTO:agent-squad`, so that two changes to the method do not collide.

## Compact instructions
When compacting this conversation, always preserve: my role and signature; the issue and PR I am
working on, with their status labels, the PR's `headRefOid`, its latest verdict and open threads;
the exact step I am at and what I was about to do next; anything I promised another agent by
message; decisions taken in this session that are not yet on GitHub. After compaction, re-read
`AGENTS.md` and `SQUAD.md` before acting. (Charter rule: SQUAD.md, section 7.)

## Status
There is no `openspec/` here: decisions live in the issues and, once released, in
[CHANGELOG.md](CHANGELOG.md).

## Directories
Your session name tells you who you are: `CTO:agent-squad`, `DEV:agent-squad` or `QA:agent-squad`.

| Agent | Directory |
|---|---|
| CTO | `agent-squad/` (plus ephemeral `agent-squad.worktrees/cto-<topic>/`) |
| DEV | `agent-squad.worktrees/dev/` |
| QA | `agent-squad.worktrees/qa/` |

[#23](https://github.com/gzurl/agent-squad/issues/23) moves the worktrees under
`agent-squad/.agent-squad/worktrees/` in v15; until it is released, this table holds.

## Environment facts
- GitHub account arrangement: **shared**, one account (`gzurl`) for the three agents.
- `main` protection: **unprotected, gates by discipline.** The plan answers 403 to branch
  protection and to rulesets, so no bypass exists either.

## Git conventions
- **Commits:** Conventional Commits, in English.
- **Branches:** `<type>/<short-kebab-description>`; `qa/` is a branch prefix for QA-owned tests.
- **Base branch:** `main`. Never force-push it. **Merge strategy:** squash; the PR title is the
  squash commit subject.

## Releases
- A PR that changes a portable file (§7) also bumps the `Version:` line of `SQUAD.md` and adds the
  matching entry at the top of [CHANGELOG.md](CHANGELOG.md), in the same PR;
  `scripts/check-version.sh` fails when they disagree. A PR that only touches the README, this
  file, the CI or this repository's own scripts does not bump the version.
- After the merge, whoever merged tags the squash commit and pushes the tag:
  `git tag -a vN -m "Charter vN: <summary>" <sha> && git push origin vN`. Then they notify the
  agents of this repository and the CTOs of the projects (`ListAgents`), who decide when their
  project takes the new version.

## Stack and commands
- bash, git ≥ 2.31, `jq`, `gh`, and `uv` (the checks run shellcheck through `uvx`).
- The checks are exactly the lines of [.squad/checks](.squad/checks); run them all with
  `scripts/squad-checks.sh`. The `pre-push` hook runs the same script (`core.hooksPath` is
  `.githooks` in this clone), and CI runs the same checks (shellcheck from apt instead of `uvx`).

## Local services and ports
None.
