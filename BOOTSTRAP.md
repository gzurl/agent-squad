# Squad Bootstrap

> **Owner:** the CTO agent. **Read by:** the CTO only, once per project, before the first task. DEV and QA never need this file.
> **Companion of** [SQUAD.md](SQUAD.md), which holds the rules; this file holds the one-time procedure that puts a repository in the state those rules assume. Both are maintained in the `agent-squad` repository and installed into projects at a tagged version (row 0); in a project this file is `.agent-squad/playbook/BOOTSTRAP.md`.
> **Targets GitHub**, one machine, and three Claude Code sessions.

## How to run it
First ask the CEO which language to use with them (SQUAD.md, *Language*); until they answer, use the language they write in. Row 10 records it in `AGENTS.md`, *Language*.

Walk the table top to bottom. For each artifact, run the check; if it fails, do what the matching column says. Never guess a decision the CEO must make: ask, as options with a recommendation. When everything passes, record in `AGENTS.md` anything this run decided (protected `main` or not, shared account or not, mapped labels), then start *Our Project* (SQUAD.md §9).

Two situations are different throughout:
- **Empty repository:** no commits on the remote. Create freely.
- **Repository with history:** read what exists (conventions, CI, docs, labels, branch protection) before creating anything; never overwrite, and reconcile differences with the CEO and in `AGENTS.md`.

## The table

| # | Artifact | Check | Empty repository | Repository with history |
|---|---|---|---|---|
| 0 | The squad, installed at the chosen tag | `"$p/scripts/squad-install.sh" --check .` passes, where `p` is `.agent-squad/playbook` of the main checkout, except its items for `.agent-squad-checks` and the `AGENTS.md` import, which rows 9b and 10 complete, and, on an empty repository, the worktrees and the default branch, which rows 5 and 13 complete | Run the installer as the `agent-squad` README says (*Install*); what it changes reaches `main` as *The installer's files* below says | Same; it never overwrites a project file: resolve with the CEO what it reports instead (for instance a `core.hooksPath` already set) |
| 1 | Three sessions, `CTO:<project-name>`, `DEV:<project-name>`, `QA:<project-name>`, launched from `<repo>/` | `ListAgents` shows DEV and QA; each confirms it started from the main checkout | Ask the CEO to launch or relaunch the missing ones from `<repo>/` | Same |
| 2 | `gh` authenticated with `repo` and `workflow` scopes | `gh auth status` lists both scopes | Ask the CEO to run `gh auth refresh -h github.com -s workflow` | Same |
| 3 | Toolchains for the stack | The stack's interpreter, package manager and linters run | Ask the CEO to install what is missing | Same |
| 4 | GitHub account arrangement | Do the agents share one account? (`gh api user` in each session) | Record the answer in `AGENTS.md`; it selects the verdict mechanism (SQUAD.md §2.2) | Same |
| 5 | Base branch `main` on the remote | `gh repo view --json defaultBranchRef,isEmpty` | Open an issue for the bootstrap commit and get the CEO's approval there (SQUAD.md §2.3); the CTO then makes it in the main checkout, the one commit it makes there (SQUAD.md §2.4), since no worktree exists before it (minimal, stack-agnostic, with a first `.agent-squad-checks` holding one stack-agnostic check, `git diff --check $(git hash-object -t tree /dev/null) HEAD`, until row 9b lists the CI's) and pushes it with `SQUAD_MAIN_EXCEPTION=#<issue>`: the gate still runs the checks, and refuses a push without a list | Nothing to do; if the default branch is not `main`, record it in `AGENTS.md` and read `main` as that branch everywhere |
| 6 | Branch protection on `main` | `gh api repos/{owner}/{repo}/branches/main/protection` (403 = plan does not allow it) | If allowed: require a PR, status checks and conversation resolution, forbid force-push, no bypass; if not, say so: either way, record it in `AGENTS.md` as `templates/AGENTS.md` words it | Same; remove any bypass (one left for `openspec/`, for instance): the charter has none; record it |
| 6b | Repository merge settings | `gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title,squash_merge_commit_message,allow_merge_commit,allow_rebase_merge}'` shows `PR_TITLE`, `PR_BODY`, `false`, `false` | `gh api -X PATCH repos/{owner}/{repo} -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY -F allow_merge_commit=false -F allow_rebase_merge=false` | Same, after checking with the CEO that squash-only suits the existing history |
| 7 | Labels | `gh label list` equals the table below (name, color, description) | Delete GitHub's default labels; create the table | Keep any existing label used by an open issue; map the rest with the CEO; create what is missing |
| 8 | First milestone | `gh api repos/{owner}/{repo}/milestones` | Create it before handing out the first issue | Same, unless one fits |
| 9 | `.github/` templates and CI | `ISSUE_TEMPLATE/task.md`, `PULL_REQUEST_TEMPLATE.md` and a CI workflow (lint, format check, type check where the language has one, tests) exist | The installer created the templates; CI comes with the first scaffolding issue | The installer kept any existing templates: evaluate them with the CEO and reconcile |
| 9b | Pre-push gate (SQUAD.md §4.2) | `.agent-squad-checks` lists the commands CI runs, one per line, each in the project's environment; `--check` reports that the gate refuses a failing check; `"$p/scripts/squad-checks.sh"` exits 0 on `main`; from the main checkout, with the worktrees in place, the project's test runner collects nothing under `.agent-squad/` (`npx jest --listTests` or `pytest --collect-only -q`, piped to `grep .agent-squad/`, prints nothing) | Write `.agent-squad-checks` with the first scaffolding issue, and exclude `.agent-squad/` in each tool that walks the tree (`templates/AGENTS.md`, *Tools that walk the tree*) | Write `.agent-squad-checks` from the existing CI; exclude `.agent-squad/` the same way |
| 10 | `AGENTS.md` with `CLAUDE.md` as a symlink to it | Both exist; `git ls-tree HEAD CLAUDE.md` shows mode `120000`; `AGENTS.md` has the *Squad* section of `templates/AGENTS.md`, word for word (the installer prints it), and the *Compact instructions* section (template below) | Create both (stack, commands, directories, language, conventions, the two sections) | Read the existing instruction files first; reconcile into `AGENTS.md` with the CEO |
| 10b | Compaction hooks | `jq` is installed (the hook script reads its JSON payload with it); `--check` reports the four hooks in `.claude/settings.local.json` and the `/squad-save-state` command in `.claude/commands/`; simulated hook input (`echo '{"session_id":"x","trigger":"auto"}' \| "$p/scripts/squad-handoff.sh" save`, then the same input to `restore`) prints a snapshot; delete `.agent-squad/handoff/x.md` afterwards | The installer merged them | Same; the installer keeps any other hook of the same event: ask the CEO whether both should run |
| 11 | `.env` conventions | `.env` is git-ignored; `.env.example` lists the variable names with empty values | Create | Check; add what is missing |
| 12 | `openspec/` layout | `vision.md`, `project.md`, `research/` exist | Create; ask the CEO for the vision | Ask the CEO whether OpenSpec applies to this project; if it does, create |
| 13 | Worktrees | `git worktree list` shows `.agent-squad/worktrees/dev` and `.agent-squad/worktrees/qa`, both detached at the remote's default branch (`origin/HEAD`) | The installer creates them once that branch has a commit: on an empty repository, run it again after row 5 | Same |
| 14 | Team ready | `--check` passes, every item; DEV and QA acknowledged the charter and their directories | Ping both with their role, directory and first task | Same |

