# Changelog

## v13 — 2026-09-24
- §4.2: **no red commit reaches the remote.** A project lists its checks in `.squad/checks`, and a
  `pre-push` hook (`.githooks/pre-push`, enabled with `git config core.hooksPath .githooks`) runs
  them through `scripts/squad-checks.sh`: each as a command of its own, one status line per check,
  the push refused on a failure, on uncommitted changes, or when the pushed commit is not the one
  checked out; a push that only deletes is not checked. `--no-verify` must be declared in the PR.
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
