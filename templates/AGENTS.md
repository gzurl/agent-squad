# AGENTS.md — <Project>

Project-specific conventions for every agent working in this repository.
`CLAUDE.md` is a symlink to this file. Owner: CTO.

Team roles, the review and merge protocol, the worktree policy and the rules about what may be
pushed directly to `main` are project-agnostic and live in [SQUAD.md](SQUAD.md). Read it once at
the start of a session. This file does not restate those rules; it only adds what is specific
to this project.

## Language
The CEO's language is <language>: messages between agents, and with the CEO, are written in it.

## Compact instructions
When compacting this conversation, always preserve: my role and signature; the issue and PR I am
working on, with their status labels, the PR's `headRefOid`, its latest verdict and open threads;
the exact step I am at and what I was about to do next; anything I promised another agent by
message; decisions taken in this session that are not yet on GitHub. After compaction, re-read
`AGENTS.md` and `SQUAD.md` before acting. (Charter rule: SQUAD.md, section 7.)

## Status
The product decisions agreed so far live in [openspec/project.md](openspec/project.md).

## Directories
Your session name tells you who you are: `CTO:<project>`, `DEV:<project>` or `QA:<project>`.

| Agent | Directory |
|---|---|
| CTO | `<repo>/` (plus ephemeral `<repo>.worktrees/cto-<topic>/`) |
| DEV | `<repo>.worktrees/dev/` |
| QA | `<repo>.worktrees/qa/` |

## Environment facts (from the bootstrap)
- GitHub account arrangement: <shared | separate>.
- `main` protection: <protected with bypass | unprotected: gates by discipline>.

## Git conventions
- **Commits:** Conventional Commits, in English.
- **Branches:** `<type>/<short-kebab-description>`; `qa/` is a branch prefix for QA-owned tests.
- **Base branch:** `main`. Never force-push it. **Merge strategy:** squash.

## Specs
Product decisions agreed between the CEO and the CTO are recorded under `openspec/`.

## Stack and commands
<stack, pinned versions, and the exact lint / format / type-check / test commands>

## Local services and ports
<none yet, or the per-agent ports and container project names>
