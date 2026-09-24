# agent-squad

The working method of a three-agent software team — **CTO**, **DEV** and **QA**, each a Claude Code
session on the same machine — directed by a human **CEO**. The charter (`SQUAD.md`) holds the
rules; this repository versions them and installs them into projects.

## How the team works
```
CEO ── decides what and why ──► CTO ── issues with acceptance criteria ──► DEV
                                                                           │ branch, code, tests
                                                                           ▼
                                 pre-push gate: the project's checks must pass
                                                                           │
                                                                           ▼
QA ◄── ping with the PR's head ── PR (closes its issue) ◄──────────────────┘
 │ code review + black-box tests, one review, verdict bound to the commit
 ▼
merge gate (verdict on the head, no open thread, label, CI green) ──► squash merge by the author
```
Every rule, and the incident that motivated it, is in `SQUAD.md`. `BOOTSTRAP.md` is the CTO's
one-time setup of a project.

## Requirements
- Claude Code, with the three sessions (`CTO:<project>`, `DEV:<project>`, `QA:<project>`)
  launched from the project's main checkout on one machine.
- A GitHub repository, and `gh` authenticated with the `repo` and `workflow` scopes and with
  access to `gzurl/agent-squad`, which is private.
- bash, git 2.31 or later, and `jq`.
- Branch protection needs a paid plan or a public repository; without it, the gates hold by
  discipline and `AGENTS.md` says so.

## Install
From anywhere, with the tag to install and the path of the project's main checkout:
```
tmp=$(mktemp -d)
gh api repos/gzurl/agent-squad/tarball/v15 | tar -xz -C "$tmp" --strip-components=1
"$tmp/scripts/squad-install.sh" /path/to/project v15
rm -rf "$tmp"
```
The installer is idempotent and never overwrites or deletes a file the project owns. It prints
every action it takes or skips, and what it leaves to you:
1. **The *Squad* section of `AGENTS.md`**, which imports the charter into every session (the
   installer prints it, from `templates/AGENTS.md`), and `CLAUDE.md` as a symlink to `AGENTS.md`.
2. **`.agent-squad-checks`**, the list of commands the pre-push gate runs: the ones your CI runs,
   one per line.

Then run `"/path/to/project/.agent-squad/playbook/scripts/squad-install.sh" --check /path/to/project`:
it changes nothing and prints the installed version and the last `install.log` entry, then one
line per item (`check: ok` or `check: FAILED  <item>: <reason>`), and exits 1 if any failed. It
also proves that the gate really refuses a failing check. Right after installing, only the items
the installer leaves to you fail, plus the worktrees in an empty repository: run the installer
again once `origin/main` exists. Launch the three sessions from the main checkout and tell the CTO to follow
`.agent-squad/playbook/BOOTSTRAP.md`.

## What goes where
Everything the squad installs or generates lives in `<project>/.agent-squad/`, which git ignores.
Outside it, the installer only touches the files listed after it.