## The installer's files
What the installer lists under *By hand* (rows 9b and 10) and the tracked files it changed (`.gitignore`, and the GitHub templates when it created them) reach `main` through one PR, like any change; in an empty repository the bootstrap commit of row 5 comes first. The main checkout stays on `main`, so write the PR in a worktree, `git worktree add .agent-squad/worktrees/cto-squad -b chore/squad origin/main`, copy there the tracked files the installer changed, and open the PR from it; remove the worktree after the merge. Before pulling in the main checkout, clear the installer's changes there, or `git pull --ff-only` refuses to overwrite them: `git checkout -- <file>` for each tracked file it modified, and delete each file it created.

The same holds at every upgrade that changes a tracked file, such as a new `.gitignore` line. At the first install and at every such upgrade, this PR needs no issue of its own (SQUAD.md §3): its content was decided and reviewed upstream, in the release it installs, and its description names that release and each *By hand* item it records.

## Compact instructions template for `AGENTS.md`
```
## Compact instructions
When compacting this conversation, always preserve: my role and signature; the issue and PR I am
working on, with their status labels, the PR's `headRefOid`, its latest verdict and open threads;
the exact step I am at and what I was about to do next; anything I promised another agent by
message; decisions taken in this session that are not yet on GitHub. After compaction, re-read
`AGENTS.md` and `.agent-squad/playbook/SQUAD.md` before acting. (Charter rule: SQUAD.md §7.)
```

## Labels
Names are the ones SQUAD.md uses (§3); colors are pastel so that the leading emoji stands out. `gh label create "<name>" --color <hex> --description "<meaning>" --force` creates or updates one.

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
