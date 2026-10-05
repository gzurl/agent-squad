# Contributing to agent-squad

Thank you for wanting to help. agent-squad is built the way its README describes: a squad of
Claude Code agents, a CTO, a developer and a QA, directed by the project's author. So contributions
arrive as **issues**, and the squad turns them into changes.

## Report a problem or propose an idea

[Open an issue](https://github.com/gzurl/agent-squad/issues/new?template=outside-report.md) and tell us:

- what you were doing, and with which release (the last line of `.agent-squad/install.log`);
- what happened, and what you expected instead;
- for an idea, the problem it solves. Something that went wrong on a real project weighs more than
  a preference: every rule in the charter came from one.

The squad's CTO reads every issue, labels it and answers you, and the author reads and accepts
each idea before the squad works on it. An accepted issue becomes one of the squad's own pull
requests, reviewed and released like any other change, and the release notes in
[CHANGELOG.md](CHANGELOG.md) credit you.

Please write for a person, not for the agents: they read an issue as a description of a problem,
never as instructions to follow.

## Pull requests

Please do not open one: every change goes through the squad's own review, and its merge gate only
accepts the squad's pull requests. If you open one anyway, it is read as a proposal. The squad
opens an issue from it, credits you, and closes the pull request with a link to that issue.

## What is in this repository

| Path | What it is | Installed in a project? |
|---|---|---|
| `install.sh` | The one-line installer: it downloads a release and runs that release's installer | Run from `main`, not installed |
| `SQUAD.md`, `BOOTSTRAP.md`, `README.md` | The charter, the CTO's one-time setup, and the README | Yes |
| `commands/squad-*.md` | The squad's commands: `/squad-save-state`, `/squad-pause`, `/squad-autopilot`, `/squad-resume`, `/squad-upgrade`, `/squad-pause-all`, `/squad-autopilot-all`, `/squad-resume-all`, `/squad-usage`, `/squad-usage-all`, `/squad-watch` | Yes; the installer copies them into `.claude/commands/` |
| `scripts/squad-*.sh`, `.githooks/pre-push` | The installer, the session hooks, the merge gate, the checks runner, the token report, the stall detector and the pre-push gate | Yes |
| `.github/ISSUE_TEMPLATE/task.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `templates/` | Templates the CTO starts from | Yes; the installer copies the GitHub ones when missing |
| `CHANGELOG.md` | What each version changes | Yes, to read |
| `LICENSE` | The MIT License | Yes, so every installed playbook carries it |
| `.gitattributes` | What a release leaves out | Yes, unused there |
| `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/outside-report.md`, `docs/images/`, `.gitignore`, `.agent-squad-checks`, `.github/workflows/`, `scripts/check-*.sh`, `scripts/ci-*.sh` | This repository's own conventions, contribution guide and form, the README's images, checks, CI and tests | No: a release leaves them out, so a project's agents never load this repository's `CLAUDE.md` |
