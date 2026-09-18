# Squad Bootstrap

> **Owner:** the CTO agent. **Read by:** the CTO only, once per project, before the first task. DEV and QA never need this file.
> **Companion of** [SQUAD.md](SQUAD.md), which holds the rules; this file holds the one-time procedure that puts a repository in the state those rules assume. Both are maintained in the `agent-squad` repository and copied into projects at a tagged version (row 0).
> **Targets GitHub**, one machine, and three agent sessions of the same harness.

## How to run it
Walk the table top to bottom. For each artifact, run the check; if it fails, do what the matching column says. Never guess a decision the CEO must make: ask, as options with a recommendation. When everything passes, record in `AGENTS.md` anything this run decided (protected `main` or not, shared account or not, mapped labels), then start *Our Project* (SQUAD.md, section 9).

Two situations are different throughout:
- **Empty repository:** no commits on the remote. Create freely.
- **Repository with history:** read what exists (conventions, CI, docs, labels, branch protection) before creating anything; never overwrite, and reconcile differences with the CEO and in `AGENTS.md`.

## The table

| # | Artifact | Check | Empty repository | Repository with history |
|---|---|---|---|---|
| 0 | The squad files, at the version named in `SQUAD.md`'s header | `SQUAD.md`, `BOOTSTRAP.md`, `.github/` templates, `.claude/settings.json` and `scripts/squad-handoff.sh` are byte-identical to the `agent-squad` tag | Copy them from the tag | Copy them from the tag; if the project already has files of the same name, reconcile with the CEO before overwriting |
| 1 | Three sessions, `CTO:<project>`, `DEV:<project>`, `QA:<project>`, launched from `<repo>/` | `ListAgents` shows DEV and QA; each confirms it started from the main checkout | Ask the CEO to launch or relaunch the missing ones from `<repo>/` | Same |
| 2 | `gh` authenticated with `repo` and `workflow` scopes | `gh auth status` lists both scopes | Ask the CEO to run `gh auth refresh -h github.com -s workflow` | Same |
| 3 | Toolchains for the stack | The stack's interpreter, package manager and linters run | Ask the CEO to install what is missing | Same |
| 4 | GitHub account arrangement | Do the agents share one account? (`gh api user` in each session) | Record the answer in `AGENTS.md`; it selects the verdict mechanism (SQUAD.md 2.2) | Same |
| 5 | Base branch `main` on the remote | `gh repo view --json defaultBranchRef,isEmpty` | Order DEV to make the single bootstrap commit directly on `main` (minimal, stack-agnostic) | Nothing to do; if the default branch is not `main`, record it in `AGENTS.md` and read `main` as that branch everywhere |
| 6 | Branch protection on `main` | `gh api repos/<owner>/<repo>/branches/main/protection` (403 = plan does not allow it) | If allowed: require status checks and conversation resolution, forbid force-push, give the CTO a bypass for `openspec/`; if not: record "unprotected, gates by discipline" in `AGENTS.md` | If protected without a bypass: OpenSpec minutes go through a PR; record it |
| 6b | Repository merge settings | `gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title,squash_merge_commit_message,allow_merge_commit,allow_rebase_merge}'` shows `PR_TITLE`, `PR_BODY`, `false`, `false` | `gh api -X PATCH repos/{owner}/{repo} -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY -F allow_merge_commit=false -F allow_rebase_merge=false` | Same, after checking with the CEO that squash-only suits the existing history |
| 7 | Labels | `gh label list` equals the table below (name, color, description) | Delete GitHub's default labels; create the table | Keep any existing label used by an open issue; map the rest with the CEO; create what is missing |
| 8 | First milestone | `gh api repos/<owner>/<repo>/milestones` | Create it before handing out the first issue | Same, unless one fits |
| 9 | `.github/` templates and CI | `ISSUE_TEMPLATE/task.md`, `PULL_REQUEST_TEMPLATE.md` and a CI workflow (lint, format check, type check where the language has one, tests) exist | Copy the templates; CI comes with the first scaffolding issue | Do not overwrite; evaluate the existing ones with the CEO and reconcile |
| 10 | `AGENTS.md` with `CLAUDE.md` as a symlink to it | Both exist; `git ls-tree HEAD CLAUDE.md` shows mode `120000`; `AGENTS.md` has the *Compact instructions* section (template below) | Create both (stack, commands, directories, language, conventions, compact instructions) | Read the existing instruction files first; reconcile into `AGENTS.md` with the CEO |
| 10b | Compaction hooks | `jq` is installed (the hook script reads its JSON payload with it); `.claude/settings.json` declares the `PreCompact` (manual and auto) and `SessionStart` (`compact`) hooks pointing at `scripts/squad-handoff.sh`; `.claude/handoff/` is git-ignored; simulated hook input (`echo '{"session_id":"x"}' \| scripts/squad-handoff.sh save`, then `restore`) prints a snapshot | Copy `.claude/settings.json` and `scripts/squad-handoff.sh`; add the ignore line | Merge the hooks into the existing `.claude/settings.json` without removing others; ask the CEO if a hook of the same event already exists |
| 11 | `.env` and `evidence/` conventions | `.env` and `evidence/` are git-ignored; `.env.example` lists the variable names with empty values | Create | Check; add what is missing |
| 12 | `openspec/` layout | `vision.md`, `project.md`, `research/` exist | Create; ask the CEO for the vision | Ask the CEO whether OpenSpec applies to this project; if it does, create |
| 13 | Worktrees | `git worktree list` shows `<repo>.worktrees/dev` (branch from `origin/main`) and `<repo>.worktrees/qa` (detached) | `git worktree add ../<repo>.worktrees/dev -b <branch> origin/main` and `git worktree add --detach ../<repo>.worktrees/qa origin/main` | Same |
| 14 | Team ready | DEV and QA acknowledged the charter and their directories | Ping both with their role, directory and first task | Same |