| Path (from the project's main checkout) | What it holds | Written by | In git | On upgrade | Removed when |
|---|---|---|---|---|---|
| `.agent-squad/playbook/` | The installed `agent-squad` tag, as GitHub's tarball of it: `SQUAD.md`, `BOOTSTRAP.md`, this README, `CHANGELOG.md`, `scripts/`, `templates/` | Installer | No | Replaced whole, only once the new one is complete | Never; reinstall to restore it |
| `.agent-squad/playbook/scripts/` | The compaction hooks' script, the merge gate, the checks runner, the installer | Installer | No | Replaced with the playbook | — |
| `.agent-squad/worktrees/dev/`, `qa/` | DEV's and QA's checkouts (git worktrees) | Installer creates; DEV and QA work there | No | Untouched | Persistent |
| `.agent-squad/worktrees/cto-<topic>/` | The CTO's checkout for one PR | CTO | No | Untouched | After its PR merges |
| `.agent-squad/handoff/` | One snapshot per session, saved before each compaction | Compaction hooks | No | Untouched | When stale, by anyone |
| `.agent-squad/evidence/<pr-or-issue>/` | Screenshots and files a review relies on | QA | No | Untouched | When its PR or issue closes |
| `.agent-squad/install.log` | One line per install or upgrade: date, old tag, new tag | Installer | No | Appended | Never |
| `.agent-squad/playbook.manifest` | The playbook's checksums as installed; `--check` compares against it | Installer | No | Rewritten | Never |
| `.agent-squad-checks` | The project's checks for the pre-push gate | The project | **Yes** | Untouched | — |
| `AGENTS.md`, `CLAUDE.md` → `AGENTS.md` | The project's conventions and the *Squad* section | The project | **Yes** | Untouched | — |
| `.claude/settings.local.json` | The four compaction hooks, next to Claude Code's own local settings | Installer merges ours, keeps the rest | No | Our entries rewritten | — |
| `.gitignore` | Two lines: `.agent-squad/` and `.claude/settings.local.json` | Installer appends when missing | **Yes** | Untouched | — |
| `.github/ISSUE_TEMPLATE/task.md`, `.github/PULL_REQUEST_TEMPLATE.md` | Issue and PR templates | Installer only if missing; then the project | **Yes** | Untouched | — |
| `.git/hooks/pre-push` | A shim that runs the playbook's gate and refuses the push if it is missing | Installer | No | Rewritten | — |
| `.git/hooks/pre-push.local` | The project's previous `pre-push`, if it had one; the shim runs it first | Installer moves it | No | Untouched | — |

## Upgrade
Run the installed installer with the new tag:
`"/path/to/project/.agent-squad/playbook/scripts/squad-install.sh" /path/to/project v16`. It
replaces `playbook/` only once the new one is complete, leaves the rest of `.agent-squad/` alone
and appends to `install.log`. Tell the agents, who re-read the changed sections: a running
session keeps the charter it loaded until it restarts or compacts. `CHANGELOG.md` says what each
version changes.

## Things to know
- **Tools that do not honour `.gitignore`** walk into `.agent-squad/worktrees/` from the main
  checkout and see the other agents' copies of the project: `grep -r`, a test runner without a
  path restriction (pytest without `testpaths`, mypy without `files`), some IDE indexers and
  bundlers. Restrict them to the project's paths; `rg` and ruff honour `.gitignore`.
- **Never run `git clean -x` or `-X` in the main checkout:** it skips the worktrees but deletes the
  playbook, the snapshots and the evidence.
- **Tooling traps:** `gh api --slurp` cannot be combined with `--jq` (pipe into `jq` instead);
  `addPullRequestReviewThreadReply` takes a `pullRequestReviewThreadId`; `jq` takes one variable
  name per `--arg`; zsh does not word-split unquoted variables, so multi-file loops belong in bash.

## This repository
| Path | What | Used from `playbook/` in a project? |
|---|---|---|
| `SQUAD.md`, `BOOTSTRAP.md`, `README.md` | Charter, one-time setup, this guide | Yes |
| `scripts/squad-*.sh`, `.githooks/pre-push` | Installer, compaction hooks, merge gate, checks runner, gate | Yes |
| `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md`, `templates/` | Templates and skeletons the CTO starts from | Yes; the installer copies the GitHub ones when missing |
| `CHANGELOG.md` | What each version changes | Yes, to read |
| `AGENTS.md`, `CLAUDE.md`, `.agent-squad-checks`, `.github/workflows/`, `scripts/check-*.sh` | This repository's own conventions, checks, CI and tests | No: `.gitattributes` keeps them out of the tag's tarball, so a project's agent never loads this repository's `CLAUDE.md` |

## How it evolves
Upstream first (`SQUAD.md`, section 7): any agent who finds a flaw or an improvement in the method
opens an issue **here**, with the incident that motivated it; this repository's CTO owns the PRs,
reviewed with the same protocol. Versions are tags `vN` matching the `Version:` line of
`SQUAD.md`; `CHANGELOG.md` says what each one changes. A project upgrades when its CTO decides.
