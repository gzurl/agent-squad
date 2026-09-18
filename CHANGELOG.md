# Changelog

## v10 — 2026-09-18
- §4.8 and §4.9: findings with no line to anchor to are PR comments tagged with a priority,
  answered and acknowledged like threads, and part of the merge gate (#7).
- §5: headline figures state what they measure and QA reproduces them from artifacts (#6);
  review evidence lives in a git-ignored `evidence/` directory, linked with `file://` (#8).
- §6: nothing is published outside the repository and GitHub; no Claude.ai artifacts (#8).

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
