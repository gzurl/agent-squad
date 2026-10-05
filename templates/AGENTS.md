# AGENTS.md — <Project>

Project-specific conventions for every agent working in this repository.
`CLAUDE.md` is a symlink to this file. Owner: CTO.

Team roles, the review and merge protocol, the worktree policy and the rules about what may be
pushed directly to `main` are project-agnostic and live in the team charter, imported below. This
file does not restate those rules; it only adds what is specific to this project.

## Squad
This project follows the team charter in `.agent-squad/playbook/SQUAD.md` (installed by the
squad installer, not tracked). Its full text is loaded below; if you cannot see it, stop and
tell the CTO that the squad is not installed.

@.agent-squad/playbook/SQUAD.md

## Language
The CEO's language is <language>: everything addressed to the CEO is written in it, whoever
writes it. Messages between agents are written in English, like everything in the repository and
on GitHub.

## Compact instructions
When compacting this conversation, always preserve: my role and signature; the issue and PR I am
working on, with their status labels, the PR's `headRefOid`, its latest verdict and open threads;
the exact step I am at and what I was about to do next; anything I promised another agent by
message; decisions taken in this session that are not yet on GitHub. After compaction, re-read
`AGENTS.md` and `.agent-squad/playbook/SQUAD.md` before acting. (Charter rule: SQUAD.md §7.)

## Status
The product decisions agreed so far live in [openspec/project.md](openspec/project.md).

## Directories
Your session name tells you who you are: `CTO:<project-name>`, `DEV:<project-name>` or `QA:<project-name>`.

| Agent | Directory |
|---|---|
| CTO | `<repo>/` (plus ephemeral `<repo>/.agent-squad/worktrees/cto-<topic>/`) |
| DEV | `<repo>/.agent-squad/worktrees/dev/` |
| QA | `<repo>/.agent-squad/worktrees/qa/` |

## Environment facts (from the bootstrap)
- GitHub account arrangement: <shared | separate>.
- `main` protection: <protected: a PR required, no bypass | unprotected: the pre-push gate refuses pushes to `main`, the other gates hold by discipline>.

## Git conventions
- **Commits:** Conventional Commits, in English.
- **Branches:** `<type>/<short-kebab-description>`; `qa/` is a branch prefix for QA-owned tests.
- **Base branch:** `main`. Never force-push it. **Merge strategy:** squash.

## Specs
Product decisions agreed between the CEO and the CTO are recorded under `openspec/`.

## Stack and commands
<stack, pinned versions, and the exact lint / format / type-check / test commands; the same commands
are the lines of `.agent-squad-checks`, which the pre-push gate runs>

## Tools that walk the tree
From the main checkout, `.agent-squad/worktrees/` holds the other agents' copies of the project,
and some tools walk into it by default. Each one this project uses excludes `.agent-squad/` in its
own configuration (`BOOTSTRAP.md` row 9b checks it), with a pattern anchored at the project root:
the worktrees themselves live under `.agent-squad/`, so an unanchored pattern also excludes a
worktree's own files when the tool runs inside it. Keep the lines for this project's tools and
delete the others:
- Jest: `testPathIgnorePatterns` and `modulePathIgnorePatterns` both list `<rootDir>/.agent-squad/`.
- Metro: `resolver.blockList` holds a pattern anchored at the project root. For instance, with
  `const path = require('path')` at the top of `metro.config.js`:
  `new RegExp('^' + (path.join(__dirname, '.agent-squad') + path.sep).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))`.
  An unanchored `/\.agent-squad\//` also matches every file of a worktree.
- Watchman: no `ignore_dirs` for `.agent-squad`. A worktree's watch reuses the main checkout's, so
  ignoring it would hide every worktree from itself; Jest's and Metro's own settings are enough.
  If Metro cannot resolve a module in a worktree after installing its dependencies there, recreate
  the main checkout's watch: `watchman watch-del <repo>`, then `watchman watch-project <repo>`.
- pytest: skips dot-directories by default; an overridden `norecursedirs` keeps `.*`.
- TypeScript and mypy skip hidden folders by default, and `rg` and ruff respect `.gitignore`: they
  need nothing.
- Node: a worktree without its own `node_modules` silently uses the main checkout's, through
  Node's upward lookup, so DEV and QA install the dependencies in their worktree before running
  anything there.

## Local services and ports
<none yet, or the per-agent ports and container project names>
