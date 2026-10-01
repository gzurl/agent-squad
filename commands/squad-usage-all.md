---
description: Report the tokens every agent on this machine has used, by project; it relays nothing (agent-squad)
argument-hint: "[Nd | YYYY-MM-DD]"
---
The CEO wants to know how many tokens the agents of every project on this machine have used.
Your role is your session name. Unlike the other `-all` commands, this one relays nothing to the
other squads: the script reads every session's transcript on the machine directly.

Follow `squad-usage.md`, in the main checkout's `.claude/commands/`, with two differences:
- **In step 2,** add `--all`, and the script reports every project on the machine.
- **In step 3,** the report has one block per project, each with its agents in the order CTO, DEV,
  QA and its subtotal. Then come the subtotals per role across all projects, the sessions whose
  names carry no role ("other sessions"), and the total. Give the CEO the same blocks, in that
  order.
