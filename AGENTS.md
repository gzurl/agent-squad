# AGENTS.md — agent-squad

Conventions for every agent working in this repository. `CLAUDE.md` is a symlink to this file.
Owner: CTO.

Team roles, the review and merge protocol, the worktree policy and the rules about what may be
pushed directly to `main` live in the team charter, imported below. This file does not restate
those rules; it only adds what is specific to this repository.

## Squad
This project follows the team charter in `.agent-squad/playbook/SQUAD.md` (installed by the
squad installer, not tracked). Its full text is loaded below; if you cannot see it, stop and
tell the CTO that the squad is not installed.

@.agent-squad/playbook/SQUAD.md

Here the charter the agents work by is the installed release; `SQUAD.md` at the root is the next
version, being written, and binds nobody until it is tagged and installed.

## Language
The CEO's language is Spanish: messages between agents, and with the CEO, are written in it.

## This is the upstream
This repository is where the method is maintained: its files are **edited here, through PRs**
reviewed like any other, and projects install tagged versions of it (§7).

**`CTO:agent-squad` owns this repository:** the backlog, the design, the PRs (its own or
`DEV:agent-squad`'s, each merged by its author as §4.9 says), the review with `QA:agent-squad`, the
tags and the notices to the projects. The CTOs of other projects open issues
here freely, with the incident that motivated them; they do not create branches, open PRs, merge or
tag, unless `CTO:agent-squad` assigns them a PR explicitly in its issue, and `QA:agent-squad`
reviews such a PR (§7).

## Compact instructions
When compacting this conversation, always preserve: my role and signature; the issue and PR I am
working on, with their status labels, the PR's `headRefOid`, its latest verdict and open threads;
the exact step I am at and what I was about to do next; anything I promised another agent by
message; decisions taken in this session that are not yet on GitHub. After compaction, re-read
`AGENTS.md` and `.agent-squad/playbook/SQUAD.md` before acting. (Charter rule: SQUAD.md, section 7.)

## Status
There is no `openspec/` here: decisions live in the issues and, once released, in
[CHANGELOG.md](CHANGELOG.md).

## Directories
Your session name tells you who you are: `CTO:agent-squad`, `DEV:agent-squad` or `QA:agent-squad`.

| Agent | Directory |
|---|---|
| CTO | `agent-squad/` (plus ephemeral `agent-squad/.agent-squad/worktrees/cto-<topic>/`) |
| DEV | `agent-squad/.agent-squad/worktrees/dev/` |
| QA | `agent-squad/.agent-squad/worktrees/qa/` |

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
- A PR that changes a file that goes into the tag's tarball (everything `.gitattributes` does not
  mark `export-ignore`: the charter, `BOOTSTRAP.md`, the README, the scripts and hooks the playbook
  runs, the templates) also bumps the `Version:` line of `SQUAD.md` and adds the matching entry at
  the top of [CHANGELOG.md](CHANGELOG.md), in the same PR; `scripts/check-version.sh` fails when
  they disagree. A PR that only touches files kept out of the tarball (this file, the CI, this
  repository's own checks and tests) does not bump the version.
- A release built over several PRs lands on `main` one PR at a time, each naming the release's
  parent issue; only its **last** PR bumps `Version:` and writes the CHANGELOG entry. Projects
  install tags only, so `main` between two tags is never installed. This repository is the
  exception: its agents run `main`'s hooks, checks and scripts, so each intermediate PR keeps them
  working here and records in this file what changes for the agents, until the last PR updates
  the charter.
- A tag's tarball, which is what projects install, leaves out what [.gitattributes](.gitattributes)
  marks `export-ignore`: this repository's own conventions, CI, checks list and tests. A new file
  that only this repository uses goes there too.
- After the merge, whoever merged tags the squash commit from a checkout of it, because the
  `pre-push` hook refuses to push a tag whose commit is not the one checked out: in the main
  checkout `git pull --ff-only`, in a worktree `git fetch && git switch --detach origin/main`; then
  `git tag -a vN -m "Charter vN: <summary>" HEAD && git push origin vN`. Then they notify the
  agents of this repository and the CTOs of the projects (`ListAgents`), who decide when their
  project takes the new version.

## Stack and commands
- bash, git ≥ 2.31, `jq`, `gh`, and `uv` (the checks run shellcheck through `uvx`).
- The checks are exactly the lines of [.agent-squad-checks](.agent-squad-checks); run them all
  with `scripts/squad-checks.sh`, and CI runs the same checks (shellcheck from apt instead of
  `uvx`). The pre-push gate and the compaction hooks are the installed release's, as in any
  project: the shim in `.git/hooks/pre-push` runs `.agent-squad/playbook/.githooks/pre-push`, and
  the hooks in `.claude/settings.local.json` run `.agent-squad/playbook/scripts/squad-handoff.sh`.
  The scripts at the root are the next version's; `scripts/check-*.sh` test them.
- `scripts/squad-install.sh --check .` from `.agent-squad/playbook/` verifies this installation;
  after a release, upgrade it like a project does (README, *Upgrade*).

## Local services and ports
None.
