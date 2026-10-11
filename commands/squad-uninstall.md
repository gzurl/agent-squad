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
       evidence and the token history), what the worktrees hold that git ignores, such as a
       `.env`, which it moves into `.agent-squad/kept/` and names on its `kept` lines, and any
       squad-named command the project tracks. `--records` removes all of them but the command;
     - what git tracks and the uninstaller leaves, from its *By hand* list, which step 3 removes
       through a PR, before anything else.
2. **Ask the CEO to confirm**, as options with a recommendation and what each costs: remove the
   squad and keep the records, remove it with its records, or keep the squad. Remove nothing until
   the CEO says yes. If the answer is no, stop there.
3. **First, one PR for what git tracks,** while the squad is still installed, so that the merge
   gate, QA's worktree and the pre-push checks are all there for it. It takes the *Squad* section of
   `AGENTS.md`, the `.gitignore` lines the dry run names (keep `.agent-squad/` unless the CEO chose
   `--records`: the records stay there), and the GitHub templates if the CEO wants them gone.
   - **Write it** from a `cto-<topic>` worktree, as for the installer's files (`BOOTSTRAP.md`, *The
     installer's files*).
   - **Its description** names the release installed and each item it removes. Like the
     installer's PR, it needs no issue of its own (§3).
   - **QA reviews it** as any PR.
   - **Merge it through `squad-merge-gate.sh`** (§4.9), chaining `git pull --ff-only` in the main
     checkout, the removal of the `cto-<topic>` worktree, and the deletion of its branch, as for any
     PR of yours.
4. **Then remove the squad**, from the main checkout: `<uninstaller> .`, with `--records` if the
   CEO chose it. Read its whole output and its exit status.
   - **Exit 1 with `refused` lines:** work appeared in a worktree since the dry run, and nothing was
     removed. The tracked part is already gone, and the rest stays until the uninstaller runs
     again, so nothing is lost. Tell the CEO whose work it is, and run it again once that work is
     committed and pushed, or set aside.
   - **Exit 1 with a `NOT REMOVED` line:** a step needs a decision. Bring it to the CEO as options
     with a recommendation.
   - **Exit 0:** check that `.agent-squad/` holds no more than what the CEO kept, that
     `git worktree list` shows the main checkout alone, and that no `squad-*` command is left in
     `.claude/commands/` but those the project tracks.
5. **Tell DEV and QA**, one message each, that the squad is gone from this project and that their
   sessions can close: their worktrees went with it.
6. **Report to the CEO**, in the CEO's language: the PR for the tracked files, what was removed,
   what was kept, and that the three sessions, this one included, can now be closed.
