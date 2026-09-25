# Changelog

## v15 — 2026-09-25
- **Projects install the method instead of carrying copies** (#23). `scripts/squad-install.sh`
  puts a tag in `<project>/.agent-squad/playbook/`, which git ignores, and never overwrites or
  deletes a project file; `--check` verifies an installation and proves the pre-push gate refuses
  a failing check; an upgrade is the same command with a newer tag. Outside `.agent-squad/` it
  only merges the compaction hooks into `.claude/settings.local.json`, appends two ignore lines,
  creates the GitHub templates when missing and writes a `pre-push` shim in the shared git
  directory (#34, #35, #36). `.agent-squad/playbook.manifest` records the playbook's checksums for
  `--check`. The tag's tarball leaves out this repository's own files (`.gitattributes`), so a
  project's agent never loads this repository's `CLAUDE.md` from inside the playbook.
- `.agent-squad/` also holds the worktrees (`worktrees/dev`, `qa`, `cto-<topic>`), the compaction
  snapshots (`handoff/`), the review evidence (`evidence/`) and `install.log` (§2.4, §5).
- The project's list of checks is `.agent-squad-checks`, tracked (§4.2). The gate no longer uses
  `core.hooksPath`, which silently disabled every other hook in `.git/hooks/`; a project's own
  `pre-push` runs first and the shim refuses the push when the playbook is missing. Every push
  that carries commits runs every check. `squad-checks.sh` skips blank lines and indented comments,
  which used to pass as checks; the hook refuses when its runner is not a file; `squad-handoff.sh`
  no longer waits for input on a terminal (#42).
- `AGENTS.md` imports the charter with `@.agent-squad/playbook/SQUAD.md`, so every session has it
  from the start and after each compaction (templates in `BOOTSTRAP.md` and `templates/`).
- §4.9: the merge gate is reached from any worktree through the shared git directory.
- §7: the method's repository has its own CTO; projects' CTOs open issues there and take one to a
  PR only when assigned. `.claude/settings.json` and the GitHub templates are no longer portable
  copies (#16). `BOOTSTRAP.md` rows 0, 9, 9b, 10, 10b, 11 and 13 run the installer and `--check`.
- README rewritten: requirements, install, a map of every directory, upgrade, tooling traps
  (#26); no portable file names a project.

## v14 — 2026-09-24
- Fix: `scripts/squad-checks.sh` clears git's own variables (`git rev-parse --local-env-vars`)
  before running any check. A hook runs with `GIT_DIR` and others set, and a check that uses git,
  such as a test that builds a repository in a temporary directory, acted on the pushing
  repository instead: in rogue-trader it committed into the pushing branch and set `core.bare` in
  the shared config. Any project on v13 that enabled the hook should check its `core.bare` and its
  branches. Closes #19.

## v13 — 2026-09-24
- §4.2: **the checks pass before anything is pushed.** A project lists its checks in `.squad/checks`, and a
  `pre-push` hook (`.githooks/pre-push`, enabled with `git config core.hooksPath .githooks`) runs
  them through `scripts/squad-checks.sh`: each as a command of its own, one status line per check,
  the push refused on a failure, on uncommitted changes, or when the pushed commit is not the one
  checked out; a push that only deletes is not checked. The pushed head is checked, not each commit
  before it; a failing commit fixed in the same push, like `--no-verify`, is declared in the PR.
  Header, §7, BOOTSTRAP.md row 0 and README list the two new portable files; BOOTSTRAP.md row 9b
  installs the hook. This repository's own checks are in `.squad/checks`, and its CI shellchecks
  `.githooks/` too. Closes #17.

## v12 — 2026-09-24
- Header and §7 name the same six portable files; `.github/` is limited to the issue and PR
  templates, since `.github/workflows/` is this repository's own CI and would fail in a project.
  §7 now lists `scripts/squad-merge-gate.sh`. README table says which `.github/` files are copied.
  `.gitignore` ignores `evidence/` (§5). The v11 entry mentions the `--match-head-commit` form.
  Closes #13 and #14.

## v11 — 2026-09-18
- `scripts/squad-merge-gate.sh`: the §4.9 merge gate as a script that stops the merge (verdict bound
  to the head, zero unresolved threads, body-only findings settled, approved label, CI green). §4.9
  requires its use in the form `head=$(scripts/squad-merge-gate.sh <pr>) && gh pr merge <pr>
  --squash --match-head-commit "$head"`, which pins the merge to the head the gate verified; it is
  a portable file (header, BOOTSTRAP row 0, README). Closes #10.

## v10 — 2026-09-18
- §4.8 and §4.9: findings with no line to anchor to are PR comments tagged with a priority,
  answered and acknowledged like threads, and part of the merge gate (#7).
- §5: headline figures state what they measure and QA reproduces them from artifacts (#6);
  review evidence lives in a git-ignored `evidence/` directory, linked with `file://` (#8).
- §6: nothing is published outside the project's repositories; no Claude.ai artifacts, nothing on
  third-party repositories without the CEO's authorisation (#8).
- 2.4: `evidence/` survives QA's cleanup until its PR or issue closes. BOOTSTRAP.md row 11: `evidence/`
  git-ignored next to `.env`.

## v9 — 2026-09-18
- §4.9 merge gate reads the latest review that contains a `QA-VERDICT` line (inline replies create
  empty reviews). §7: project copies may change only by copying a tagged version in full. 2.4:
  runs never write into tracked files. §6: PR titles are the squash subject by repository setting.
  §5: scripts refuse to run on empty or placeholder keys. BOOTSTRAP.md row 6b: repository merge
  settings (squash only, PR title and body as the squash message). Closes issues #1 and #2.

## v8 — 2026-09-18
- First release from this repository. Charter v7 of `rogue-trader` plus the upstream-first rule
  (SQUAD.md section 7), header naming this repository as home, and BOOTSTRAP.md row 0 (copy the
  tagged files). Includes the compaction hooks, the handoff snapshot script, the issue and PR
  templates, and the `AGENTS.md` / `openspec/` skeletons.
