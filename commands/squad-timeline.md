---
description: Show where the time of a release went, issue by issue (agent-squad)
argument-hint: "[vN]"
---
The CEO wants to see where the time of a release went (agent-squad #574): for each of its issues,
how long it took before its PR, how long the PR waited for QA, was being fixed and waited for its
merge, and how many review rounds and findings it had. Your role is your session name.

1. **The milestone.** What the CEO typed after the command is: `$ARGUMENTS`.
   - Nothing: the release in progress, the milestone of each open plan issue, or with none, the
     milestone closed last.
   - A milestone's title, or its first word, such as `v76`.
2. **Run the timeline** from where you are, with the milestone only when the CEO gave one:
   `"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-timeline.sh" <milestone>`.
   It reads everything from GitHub and changes nothing. Read its exit status before its output.
   - **1:** GitHub could not be read, so nothing was measured. Give the CEO the script's message
     in one line.
   - **2:** no milestone has that title, several titles start with it, or the command was not run
     from a checkout of the project. Give the CEO the script's message, and stop.
3. **Show the CEO each table**, in the CEO's language (`AGENTS.md`, *Language*). Keep the
   milestone's title and the column headers in English, as the script prints them, and write the
   rest in the CEO's language: the title line's count and time, the total row's label, the line
   under the table and each note. Keep every figure as the script gives it. Always show the line
   under the table, that the times are wall-clock and not effort: the CEO asked to see it. Posted
   on GitHub, as on a plan issue, the table stays in English, as the script prints it.
