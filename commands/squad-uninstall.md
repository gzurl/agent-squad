---
description: Show what removing the squad would do, ask the CEO, then remove it (agent-squad)
---
The CEO wants to know what removing the squad from this project would do, and to remove it on a
yes. Your role is your session name.

## If you are DEV or QA
This command is the CTO's. Tell the CEO, in one line and in the CEO's language (`AGENTS.md`,
*Language*), to type `/squad-uninstall` in the CTO's session, and do nothing else.

## If you are the CTO
Work from the main checkout. The uninstaller is the installed release's own:
`.agent-squad/playbook/scripts/squad-uninstall.sh`, here `<uninstaller>`. It removes what the
installer wrote outside git and nothing else, and it never touches a tracked file.

1. **What it would do.** Run `<uninstaller> --dry-run .`, read its whole output, never through
   `head` or `tail`, and read its exit status.
   - **Exit 1, with `refused` lines:** a worktree holds work that is not committed or not pushed,
     and nothing would be removed. Tell the CEO which, and whose work it is, and stop. The work is
     committed and pushed, or set aside, before this command is typed again.
   - **Exit 0:** show the CEO, in the CEO's language:
     - what it would remove: the hooks, the commands, the pre-push shim, the board's mods, the
       worktrees and `.agent-squad/`;
     - what it would keep: the records in `.agent-squad/` (the compaction snapshots, the review
       evidence and the token history), which `--records` removes too, and any squad-named
       command the project tracks;
     - what git tracks and the uninstaller leaves, from its *By hand* list, which step 4 removes
       through a PR.
2. **Ask the CEO to confirm**, as options with a recommendation and what each costs: remove the
   squad and keep the records, remove it with its records, or keep the squad. Remove nothing until
   the CEO says yes. If the answer is no, stop there.
3. **Remove it**, on the CEO's yes, from the main checkout: `<uninstaller> .`, with `--records`
   if the CEO chose it. Read its whole output and its exit status.
   - **Exit 1 with `refused` lines:** work appeared in a worktree since the dry run, and nothing
     was removed. Report it to the CEO as in step 1.
   - **Exit 1 with a `NOT REMOVED` line:** a step needs a decision. Bring it to the CEO as options
     with a recommendation.
   - **Exit 0:** check that `.agent-squad/` holds no more than the records the CEO kept, that
     `git worktree list` shows the main checkout alone, and that no `squad-*` command is left in
     `.claude/commands/` but those the project tracks.
4. **Open one PR for what git tracks:** the *Squad* section of `AGENTS.md`, the `.gitignore` lines
   the uninstaller names (keep `.agent-squad/` while the records stay there), and the GitHub
   templates if the CEO wants them gone. Write it from a worktree of its own, as for the
   installer's files (`BOOTSTRAP.md`, *The installer's files*), but outside the project, since
   `.agent-squad/worktrees/` went with the uninstall; remove it after the merge. QA reviews it as
   any PR, on GitHub, since its worktree went too. The merge gate went with the playbook, so check by API what it checks (§4.9): QA's
   verdict on the PR's head, no open thread, `✅ status:approved` alone, and CI green. Then merge
   with `gh pr merge <pr> --squash --match-head-commit <the head QA approved>`.
5. **Once that PR is merged, tell DEV and QA**, one message each, that the squad is gone from this
   project and that their sessions can close: their worktrees went with it.
6. **Report to the CEO**, in the CEO's language: what was removed, what was kept, the PR for the
   tracked files, and that the three sessions, this one included, can now be closed.
