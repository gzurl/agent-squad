# Changelog

## v66 — 2026-10-19
- **A release branch is held as `main` is** (#441, reported by trivial-tape's CTO from its QA's
  finding, and #446). trivial-tape ships 0.15.2 from `release/0.15` while `main` carries 0.16, and
  the pre-push gate let a direct push to that branch through, since it held the default branch
  alone. §2.3: a project lists the patterns of its release branches in
  `.agent-squad-release-branches`, at its root, in the form of `.agent-squad-checks`. Only a PR
  reviewed by QA changes a branch that matches, with the same exception as `main`. The pre-push
  gate refuses a direct push to one, and reads the declaration from the default branch's tip, so
  that a push cannot lift it with its own commit. A fix goes to `main` first, and a backport, a PR
  that names the PR it carries (`Backport of #M`), takes it to the release branch: §2.4, §3, §4.1,
  §4.2, §5 and §6 say so. BOOTSTRAP's row 6 protects the release branches on GitHub, and
  `templates/AGENTS.md` records them.
- **Upgrading from v65:** a project with release branches lists them in
  `.agent-squad-release-branches` and commits it to `main` through a PR, protects them on GitHub
  as `main` is (`BOOTSTRAP.md`, row 6), and records them in `AGENTS.md`. Then restart the three
  sessions, since §2.3, §2.4, §3, §4 and §5 change.

## v65 — 2026-10-18
- **A GitHub call that never answers ends, and the stall watch goes on** (#430, #437, and #439,
  found by QA in its review of PR #436). On 2026-10-18 a `/squad-watch` pass hung for 2 h 21 min
  on a `gh` call whose connection died while the Mac slept, and the passes after it queued up
  behind it. The new `scripts/squad-timeout.sh` bounds a command by wall-clock time, which moves on
  while the machine sleeps, unlike `sleep`, `alarm` or GNU `timeout`. Past the bound, it stops the
  command and every process the command started, such as a `git` call's ssh. A command that ends
  in time returns as soon as it ends. `squad-stalls.sh`, `squad-outside.sh` and `squad-plan.sh` run each GitHub call
  through it, 120 s by default (`SQUAD_GH_TIMEOUT`), and exit 1 with a message that says so when a
  call does not answer. `squad-latest.sh` keeps its exit 0, and its line says when GitHub did not
  answer within its 10 s.
- **Every other call to GitHub or to the remote ends too** (#435). The session hooks' snapshot,
  the merge gate, `squad-set-status.sh`, `squad-setup-labels.sh`, the installer and the pre-push
  gate run each such call through `squad-timeout.sh`. The bound is 120 s, or 10 s in the session
  hooks. A call that never answers fails, and the script says so. The snapshot reads
  `(GitHub did not answer within 10 s)`. A pre-push gate whose remote did not list its branches
  counts every ref pushed as new code.
- **Going back to an older release names the sessions to restart** (#428, found by QA in its
  review of PR #427). After a downgrade, `squad-sessions.sh` said that every session ran the
  installed release, though each still ran the newer squad board until it restarted. It now names
  a session on a newer release than the installed one to restart, as it names one on an older
  release, and the band marks it the same way. `/squad-upgrade`, `/squad-resume` and the README
  say so.
- **The plan's table knows a release that takes no README read** (#429). §3: the CTO's note that a
  release which only fixes things takes no read is a line of the plan issue's description, outside
  its markers, that starts with `No README read:` and gives the reason. The table's README row
  then shows the read as not taken, with that reason, before and after the tag, and the stall
  watch asks for no read. Until now the row asked for a read, and showed one as done once tagged.
- **Outside the release, already live:** `install.sh` runs from `main`, and it now bounds its own
  calls to GitHub the same way. When one never answers, it exits 2 with nothing installed (#435).
- **Upgrading from v64:** nothing to do by hand. Re-read §3's paragraph on plan issues, and
  restart the three sessions to load the new squad board.

## v64 — 2026-10-17
- **Going back to an older release names the rules it takes back** (#425, found by QA in its
  review of PR #424). `/squad-upgrade vN` to a release older than the one the project runs read
  that release's `CHANGELOG.md`, which has no entry above the running version, and so told DEV, QA
  and the CEO that no rule changed. It now reads the installed playbook's `CHANGELOG.md` before the
  install replaces it, names the rules that revert, with their § numbers, to DEV and QA and in its
  report, and ends with the headlines of the releases it takes back.
- **Upgrading from v63:** nothing to do. No rule changes, and the command takes effect at once. A
  restart only brings the squad board's version up to date.

## v63 — 2026-10-15
- **`/squad-update` tells, `/squad-upgrade` installs** (#422, the CEO's decision). `/squad-update`
  tells what a newer release changes, as `/squad-upgrade` did, and installs nothing.
  `/squad-upgrade` installs the latest release, and `/squad-upgrade vN` a given one, with no
  question, since typing it is the CEO's yes; it need not follow `/squad-update`. It still brings
  the agents to a safe point first, stops and tells the CEO when a step is left undone or the check
  fails, and asks for the restart and `/squad-resume`. It ends with the version installed and its
  release's headlines. The squad board's notice of a newer release names `/squad-update`. §7 says
  so.
- **Upgrading from v62:** nothing to do by hand. Restart the three sessions, so that each loads the
  new §7 and the board's new notice. This upgrade still runs v62's `/squad-upgrade`, which asks
  first; from v63 on, it installs without asking.

## v62 — 2026-10-15
- **A session in its worktree loads the project's instructions once** (#416, reported by
  rogue-trader's squad). Until now, the first Read, Edit or Write in a worktree also loaded that
  worktree's copy of `CLAUDE.md`, beside the main checkout's: about 48k tokens more per session in
  rogue-trader, and again after each compaction. The installer now writes Claude Code's
  `claudeMdExcludes` into `.claude/settings.local.json` for each worktree's `CLAUDE.md`,
  `.claude/CLAUDE.md` and `.claude/rules/`, and keeps the project's own entries; a `CLAUDE.md` in
  a worktree's subdirectory still loads. `--check` verifies the entries, and the uninstaller
  removes them.
- **The charter's italic notes give a rule's reason, not the story of its incident** (#417, the
  CEO's decision). The 13 notes that only told an incident go, and 20 others keep only their
  reason, in a sentence. No rule changes. The charter is about 700 words shorter, and the README
  says that each rule comes with its reason.
- **Upgrading from v61:** nothing to do by hand, since the installer writes the setting. Restart
  the three sessions, so that each loads the shorter charter and starts with the setting.

## v61 — 2026-10-14
- **`/squad-upgrade`'s pause relay gives the time it was sent** (#413, noticed by DEV and QA at the
  v58 and v60 upgrades). Its step 4 ends the message with the same "Sent at" line as
  `/squad-pause`, as §6 asks of every relayed step-away message, and a check of this repository
  fails when a command that relays one leaves the line out.
- **Upgrading from v60:** nothing to do. No rule changes, and the command takes effect at once. A
  restart only brings the squad board's version up to date.

## v60 — 2026-10-14
- **A release that only fixes things takes no README read** (#410, the CEO's decision). §3: when
  the README is unchanged since the last tag, and the CHANGELOG entry adds no rule and nothing a
  user notices, the CTO says so on the plan issue in one line and tags the release. The install
  still waits for the CEO's yes.
- **Upgrading from v59:** restart the three sessions, as `/squad-upgrade` asks, since §3 changes.
  Nothing else.

## v59 — 2026-10-14
- **On Windows, the squad's scripts drop the carriage return that `jq` writes at the end of each
  line** (#405, reported by @fctcode in #403). It had kept `squad-plan.sh` from adding sub-issues,
  since GitHub refused `"<id>\r"` as an id. Every script that runs `jq` now strips it, and a new
  check of this repository keeps it so.
- **Outside the release, already live:** `install.sh`, which runs from `main`, makes its temporary
  directory in a way NTFS allows, and leaves nothing in `TMPDIR` when it fails (#404, reported by
  @fctcode in #402).
- **Upgrading from v58:** nothing to do. No rule changes, and the scripts take effect at once. A
  restart only brings the squad board's version up to date.

## v58 — 2026-10-14
- **GitHub text is short, and says each thing once** (#397, the CEO's decision, from a reading of
  three squads' issues and PRs). §6 adds seven principles:
  - the point first;
  - each thing said once, and linked elsewhere;
  - an issue as *Why*, *What* and outcome criteria;
  - a PR's claims about the change, with its evidence given once, folded;
  - a review that opens with its verdict, and later rounds on the delta only;
  - the state as below;
  - no thanks and no loose notes.

  It sets word budgets as SHOULD: an issue, 200 visible words besides its criteria, and 7 criteria
  at most; a PR description or a review, 300; a comment, five lines. Folded `<details>` do not
  count, and going over a budget is a P3 at most. §1's DEV reference, §3, §4.2, §4.6, §5, §7 and
  §8, the PR and issue templates and the README follow it.
  - **State:** an agent's state comment opens with its signature, a status emoji and `State:`.
    `/squad-save-state` edits it in place while it is still the item's last comment, and posts a
    new one once anyone has written after it, so that the state in force is always at the bottom.
    The compaction hook's re-orientation points at the latest one.
- **An outside reporter is credited as `@<login>`** (#396, the CEO's decision). A Release's notes
  then link the account and count it among the Release's contributors (§3). v57's entry now credits
  `@fctcode`.
- **Upgrading from v57:** restart the three sessions, as `/squad-upgrade` asks, since §1, §3, §4,
  §5, §6, §7 and §8 change. Nothing else is needed. The PR and issue templates in `.github/` belong
  to each project once installed, so the installer leaves a project's own as they are. A project
  that wants the new ones copies them from `.agent-squad/playbook/.github/`.

## v57 — 2026-10-14
- **`/squad-usage` finds a project's transcripts on Windows, and reports no silent zero** (#389,
  reported by @fctcode in #388).
  - **On Windows, under Git Bash,** `squad-tokens.sh` names Claude Code's directory for the project
    from the main checkout's Windows path, which `cygpath -w` gives, and matches it ignoring case,
    since the drive letter's case varies with how the session was started. It used to name it from
    git's POSIX path, which Claude Code does not use there, and found nothing. Nothing changes on
    macOS and Linux.
  - **No silent zero:** by default, when neither a transcript directory nor the history has the
    project, it says where it looked and exits 1. It used to report "No token usage recorded", with
    0, which read like a measurement. `/squad-usage` gives the CEO that message, and says that
    nothing was counted. `--all` and `--project` are unchanged, since they group by session name.
- **A release's plan issue is the parent of its milestone's issues** (#391, the CEO's idea).
  - `squad-plan.sh --update`, which `squad-set-status.sh` runs at every state change and
    `/squad-watch` at each pass, keeps the plan issue's sub-issues in step with its milestone, its
    closed issues included. GitHub then shows each issue's parent, and the plan issue shows a bar of
    how many are done. An issue that already has another parent stays under it, as do the issues
    past the 100 sub-issues GitHub allows, and the script's line says so. A sub-issue that cannot
    be read or written stops no other plan: every table is still written, and the run exits 1. It
    all goes through `gh api`, which any `gh` can call.
  - **An accepted outside report shows the squad issue that answers it:** on the CEO's yes, the CTO
    marks the report as blocked by that issue, so that each issue's page shows the other (§3).
  - The README says so: *The plan, pinned on GitHub* for the sub-issues, and *Contributing* for an
    outside report.
- **Upgrading from v56:** restart the three sessions, as `/squad-upgrade` asks, since §3 changes.
  Nothing else: no label, file or setting changes. The next `squad-set-status.sh` or `/squad-watch`
  makes a plan in progress the parent of its milestone's issues.

## v56 — 2026-10-13
- **A release's version PR names its plan issue, and closes none** (#384, the CEO's decision).
  v55's plan showed the version step twice: the row of #380, an issue opened only so that the
  version PR had one to close, and the table's own *Version PR* row.
  - **The charter's exception:** §3's *Every PR MUST close an issue* exempts a release's version
    PR, the one that sets the release's version and writes its CHANGELOG entry. It names the plan
    issue with `Part of #N` instead, since the plan issue stays open until the release is out.
    §4.2's and §5's first checklist items say the same. The plan issue takes no status label from
    it, and stays open after its merge: §4.2's last item and §4.9's clean-up act only on an issue
    the PR closes.
  - **The plan's *Version PR* row shows the open version PR** as an issue's row shows its PR: its
    number, whether it is a draft, in review, approved or has changes requested, its head, its CI,
    and whose the next step is. `squad-plan.sh` takes for it the open PR that names the plan issue
    with `Part of #N` and closes no issue, the highest-numbered of several. In a project, whose
    plan has no *Version PR* row, the table stays as it was.
- **Upgrading from v55:** restart the three sessions, as `/squad-upgrade` asks, since charter rules
  change (§3, §4.2, §4.9, §5). Nothing else: no label, file or setting changes. The exception binds
  once v56 is installed, so v56's own PR still closed its issue.

## v55 — 2026-10-13
- **A status label is set in one command, and read back** (#367, found by rogue-trader's DEV). An
  issue there was closed carrying two states, after a `gh issue edit` whose result went unread,
  and only the merge gate checked the rule, on PRs alone.
  - **`squad-set-status.sh <issue|pr> <n> <state>`** sets the state and removes the others in one
    edit, then reads the labels back, and fails unless that state alone is there. It reads the
    item's kind before it writes, so that an issue command given a PR's number writes nothing
    (#375, found by QA).
  - **The charter names it** wherever it tells an agent to set or remove a status label: §1's
    quick references, §3, §4.2, §4.5 to §4.7 and §4.9. The board follows it, and the merge gate's
    message on two states names it.
- **The squad's labels are created by a script** (#369, the CEO's idea). `squad-setup-labels.sh`
  creates the labels of `BOOTSTRAP.md`'s table that the repository lacks, and corrects those whose
  color or description differs. It never deletes one, and `--check` only lists them, exiting 3 on
  a gap. `BOOTSTRAP.md` row 7 and `/squad-upgrade` run it, so that an entry that adds a label
  needs no *By hand* line for it.
- **A pinned plan issue shows the release in progress** (#370, the CEO's idea). Each release in
  progress has a plan issue, pinned, whose table `squad-plan.sh --update` writes: one row per
  issue, with its state and whose the next step is, then the release's own steps (§3).
  - **It follows the work:** `squad-set-status.sh` runs it at every state change, and
    `/squad-watch` at each pass. `/squad-resume` shows the table, its cells in the CEO's language.
  - **§6's emoji rule** names the table. The next step comes from `squad-steps.jq`, which the
    stall detector now shares.
- **Upgrading from v54:**
  - **Restart the three sessions,** as `/squad-upgrade` asks, since charter rules change (§3, §4,
    §6).
  - **Check the labels once:** v54's `/squad-upgrade` does not run `squad-setup-labels.sh`, so
    run `squad-setup-labels.sh --check` after this upgrade. v55 adds no label, so it should find
    none missing. A label it lists as different, in color or description, the script corrects to
    the table's: run it, unless the project chose those words or that color on purpose.
  - **A milestone already in progress** gets its plan issue: the CTO opens it and pins it (§3).

## v54 — 2026-10-12
- **The squad shows which sessions still run an older release** (#361, proposed by
  rogue-trader's CEO). After an upgrade, a session keeps its old board and hooks until its
  `/restart`, and nothing showed which ones had not restarted.
  - **The band** marks each such session with both releases, as `DEV ⟳ v50→v53`, until its
    `/restart` (#362).
  - **`/squad-upgrade` and `/squad-resume` name the sessions still to restart,** from a record
    that each session's board writes in `.agent-squad/sessions/`. The new `squad-sessions.sh`
    reads it.
- **The first upgrade into v54** names every open session as having no record, to restart, since
  v53's boards write none. From then on, only the sessions on an older release are named.
- No charter rule changes. Restart the three sessions after the upgrade, as `/squad-upgrade` asks.

## v53 — 2026-10-12
- **The band keeps an agent's item through its work** (#354, seen by the CEO). DEV's item vanished
  while it worked on a parent issue through sub-issues.
  - **An issue created with `🚧 status:in-progress`** is the agent's focus, as one labelled later
    is.
  - **A PR is tied to the issue its body closes** (`Closes`, `Fixes` or `Resolves #N`), read from
    `--body` or an absolute `--body-file`, never from the network. Merging it drops that issue
    alone, so a parent issue stays while its sub-issues' PRs merge.
  - **Taking an issue's in-progress or in-review label off,** with none put on, ends it, as §4.9's
    step after a merge does.
- **An install over a `.agent-squad/squad-hook` that is not a file refuses, saying so** (#356,
  found by DEV while writing tests, filed by QA). Before, it moved the wrapper into it and reported
  success, and every hook then failed.
- **The scripts' tests run every line** (#246, #348, #350, #352), but the installer's two
  timing-only lines, which carry a comment that excuses them. This repository's coverage check had
  read about 44% since v52's PR #322 while it passed, and it now fails when it cannot read a
  result.
- No charter rule changes. As `/squad-upgrade` asks, restart the three sessions after the upgrade,
  to load the new board.

## v52 — 2026-10-12
- **A session that is not in the main checkout is told so** (#319, found by biwenger-metrics-ai's QA
  and CEO). Such a session was started in a subdirectory, or resumed from one.
  - **Before:** v50's hooks failed in it with nothing reaching the model, and older ones said the
    charter was not installed.
  - **Now:** the hooks name the wrapper by its absolute path, and the wrapper tells this case apart
    from a missing playbook. The session hears where it belongs and that it should start again
    from the main checkout, without `--resume`.
  - **§2.1** says so, and `--check` names a checkout that has moved.
- **A session start always checks the latest release** (#336): a new session, a resumed one, a
  `/restart` or a `/clear`, though not a compaction. The other moments keep the once-a-day rule. An
  upgrade adds a hook for `/clear`.
- **The stall watch leaves an approved PR to a reviewer still requested on GitHub** (#306, from
  trivial-tape's squad). It tells the CEO after an hour, since only the CEO can reach a human
  reviewer. The squad's own review and answer steps ping as before.
- **The band:**
  - **The PR QA reviews** shows when QA checks it out with `git fetch … pull/<n>/head` and
    reviews through `gh api` (#334).
  - **`/squad-upgrade`'s safe point** shows DEV and QA as ⏸️ (#320).
- **The commands only the CEO types cannot be run by the model** (#325): `/squad-uninstall`,
  `/squad-upgrade`, the step-away commands and their `-all` forms, and `/squad-save-state`. Typing
  them, `/loop 30m /squad-watch`, and a relay that reads a command's file work as before.
- **Releases and downloads** (#330, #341):
  - **A Release carries the package alone.** The installer checks it against the SHA-256 that
    GitHub publishes for it, so each install counts once.
  - **The README shows a downloads badge,** and its badges sit in two rows, with *Built for Claude
    Code* and *Built for GitHub*.
  - **A v50 or v51 installer run by hand with v52 refuses,** its playbook unchanged (#335). Upgrade
    with `install.sh` or `/squad-upgrade`, which run v52's own installer.
  - **Once v52 is out, v50's and v51's Releases lose their `.sha256`,** so that the badge counts
    packages alone (#330). v50 and v51 can then no longer be installed by tag, since their own
    installers need that file; upgrading from them is unaffected.
- **Charter:**
  - **§6:** an announced step starts in the same turn (#326).
  - **§2.4:** a load of the whole machine is announced to every other squad on it, and waits for
    their answers (#337).
  - **§2.1:** the misplaced session above.
- **Upgrading:** as v51 says, `/squad-upgrade` brings the squad to a safe point, then asks for
  `/restart` in the three sessions and `/squad-resume`. Upgrading from v50 or older, type
  `/squad-pause` first.

## v51 — 2026-10-12
- **`/squad-upgrade` brings the squad to a safe point before installing** (#317). On the CEO's
  yes, DEV and QA follow `/squad-pause`'s part for every agent, and save their state, before the
  install replaces the scripts that their hooks and pushes run. §7's summary of `/squad-upgrade`
  says so.
- **Then it guides the CEO through the restart** (#315, #317). Every upgrade needs one, since a
  session loads the board and any hook a release adds only when it starts.
  - **The CEO types `/restart`** in DEV's session, in QA's and, last, in the CTO's. Claude Code's
    `/restart` keeps each session's conversation and name.
  - **Then `/squad-resume`** in the CTO's session. A restarted session waits for someone to write
    to it, and `/squad-resume` tells DEV and QA to carry on from the state they saved.
  - The README's *Upgrade* section says the same.
- **Upgrading to v51:** the `/squad-upgrade` that runs it is the installed release's, which
  neither brings the squad to a safe point nor guides the restart yet. Type `/squad-pause` in the
  CTO's session first, then `/squad-upgrade` once the three are at a safe point. When it is done,
  type `/restart` in DEV's session, in QA's and, last, in the CTO's, and then `/squad-resume` in
  the CTO's.

## v50 — 2026-10-12
- **The band follows each agent's focus** (#289, found by trivial-tape's CEO), not its last `gh`
  call.
  - **Declaring work sets the item:** an issue marked `🚧 status:in-progress`, a PR the agent
    creates, or a PR it checks out or reviews.
  - **Bookkeeping does not:** viewing, commenting, other labels.
  - **A merge or a close** goes back to the focus before it.
  - **Every `gh` call** on a command line counts, in order. The PR that `gh pr create` made is
    never taken for one an earlier call on the line printed (#299).
  - Each key gains a `focus` list, and a key written before v50 comes back as a focus of its item.
- **The band's squad part moves to the right** (#244). The agents come first, on the left; on the right
  go ⏩ while the squad is on autopilot, the wordmark and the release, and the notice of a newer one:
  `agent-squad (v49) → v50 available: /squad-upgrade`. On a narrow terminal the squad's part
  shortens first, and a narrower band never shows more than a wider one (#304).
- **The latest release is checked at most once a day** (#302, #309): at session start, at the end of
  a turn once a day has passed, and in `/squad-resume` and `/squad-watch`.
  - The new `squad-latest.sh` writes `.agent-squad/latest-release` for the band. Offline, it retries
    at most once an hour, and a time ahead of now counts as never.
  - An upgrade adds a hook at the end of each turn, through the same wrapper as the others, and
    `--check` requires it.
- **Each release is a GitHub Release with its package** (#295), so that GitHub counts its downloads,
  one number per version, and nothing about who.
  - From v50 on, the installer downloads the Release's package and checks its SHA-256, with
    `sha256sum` or `shasum`.
  - A tag without a Release still installs from its tarball.
- **The installer reads the project's own `.gitignore` rules,** whatever the machine's excludes say
  (#296). An install no longer asks for a decision there, and `--check` passes. Lines an earlier
  install appended twice are harmless, and can be removed by hand.
- **The uninstaller** lists the `.claude/settings.local.json` ignore line only when that file goes
  (#291).
- No charter rule changes. Restart the three sessions after the upgrade, to load the new board and
  the new hook.

## v49 — 2026-10-12
- **What comes from outside: the author decides, and a label only shows it** (#281, after #276).
  - **§3:** an issue, pull request, review or comment is inside only when its account is the
    repository's owner, a member or a collaborator, `CONTRIBUTOR` included among the outside ones.
  - **§3, credit:** an accepted report is credited in the CHANGELOG. Code reused from an outside
    pull request is credited with a `Co-authored-by:` trailer, which puts its author in the
    repository's *Contributors*. That code is written again, or read line by line, before anything
    runs it.
  - **§6:** a signature proves nothing; only the account does.
  - **`📥 needs-triage`** is a new label (`BOOTSTRAP.md`, *Labels*). A project creates it by hand.
    This repository sets it with a workflow of its own.
  - **`squad-outside.sh`** lists, for `/squad-resume` and `/squad-watch`, the outside items waiting
    for triage and the outside comments and reviews since the last one, each with its account. The
    stall watch asks the CTO for a triage that has waited half an hour.
- **The merge gate refuses a PR labelled `👨🏻‍💼 needs-ceo`** (#283, from rogue-trader's CTO). §4.9's
  checklist lists it: a merge would take the CEO's decision in the CEO's place.
- **A blocked `/compact` says what to do** (#269): *Save this session's state first: type
  /squad-save-state, then /compact.*
  - The five hooks now run a small wrapper, `.agent-squad/squad-hook`, which keeps the warning when
    the playbook is missing. `--check` verifies it.
  - **An upgrade rewrites the five hooks' commands and writes the wrapper.** Restart the sessions to
    load them.
- **Removing the squad** (#263, #287): `/squad-uninstall`, a new command, in the CTO's
  session. It runs `squad-uninstall.sh`, which ships in the playbook and can also be run by hand,
  with `--dry-run` first.
  - **It removes** what the installer wrote outside git, after a PR for what git tracks.
  - **It keeps** the records, and moves what a worktree held that git ignores, such as a `.env`,
    into `.agent-squad/kept/`.
  - **It refuses** while a worktree holds unsaved or unpushed work.
  - A known gap is #291.
- **The docs count nothing that grows** (#297): the README, `BOOTSTRAP.md` and `CONTRIBUTING.md`
  say "the squad's commands" and "the squad's hooks", without a number. The README's *What goes
  where* lists `.agent-squad/`'s new entries: `squad-hook`, `kept/` and `triage.since`.

## v48 — 2026-10-10
- **`--check` works on Windows with Git Bash** (#277, from #276 by @lauverrec, the first report from
  outside the squad).
  - The gate's self-test makes its lab with a plain `mkdir` under `umask 077`, where it used
    `mkdir -m 700`, whose separate mode step fails on NTFS. The lab is still closed to others
    (mode 700) on macOS and Linux.
  - `BOOTSTRAP.md` row 10 says that on Windows `CLAUDE.md` as a link needs `core.symlinks=true`
    and Developer Mode.
  - The README's *Requirements* says that macOS and Linux are tested, and Windows with Git Bash is
    best effort.
- **This repository's CI takes about half the time** (#245): about 50 s per pull request, where it
  took 100 to 120. The installer's test runs its cases side by side, and CI runs five jobs in
  parallel. Only this repository's own tests and CI change, so projects see no difference.
- No charter rule changes.

## v47 — 2026-10-06
- **The installer ends with the next steps until the squad is set up** (#271), not only on a first
  install. The CEO found the gap in a test project installed the day before and never set up: a
  rerun printed the CTO's *By hand* list and no next steps.
  - While `AGENTS.md` does not import the charter, every run ends with the next steps and prints no
    *By hand*.
  - Once it does, a run prints *By hand, for the CTO, …* and no next steps.
  - The *By hand* item about the *Squad* section is gone, since it could no longer show: `--check`
    still fails until the section is there.
  - `BOOTSTRAP.md`'s *The installer's files* and row 13 follow the rule.
- **The README's *Why agent-squad* takes the launch post's best lines** (#272): the meteorite, the
  CTO the agents needed, and agent-squad building itself.
- No charter rule changes.

## v46 — 2026-10-06
- **A simpler install, coherent with the README** (#262, #267), after the CEO's first install in a
  new project.
  - A first install ends with the next steps of *Quick start*: the three `claude -n` lines with the
    project's name, the optional `/color`, and the sentence for the CTO. It prints no *By hand*
    list: the CTO finds what is left with `--check`, as `BOOTSTRAP.md` now says.
  - A later run, a second one or an upgrade, prints *By hand, for the CTO, …* and no next steps.
  - The output is shorter, with one line each for `.gitignore`, the commands, the templates and the
    worktrees.
  - A folder name holding a `!` is printed in single quotes, so that a pasted line works.
  - *Quick start* reads like the output, and `/color` is optional there and in `BOOTSTRAP.md`.
- **The band shows ⚙️** (#264) while a session's turn has ended and a shell it started in the
  background still runs. It used to show 💤. Meanwhile the session reads messages, since no turn
  runs.
- **§3:** the installer's PR names each item the installer left to the CTO, since a first install
  prints no *By hand* list. `BOOTSTRAP.md` row 0 names *Quick start*, where it named the README's
  *Install*, a section gone since v44.
- Restart the three sessions to load the new board.

## v45 — 2026-10-05
- **agent-squad is public** (#62).
  - The README installs it with `curl`, from `raw.githubusercontent.com`.
  - *Requirements* no longer asks for access to a private repository. `gh` is still needed: the
    installer downloads the release with it.
- **A code of conduct** (#253): the Contributor Covenant 2.1, with reports through GitHub's
  *Report content*.
- **A security policy** (#255, #257): `SECURITY.md` asks for vulnerabilities to be reported in
  private, with GitHub's *Report a vulnerability*, and supports the latest release only. A release
  now carries it, so that OpenSSF Scorecard finds it.
- No charter rule changes.

## v44 — 2026-10-05
- **The band hides an idle agent's item** (#247), as the CEO chose. An idle agent (💤) shows its
  role alone, as `💤 👩🏼‍🔬QA`, with no colon. Its session keeps the item, which shows again as soon as
  the agent works.
  - ⏳, 👀, ✋, ⏸️ and ❓ show the item as before.
  - The CTO's context still shows from 90%.
- **The README's last pass before publishing** (#249), with the CEO's comments:
  - the features are shorter, and the live board says it is a Claude Code mod;
  - *Install*, which repeated *Quick start*, is gone: how to pick a release or a folder, and
    `--check`, are now in *What goes where*;
  - a new *Commands* section, before the FAQ, lists every `/squad-*` command.
- No charter rule changes. Restart the three sessions to load the new board.

## v43 — 2026-10-05
- **The band opens with the board's name and release** (#240), as the CEO asked:
  `agent-squad (v43) │ ⏳ 👷🏼‍♂️CTO: #201 │ 💤 👨🏼‍💻DEV │ 💤 👩🏼‍🔬QA: PR #239`.
  - `agent` is in the plain text colour; `-squad` and the release are in the rules' blue, as in the
    README's wordmark.
  - The release is the one the CTO's session loaded, so a session not restarted since an upgrade
    shows the previous one.
  - On a narrow terminal the prefix always shows, and the agents are cut first.
- The README says so, in *The squad board*. No charter rule changes.

## v42 — 2026-10-05
- **The band reads like the CTO's reports** (#235): the state first, then the agent, then the item,
  as `💤 👷🏼‍♂️CTO: PR #231 │ ⏳ 👨🏼‍💻DEV: #123 │ 👀 👩🏼‍🔬QA: PR #231`.
  - A colon comes only before an item, and the CTO's context, from 90%, sits before it.
  - An issue reads `#123`, and a pull request `PR #124`; the item stays white.
- **The README, finished before publishing:**
  - *Why agent-squad* is the CEO's shorter text (#232);
  - *This repository* becomes *Contributing* (#233);
  - the text example of a report goes, since the screenshot shows one (#236);
  - the squad's record goes, and becomes a *Features* line with no figures, since the PR badge
    keeps the live count (#236);
  - *Things to know* goes, and its `git clean` warning moves under *What goes where* (#236).
- No charter rule changes.

## v41 — 2026-10-05
- **The README's final review before publishing** (#200), with the CEO's seven changes. It reads
  for a first-time visitor and goes from 563 lines to 507.
  - *Features* no longer says the board shows every agent's context.
  - *The squad board* is shorter.
  - The example report has no dated versions.
  - *Install* points to *What goes where* instead of listing every file.
  - *When you step away* folds the waiting sessions into one sentence.
  - *Things to know* keeps what can hurt the CEO, and points to `BOOTSTRAP.md` row 9b and
    `SQUAD.md` for the rest.
  - The repository's file table moves to `CONTRIBUTING.md`.
  - `templates/AGENTS.md` gains the tools that need no exclusion.
- **§2.4, *Cleanup*:** `git worktree remove` refuses a worktree with modified or untracked files.
  `git -C <worktree> status` shows what is in the way, and `--force` comes only once that is
  committed or known not to be needed. This used to be in the README.
- **The board's item parser** (#225, #227): a `<<` inside quotes opens no heredoc, and shell
  comments are skipped, so neither can be read as a `gh` call.
- The squad's record is recomputed up to v41.

## v40 — 2026-10-05
- **The board shows each session's own state, not GitHub's** (#222), as the CEO asked after
  seeing v39's line live.
  - **The item:** each session's key holds the issue or PR its agent last acted on with `gh`
    (`gh issue edit|comment|view|close N`, `gh pr view|checkout|review|comment|merge|edit N`,
    `gh pr create`). It stays a link, built from the session's own remote.
  - **No GitHub, no host command:** the board no longer reads GitHub, and the mod runs no command.
    `squad-stalls.sh --current` is gone, and `check-mods.sh` refuses any host command in a mod.
  - **The marks:** QA working shows 👀, and a paused agent shows ⏸️, set by `/squad-pause` or
    `-all`, typed or relayed, and cleared by a resume or by autopilot. The CTO and DEV working
    keep ⏳.
  - **The look:** the line sits between two blue rules, with blue bars between the agents. Each
    role's name is in the colour its session takes with `/color`: CTO yellow, DEV blue, QA
    green. A mod cannot read `/color`, so the colours are fixed. They use Claude Code's
    undocumented theme keys for `/color`, with the plain colour as a fallback.
  - **Restart:** as before, a session loads the new board at its next start.
- **The README and `BOOTSTRAP.md` (row 1)** say which `/color` to give each session.
- The squad's record is recomputed up to v40.

## v39 — 2026-10-04
- **The squad board's final line** (#217), as the CEO asked after seeing v38's band:
  `👷🏼‍♂️CTO 💤 │ 👨🏼‍💻DEV ⏳ Issue #123 │ 👩🏼‍🔬QA 🔍 PR #235`, under a rule of `─`.
  - Each agent shows its signature emoji and role, then its state: ⏳ working for the CTO and DEV,
    🔍 for QA, who reviews, and ✋, 💤 and ❓ for all three.
  - The item names its kind, `Issue #N` or `PR #N`.
  - Context shows only for the CTO, and only from 90%, as `(ctx: 96%)`.
  - The cut at the end measures each emoji as two cells, so the CTO's part stays whole first.
- **The board keeps its store across upgrades** (#215). The squad's marketplace is now named
  `agent-squad-<project>-<hash>`, with no release, so an upgrade no longer moves the board to a
  new, empty store, where it showed DEV and QA as `❓` until every session had restarted.
  - The install moves the `…-v<N>` names of v37 and v38 to the new one, and keeps a plugin off
    where it was off. It leaves every other marketplace alone: one of the project's own, even named
    `agent-squad-…`, unless it points at a `.agent-squad` folder.
  - The old store files stay in `~/.claude/plugins/store/`, named
    `squad-board_agent-squad-<project>-<hash>-v<N>-<…>.json`, which can be deleted once every
    session runs v39 or later.
  - A session still loads a new release of the board at its next start: the README and
    `/squad-upgrade` say to restart the three sessions after an upgrade.
- **§7: the CEO saves state and compacts at about 90%,** not 80% (#218). On a 1M-token session,
  automatic compaction starts near 96.7%; the README says the same.
- The squad's record is recomputed up to v39.

## v38 — 2026-10-04
- **The squad board is one line above the CTO's prompt,** instead of a side pane (#212). The CEO
  chose it after seeing v37's pane take a narrow column of the CTO's session.
  - The line reads `💤 CTO 42% │ ⏳ DEV 68% #205 │ ✋ QA 33% PR #208`, in the order CTO, DEV, QA.
  - On a narrow terminal it is cut at its end, so the CTO's part always shows first.
  - An agent with no state, or a state older than three minutes, shows `❓`. When GitHub cannot be
    read, the line says so, with no links.
  - The `/squad-board` command, which only reopened the pane, is gone.
  - The states, the notices and what is read are unchanged. Sessions already running load the new
    board at their next start.
- **The installer** (#210): when a default plugin is off, it prints how to turn it back on
  (`claude plugin enable <plugin>@<marketplace> --scope local`). A test now pins that it leaves
  alone a project's own marketplace whose name starts with `agent-squad-`, as v37 already did.
- **The README:**
  - *The squad board* describes the line and how to turn the board off and on, and says that only
    the marketplaces named `agent-squad-…-v<N>` are the squad's;
  - *Features* names the line, and the FAQ lists mods among the Claude Code features the squad
    relies on, as one it can do without;
  - *What comes next?* no longer announces the board;
  - the squad's record is recomputed up to v38.

## v37 — 2026-10-04
- **The squad board** (#172, #205, #206), the squad's first Claude Code mod, shown in the CTO's
  session.
  - One line per agent of the project, in the order CTO, DEV, QA: its state (working, waiting for
    the CEO on a permission or a question, idle, or silent for a few minutes), its context use, and
    a link to the issue or PR it works on, read from GitHub every three minutes.
  - A notice in the CTO's session when DEV or QA starts to wait for the CEO, once per wait.
  - It reads GitHub with `gh` and answers no prompt; each session publishes only its own state.
- **This release enables the board in every project that installs it.**
  - The installer writes a marketplace of the project's own in `.agent-squad/`, named after the
    project and the release, whose plugin is the playbook's, and enables it in
    `.claude/settings.local.json`, for this project alone. It fetches nothing and leaves
    `~/.claude/settings.json` alone.
  - The mod runs agent-squad's code inside every squad session, under the same trust as the
    squad's hooks. The CEO's yes to `/squad-upgrade` is the consent for it, project by project.
  - `claude plugin disable squad-board@<marketplace> --scope local`, the line the installer prints,
    turns it off, and it stays off on later upgrades.
  - It needs Claude Code 2.1.287 or later. With an older one, the installer skips it, says why,
    and installs the rest.
  - Sessions already running load it at their next start.
- **`--check` has a twelfth item:** the board enabled from the playbook, with nothing of an earlier
  release left; or skipped, with the reason.
- **`scripts/squad-stalls.sh --current`** prints the issue or PR each role works on, by the rules
  the stall watch applies, for the board.
- **Smaller changes:**
  - the README names agent-squad in bold and links the tools it mentions (#204), and describes the
    board;
  - `/squad-autopilot` and `/squad-autopilot-all` have shorter descriptions (#207).

## v36 — 2026-10-04
- **The stall watch** (#174): `scripts/squad-stalls.sh` and `/squad-watch`, one pass in the CTO's
  session.
  - It finds work whose next step has waited half an hour on an idle agent, and pings the agent who
    owns that step. If nothing has moved an hour later, it tells the CEO. A session that waits in
    its own terminal, or is gone, is reported to the CEO at once.
  - Declared waits are left out: an item labelled `needs-ceo` or `⛔ status:blocked`, and a PR
    whose closing issue carries one of them.
  - A pass that finds nothing says nothing. What it reported is kept in `.agent-squad/watch.tsv`,
    so that each stall is reported once, and a `watch.tsv` that cannot be kept fails the run.
- **`/squad-away` becomes `/squad-autopilot`** (#188), and `/squad-away-all` becomes
  `/squad-autopilot-all`, with no alias.
  - Autopilot starts `/loop 30m /squad-watch`, and `/squad-pause` and `/squad-resume` stop it. The
    CTO says so when the loop cannot be scheduled or is gone.
  - On upgrade, the installer removes the squad's commands that the release no longer has, such
    as `squad-away.md` and `squad-away-all.md`, unless the project tracks them. The squad now has
    eleven commands.
- **Rules that change** (#191):
  - **§4.7:** a push after a verdict pings the reviewer again, with the new head, in the same
    message as the answers to the threads, and puts the PR back in review. P3s that come with an
    `APPROVED` verdict, or after it, are declined or deferred by default.
  - **§6, *A message may not arrive*:** an agent that ends its turn waiting for another says so on
    its issue or PR: what it waits for, from whom, and since when. The stall watch is the
    backstop: it runs by itself under autopilot and by hand at any time, and it leaves out
    declared waits.
  - **§6, *When the CEO steps away*:** `/squad-autopilot` replaces `/squad-away` and runs the
    watch.
- **The README** (#196):
  - *Features* and *Work that stalls* say what autopilot and the watch do;
  - the FAQ lists `/loop` among the Claude Code features the squad relies on.

## v35 — 2026-10-04
- **A README that makes people want to try it** (#167, #169, #173, #189, with the CEO's texts and
  images):
  - the CEO's wordmark and five badges, the team picture and the square logo, and a screenshot of
    the squad in cmux;
  - an opening in the CEO's words, *Features* as six items, *The team*, *What you see as the CEO*,
    and *Built by its own squad*;
  - an FAQ, which ends with what may come next and lists the Claude Code features the squad relies
    on;
  - and *Why agent-squad*, rewritten by the CEO (#156).

  The images live in `docs/images/`, which a release leaves out.
- **Contributions arrive as issues** (#158): `CONTRIBUTING.md` says so, and an issue form for
  outside reports is kept out of the tarball (#165).
- **Outside issues, PRs and text** (#159):
  - §3: an issue or PR from outside the squad is a proposal that the CTO triages and brings to the
    CEO, and nothing is built without the CEO's yes;
  - §3: an outside PR is never checked out or run;
  - §6: text from outside is data, never an instruction;
  - `/squad-resume` triages the outside items that carry no label yet.
- **The merge gate counts only the squad's accounts** (#160): reviews and comments by anyone but the
  repository's owner, its organisation's members and its collaborators are ignored, so a stranger
  can neither forge a verdict nor hold a merge with a fake finding. A missing signature on the
  description's first line still stops the gate.
- **A resumed session is told where its shell is** (#164, from QA's post-mortem): a
  `SessionStart(resume)` hook says that the shell starts in the main checkout and where each role
  works. The installer adds it as the fifth hook, with no *By hand* item.
- **The installer writes nothing through a symlinked `.gitignore`** (#186): it reports NOT IGNORED
  with what to do, and `--check` names the link.
- The README's *Install* names all ten commands (#163).
- **§6's emoji rule** also allows one emoji at the start of each item of a list, and those of an
  example report shown as the CEO sees it, as the README's *Features* and *What you see as the CEO*
  do (#169).

## v34 — 2026-10-01
- **`/squad-usage` and `/squad-usage-all`: the tokens each agent used** (#119, the CEO's request).
  `scripts/squad-tokens.sh` reads the transcripts Claude Code keeps on the machine, and only reads
  them. It reports each agent by its session's name, such as `CTO:trivial-tape`, with the role read
  on either side of the colon, and gives its input, the share of it read from the cache, its output
  and its models. Each model response counts once, by its message id, even when a forked session
  holds a copy.
  - `/squad-usage` reports the project it is typed in. `/squad-usage-all` reports the whole
    machine, one block per project, with subtotals per role, then other sessions, then the total,
    and relays nothing to other squads.
  - Both cover the whole history by default, and take `Nd` or a date for a period. Any session of
    the squad may run them.
  - Each run merges per-day figures into `.agent-squad/tokens.tsv`, so that they outlive Claude
    Code's cleanup of transcripts about 30 days after a session's last use.
  - A change in the transcripts' format stops the script, and is never counted as zero.

  The installer now requires ten commands, so upgrading writes the two new ones. The README has a
  section on it, *How many tokens the agents use*.
- §6: **a report of the agents' state gives one line per agent** (#130, defined with the CEO):
  - the lines go in the order CTO, DEV, QA, in the third person, the CTO's included;
  - each line starts with an emoji for one of five states: working, paused, free, waiting for the
    CEO in its terminal, or no answer;
  - every update repeats the same lines, with a closing line on where things stand, and several
    squads give one block each;
  - it holds for the six step-away commands, which now apply it, and for any status given on
    request. The README says so in *When you step away*.

## v33 — 2026-10-01
- **The merge gate keys body-only findings on the reviewer** (#150, found by rogue-trader's QA): on
  a PR that QA authors, DEV reviews, so the gate reads the author from the first line of the PR's
  description and takes as findings the comments signed by the reviewer, DEV there and QA
  otherwise. QA's answers on its own PR no longer read as findings, and DEV's findings there now
  hold the merge. A description with no signature on its first line makes the gate refuse. §4.8
  and §4.9 say "the reviewer".
- §4.9: **after the merge, the author checks that the issue closed** (#127), and closes it with a
  comment naming the PR if it did not. A PR's closing link, read through the API before the merge,
  proves nothing: on two repositories it filled in only some time after the merge. So the gate
  does not check it.

## v32 — 2026-09-30
- **The pre-push gate lets through a tag of a past release** (#143, found by trivial-tape's CTO): a
  pushed ref whose commit one of the remote's branches already contains carries no new code, so it
  need not be the checked-out commit, and a push made only of such refs and deletions runs no
  checks. The remote's branches are listed at the push (`git ls-remote --heads`), so a stale
  remote-tracking ref cannot vouch for a commit the remote dropped. As soon as one ref carries a
  new commit, everything runs as before, and only a PR changes the protected branch, whatever the
  commit. §4.2 and `AGENTS.md` say so. The new gate reaches a project when it installs v32.
- §4.9: **the cleanup after a merge is chained to it with `&&`** (#144, found and fixed by
  trivial-tape's DEV): a cleanup chained with `;` ran after the gate had stopped a merge, deleted
  the head branch, and GitHub closed the PR.
- The README drops its notes for releases older than v31 (#145): every project upgrades with
  `/squad-upgrade`.

## v31 — 2026-09-30
- **Step-away commands reach a session that is waiting for the CEO** (#139). A session that the
  list of sessions shows as waiting is held by a question or a permission prompt in its own
  terminal, and reads no message until the CEO answers it there. The CTO now names it to the CEO.
  When another squad's CTO is waiting, the `-all` commands send the command both to it, for when
  the CEO has answered, and straight to that squad's DEV and QA. Every relayed step-away message
  gives the time it was sent, and an agent that reads it more than ten minutes later asks the
  sender whether it still holds before acting. Found by the CEO during a `/squad-pause-all`, whose
  pause one squad read only after the CEO was back. §6 and the README (*When you step away*)
  describe it.
- **No `/compact` in every session after an upgrade** (#140): `/squad-upgrade` has DEV and QA
  re-read the sections that changed, taking them as superseding what their session loaded, and
  tells the CEO that nothing else is needed; it recommends `/squad-save-state` and `/compact` only
  after a release that rewrites much of the charter. §7 and the README (*Upgrade*) say the same.

## v30 — 2026-09-30
- **The README at the user's level** (#137), after the CEO's review of v28 and v29: `/squad-upgrade`
  has a section of its own, *Upgrade*, next to *Install*, and *When you step away* says what the
  CEO types and gets back, in a table with one emoji per command, with the `-all` commands in one
  paragraph. The agents' inner steps stay in the charter and the commands. §6 allows that emoji: one
  per row of a table of commands, in the command's cell.
- **`/squad-pause` is a safe point for any reason** (#137): to close the laptop, to use the
  machine for something else, or anything else. §6, the README and the `/squad-pause` and
  `/squad-pause-all` commands say so, and the agents report "at a safe point" instead of "safe to
  close".

## v29 — 2026-09-30
- **Step-away commands for every squad on the machine** (#117): `/squad-pause-all`,
  `/squad-away-all` and `/squad-resume-all`, next to the single-squad commands, which do not
  change. Typed in any squad's CTO session, the command is run for that squad and relayed to every
  other squad's CTO, or to the DEV and QA of a squad with no CTO session, and the CEO gets one
  answer grouped by squad. `/squad-away-all` keeps one `caffeinate` for the machine. The other
  squads need only the single-squad commands (v26 or later), and a project that runs no squad is
  told what to do without them. Tried at the CEO's real absences with four projects open. §6 and
  the README (*When you step away*) describe them.
- **`/squad-resume` ends with the plan ahead** (#131): the release in progress step by step, the
  next one, what waits for a decision, and what the CEO will be asked next.
- **The pre-compact gate no longer stops every interactive `/compact`** (#134): the interactive CLI
  writes a plain `/compact` entry before the command's markup, and the gate now skips it, so a
  `/compact` right after `/squad-save-state` goes through.

## v28 — 2026-09-30
- **`/squad-upgrade`** (#118): typed by the CEO in the CTO's session, it has the CTO say which
  version the project runs and which is the latest, summarise what the releases in between change
  (rules, what the project must commit, whether the sessions should be compacted to load new
  rules), and **ask the CEO before installing**. On a yes, it installs with `install.sh`, reading
  the whole output and exit status, runs `--check`, commits the *By hand* items through the
  installer's PR, tells DEV and QA, and reports. Installed like the other commands; a project on a
  release older than v28 upgrades by hand that once. §7 and the README (*Install*) describe it.
- §6: **DEV and QA ask the CEO only through GitHub and the CTO** (#128). They never ask the CEO in
  their own session, nor wait there: a question for the CEO is written on its issue or PR as
  options with a recommendation, labelled `needs-ceo`, and the CTO brings it to the CEO; the CTO
  flags an agent that stays busy with no sign of life. §7 records a memory note that kept a
  superseded rule alive.

## v27 — 2026-09-30
- **Git LFS runs its pre-push hook from `pre-push.local`** (#121). The squad's shim owns
  `.git/hooks/pre-push`, so `git lfs install` cannot add LFS's hook there, and a push would send
  pointers without their files. A project that uses LFS puts `git lfs pre-push "$@"` in an
  executable `.git/hooks/pre-push.local`, which the shim runs first; one that had LFS's hook before
  the install already has it there. Files pushed before the hook was in place reached the remote
  as pointers, and `git lfs push --all origin` uploads what it lacks. `--check` shows an item for it only when a `.gitattributes` of
  the project, at the root or tracked below it, has `filter=lfs` outside a comment, and names the
  fix when it fails.
  The README's *Things to know* and `BOOTSTRAP.md` row 9b say so.

## v26 — 2026-09-30
- **When the CEO steps away** (#101): `/squad-pause` gets each agent to a safe point before the
  laptop closes, `/squad-away` has the squad go on with what needs no decision while the machine
  stays on (macOS kept awake with `caffeinate` while work remains), and `/squad-resume` gives the
  CEO one summary on return. The CEO types them in the CTO's session, which relays them, or in one
  agent's session for that agent alone. The installer writes them into `.claude/commands/` like
  `/squad-save-state`, and one `.gitignore` rule, `.claude/commands/squad-*.md`, covers the four.
  `--check` verifies them. The commands were tried at the CEO's real absences before this tag.
  §6 and the README (*When you step away*) describe them. The `needs-ceo` recipe lists every open
  issue (`--limit 1000`), not the first 30 (§3).
- **Worktree exclusions anchored at the project root** (#120): the Metro setting of v24 was
  unanchored and, inside a worktree, excluded the worktree's own files; `templates/AGENTS.md` now
  anchors it, and Watchman gets no `ignore_dirs` for `.agent-squad`, since a worktree's watch
  reuses the main checkout's (§2.4, README).
- **Signatures in bold** (#111): everywhere a signature is written, `**👷🏼‍♂️[CTO]:**`; the merge
  gate recognises a body-only finding whether its signature is bold or plain.

## v25 — 2026-09-29
- §3: **a PR or an issue carries no more than one state label** (#99). Whoever sets a state label removes the
  other two in the same command, never listing the label it adds among those it removes: when one
  `gh pr edit` adds and removes the same label, the removal wins and the PR is left with none. The
  merge gate refuses a PR that carries more than one of the three state labels, naming them (§4.9).
  Twice in one day a PR carried two states, each side having removed only the label it had added.
- **The installer leaves a project-tracked `.claude/commands/squad-save-state.md` alone** (#104).
  A file the project tracks at that path is the project's: the install marks the step NOT and
  exits 1, as it does for any step that needs a decision (a `core.hooksPath`, for instance), and
  `--check`'s command item fails on it.
  Both say which way out fits: rename a command of the project's own, since untracking it would
  have the next install overwrite it; untrack the squad's command committed by mistake.
- §3: **the PR that commits the installer's files needs no issue of its own** (#107), at the first
  install and at every upgrade that changes a tracked file, such as a new `.gitignore` line. It is
  §3's second exception to "every PR closes an issue": its content was decided and reviewed
  upstream, in the release it installs; its description names that release and each *By hand*
  item it records, and QA checks that it commits exactly what the installer wrote. `BOOTSTRAP.md`,
  *The installer's files*, says the same, and the README says that such an upgrade lists the file
  under *By hand* and the CTO commits it through a pull request.

## v24 — 2026-09-29
- **`/squad-save-state` before a compaction** (#100): a command, which the installer writes into
  `.claude/commands/` and git-ignores and which `--check` verifies (11 items now), has the agent
  record on GitHub the decisions not there yet, write its exact state on its issue, and tell the
  CEO it is ready. The pre-compact hook stops a manual `/compact` that does not come right after
  it and lets a second one through within ten minutes; it never stops an automatic compaction, and
  lets a compaction through when it cannot read the transcript. §7's third defence and
  `BOOTSTRAP.md` row 10b say so, and the README explains compaction in *When a session's context
  fills up*.
- **Tools that walk the worktrees** (#98): Jest, Metro and Watchman walk into
  `.agent-squad/worktrees/` by default. §2.4 and the README say so, `BOOTSTRAP.md` row 9b checks
  that the project's test runner collects nothing there, and `templates/AGENTS.md` has the
  settings that exclude it.

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
