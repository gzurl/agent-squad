---
description: Report the tokens this project's agents have used, per agent (agent-squad)
argument-hint: "[Nd | YYYY-MM-DD]"
---
The CEO wants to know how many tokens this project's agents have used. Your role is your session
name.

1. **The period.** What the CEO typed after the command is: `$ARGUMENTS`.
   - Nothing: the whole history.
   - `Nd`, such as `30d`: the last N days, today included.
   - A date, `YYYY-MM-DD`, with or without `since` before it: from that day on.

   Anything else: tell the CEO, in one line and in the CEO's language (`AGENTS.md`, *Language*),
   which forms the command takes, and stop.
2. **Run the report** from where you are, with `--since <period>` only when the CEO gave one (the
   `Nd` or the date, without `since`):
   `"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-tokens.sh" --since <period>`.
   It reads the transcripts of the sessions launched from the project's main checkout, adds them to
   the history in `.agent-squad/tokens.tsv`, and prints the report. Read its exit status.
   - **1:** a transcript or the history could not be read, which is how a change in Claude Code's
     format shows. Give the CEO the script's message as it is, and say that nothing was counted.
   - **2:** it was not run from a checkout of a project the squad is installed in. Say so.
3. **Give the CEO the report**, in the CEO's language: the period it covers, then a table with one
   row per agent (CTO, DEV, QA, then any session without a role), its responses, input, the share
   of input read from the cache, output and models, and the project's total. Keep the script's
   figures as they are; translate only the labels. End with one line: tokens are not cost, and
   input read from the cache is billed far below fresh input.