## Compact instructions template for `AGENTS.md`
```
## Compact instructions
When compacting this conversation, always preserve: my role and signature; the issue and PR I am
working on, with their status labels, the PR's `headRefOid`, its latest verdict and open threads;
the exact step I am at and what I was about to do next; anything I promised another agent by
message; decisions taken in this session that are not yet on GitHub. After compaction, re-read
`AGENTS.md` and `SQUAD.md` before acting. (Charter rule: SQUAD.md, section 7.)
```

## Labels
Names are the ones SQUAD.md uses (section 3); colors are pastel so that the leading emoji stands out. `gh label create "<name>" --color <hex> --description "<meaning>" --force` creates or updates one.

| Label | Color | Meaning |
|---|---|---|
| `👷🏼‍♂️ owner:cto` | `D8CCF5` | Owned by the CTO agent |
| `👨🏼‍💻 owner:dev` | `D8CCF5` | Owned by the DEV agent |
| `👩🏼‍🔬 owner:qa` | `D8CCF5` | Owned by the QA agent |
| `✨ feature` | `A2EEEF` | New capability |
| `🐛 bug` | `F9C0C0` | Something is not working |
| `🧹 chore` | `CFD3D7` | Tooling, maintenance, refactoring |
| `📝 docs` | `0075CA` | Documentation |
| `🔬 research` | `D4C5F9` | Spike or investigation with a written outcome |
| `🔴 P1` | `F9C0C0` | Must do next |
| `🟡 P2` | `FDF2B3` | Should do |
| `🔵 P3` | `C5DEF5` | Nice to have |
| `👨🏻‍💼 needs-ceo` | `E99695` | Waiting for a decision from the CEO |
| `🚧 status:in-progress` | `FBD9A8` | Someone is actively working on it |
| `👀 status:in-review` | `006B75` | A PR is open and waiting for QA |
| `✅ status:approved` | `C3E6CB` | QA approved the last commit; the author may merge |
| `⛔ status:blocked` | `F9C0C0` | Cannot progress; the reason is in the last comment |
