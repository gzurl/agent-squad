# Changelog

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
