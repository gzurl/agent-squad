# Changelog

## v23 — 2026-09-29
- **An install cut short is caught** (#96). `--check`'s version item now fails when the last line
  of `install.log` does not record the installed version's tag, or when the log records no install,
  and says to install that version again, which records it. An upgrade killed after the playbook
  and before the log used to pass `--check` with a log one version behind.
- **An installer whose output loses its reader finishes** (#96). The installer, and `install.sh`
  (from `main`), ignore SIGPIPE: piped into `head`, a run used to die at its next write, after the
  playbook and before `install.log`, `.gitignore`, the hooks, the shim and the worktrees, with its
  exit status hidden by the pipe. A write that fails now loses a line, not the steps after it.
  `install.sh`'s setting is inherited by the tag's installer, so it covers older tags too.

## v22 — 2026-09-29
- **MIT License** (#94): `LICENSE` at the root is GitHub's own MIT template, so GitHub detects it,
  and the tag's tarball carries it into every installed playbook. The README says so in a
  *License* section, which asks for a link back rather than requiring one.

## v21 — 2026-09-28
- *Language*: **the reader decides** (#92). Messages between agents are written in English, like
  everything in the repository and on GitHub; everything addressed to the CEO, whoever writes it,
  end-of-turn summaries included, is written in the CEO's language. The CTO asks the CEO for it
  before walking `BOOTSTRAP.md`'s table and until then answers in the language the CEO writes in;
  `templates/AGENTS.md` words *Language* that way.
- §6: **a reference says what it is** (#92). In a message or an end-of-turn summary, the first
  mention of an issue or PR carries a summary of two to five words, in the reader's language, inside
  the link (`[#62 — publish the repository](https://github.com/<owner>/<repo>/issues/62)`); later
  mentions are the linked number. On GitHub, `#62` is still enough.
- README: the agents write to the CEO in the CEO's language, and the CTO asks for it first.

## v20 — 2026-09-28
- **Install in one line** (#89): `install.sh`, fetched from `main` (while the repository is private,
  `gh api -H 'Accept: application/vnd.github.raw' repos/gzurl/agent-squad/contents/install.sh |
  bash`), installs or upgrades the squad with the chosen tag's own installer: the latest release by
  default, or `--tag vN` from v15 on, in the current directory or the one given. An upgrade
  therefore writes the new tag's pre-push shim in the same run. It is the one file projects run
  from `main`, and no tag ships it.
- **A README for people** (#88): it opens with you, the CEO, and the team you direct; why GitHub,
  and why the method exists (*Why agent-squad*); one bullet per member, the CTO as the one the CEO
  talks to; the agents coordinating by themselves, each in its own worktree; the labels they
  coordinate with, `needs-ceo` as the CEO's inbox; the quick start in three steps; *How the team
  works* as a sequence diagram that reads top to bottom and shows the review loop; the merge gate's
  conditions once, pointing at §4.9; *Requirements* without branch protection, which
  `BOOTSTRAP.md` row 6 handles, and saying what the installer checks; no *Upgrade*, since
  upgrading is running the install line again; *What goes where* as an annotated tree; no *How it
  evolves*.
- §6: a member's signature emoji may appear in body text where the text introduces that member,
  as the README's roles do. Session names read `CTO:<project-name>` everywhere.
- `BOOTSTRAP.md`: *The installer's files*, how the CTO takes what the installer changed to `main`
  through a PR, moves there from the README; row 0 points at it.

## v19 — 2026-09-28
- **Coherence across every document**, from two independent passes (#84): the charter's owner is
  `agent-squad`'s CTO; the README says who opens issues upstream (§7) and summarises the merge gate
  as §4.9 does; the main checkout commits nothing but the bootstrap commit, which the CTO makes
  there (§2.4, `BOOTSTRAP.md` row 5); OpenSpec applies unless the CEO decided otherwise at bootstrap
  (§3, §9); `BOOTSTRAP.md` rows 0, 6 and 13 match the installer and the template; "Claude Code"
  instead of "harness"; one name for the pre-push gate and one notation for sections (§N.N);
  `{owner}/{repo}` in every `gh api` of the table; the issue and PR templates start with
  `<signature>`; the *Squad* section of this repository's `AGENTS.md` is the template's, word for
  word; the README's tooling traps for script authors move to `AGENTS.md`; the CHANGELOG names no
  project. The scripts' own text follows (#85): the pre-push gate's header, usage paths from the
  playbook, `agent-squad #N` for this repository's issues, and the compaction snapshot logs the
  remote's default branch instead of `main`.

## v18 — 2026-09-28
- §4.9: **the merge gate stops the chained merge** (exit 3) when the PR is behind its base and the
  base changed a file the PR also changes, or when it cannot tell whether it did (a failed or
  truncated comparison, an unreadable list of the PR's files); a renamed file counts under both
  its names. After checking the PR's claims against that base, `SQUAD_BEHIND_CHECKED=<base sha>`
  (full, or a prefix of seven characters or more) lets it pass for that base only. A PR behind
  with no file in common keeps the warning. The v17 warning was read only after the merge it was
  chained to (#80).
- README: *From v14* and *From v15* are gone, since no project is on those versions any more; a
  project on v14 or earlier follows the README of tag `v17`. The note on pushes to `main` is part
  of *Upgrade*'s general text.

## v17 — 2026-09-28
- **The installer and `--check` use the remote's default branch** (`origin/HEAD`, set when
  missing), not `main`; the worktrees start from it, and `--check` has a tenth item saying it is
  known. From git 2.48, `git fetch` sets `origin/HEAD` by itself; it is missing mostly with older
  git or after `git remote add` without a fetch (#72).
- §7: an agent who finds a flaw in the method tells its CTO, who opens the issue in `agent-squad`,
  crediting who found it (#54).
- §5: a source that refuses scripts is investigated by DEV (a plain client, a headless browser as
  it identifies itself, a client that identifies as a person's browser; `robots.txt`, terms of
  use) and decided by the CEO per source; only DEV, only for that analysis, gets past the refusal,
  never with credentials or challenges (#55).
- §3 and §6: anything another agent will act on is written on the issue or PR first, and the
  message only notifies; a message may not arrive; a message that asks for something gets one
  acknowledgement, one that only informs gets none, and a decision always gets a notification
  (#61).
- README, *Upgrade → From v14*, after the first real migration: QA reviews the migration PR from
  its v14 worktree before anything moves; v14 → v16 or later also needs *From v15*; keep
  `evidence/` in `.gitignore` until the evidence has moved; move the worktrees before the
  installer (a move keeps ignored data); clear `__pycache__`, `.mypy_cache` and `.ruff_cache`
  with the `.venv`; QA repoints its `file://` links to the moved evidence; nobody compacts or
  branches until the relaunch; *Things to know* states when `git worktree remove` needs
  `--force` (#78).
- README: the install and upgrade commands resolve the latest release tag (the highest `vN`) with
  `gh` instead of naming one, so a release no longer has to edit them.

## v16 — 2026-09-25
- **Nothing reaches `main` without a PR reviewed by QA**, documentation and OpenSpec minutes
  included (§2.3). An exception is approved by the CEO on an issue before the push; the bootstrap
  commit is one (BOOTSTRAP row 5). The pre-push gate refuses any push to `main` unless
  `SQUAD_MAIN_EXCEPTION` names that issue (#59); GitHub protection, where available, has no
  bypass (row 6). QA checks that documentation is consistent with the rest of the repository.
- **The PR is the unit of attribution** (§6); a commit that reaches `main` without a PR carries the
  author's signature in its body (#47).
- **Review rules** (§3, §4, §5, #27, #28, #57, #58): a PR announces numbered claims a reviewer can
  prove false, and QA gives each a result; evidence on both sides, stating what it proves;
  negative results say what was searched; a claim that something is untouched or absent says how it
  was measured; inputs are checked, not only the arithmetic; the
  author's self-criticism; the tie-break happens in the thread; a P2 is marked `claims: yes|no`,
  and one that does not touch what the PR claims is deferred unless another push is due; any
  agent may challenge the CTO's instructions with evidence, through the CTO to the CEO when a
  CEO decision is at stake; claims are checked against `main` when the PR is behind it, and the
  merge gate warns when it is, naming what `main` changed (#64); published recipes keep working;
  tests that walk a collection fail when it is empty. The PR template asks for numbered claims.
- **Operations** (§2.4, §3): a command that runs out of time can leave processes behind, and the
  agent ends only its own and reports the rest (#48); `gh issue list --label` misses the
  ZWJ-emoji labels, so the squad's scripts never filter by label (a check guards it) and the
  compaction snapshot lists with explicit limits and says when it may be truncated (#56, #63);
  a milestone ships with its user-facing documentation, reviewed by the CEO (#29).
- **Installer and gate fixes:** an interrupted `--check` could delete the user's `TMPDIR` or leave
  its sandbox behind; it no longer can (#71). A CRLF checks list runs without carriage returns (#46); the
  bootstrap commit of an empty repository carries a first `.agent-squad-checks` (BOOTSTRAP row 5); *By hand*
  lists the squad's tracked files still uncommitted, from `git status` (#49); `.gitignore` stays
  out of the tag's tarball (#50).
- **Upgrading from v15:** see the README, *Upgrade*, *From v15* (the PR template, any `openspec/`
  bypass, `AGENTS.md`'s protection line).
- **README** rewritten for readability: built for Claude Code and GitHub, features, quick start,
  contents, an overview with a diagram. §6 lets Markdown documentation carry one emoji per section
  heading, never in body text nor in headings a script parses (#65).

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
  from the start and after each compaction (the *Squad* section of `templates/AGENTS.md`, which
  the installer prints); the re-orientation after a compaction names that charter.
- §4.9: the merge gate is reached from any worktree through the shared git directory.
- §7: the method's repository has its own CTO; projects' CTOs open issues there and take one to a
  PR only when assigned. `.claude/settings.json` and the GitHub templates are no longer portable
  copies (#16). `BOOTSTRAP.md` rows 0, 9, 9b, 10b and 13 now rely on the installer and `--check`, row 10
  points at the *Squad* section of `templates/AGENTS.md`, row 11 drops `evidence/`, and row 14
  requires `--check` to pass entirely.
- README rewritten: requirements, install, a map of every directory, upgrade, tooling traps
  (#26); no portable file names a project.
- **From v14:** a project that carries the v14 copies follows the README, *Upgrade*, *From v14*:
  one PR that removes the copies and moves `.squad/checks`, then an announced stop to unset
  `core.hooksPath`, move the worktrees (and rebuild any environment with absolute paths), install
  and `--check`. Rehearsed end to end on a clone of a v14 project.

## v14 — 2026-09-24
- Fix: `scripts/squad-checks.sh` clears git's own variables (`git rev-parse --local-env-vars`)
  before running any check. A hook runs with `GIT_DIR` and others set, and a check that uses git,
  such as a test that builds a repository in a temporary directory, acted on the pushing
  repository instead: in one project it committed into the pushing branch and set `core.bare` in
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
- First release from this repository. Charter v7 of the project the method came from, plus the
  upstream-first rule (SQUAD.md section 7), header naming this repository as home, and BOOTSTRAP.md
  row 0 (copy the tagged files). Includes the compaction hooks, the handoff snapshot script, the
  issue and PR templates, and the `AGENTS.md` / `openspec/` skeletons.
