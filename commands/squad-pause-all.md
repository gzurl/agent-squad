---
description: The CEO is closing the laptop; get every squad on this machine to a safe point (agent-squad)
---
The CEO is about to close the laptop, and every squad open on this machine stops with it. Your
role is your session name. The squad's commands are in the main checkout's `.claude/commands/`,
not in the worktrees.

## If you are DEV or QA
Follow the part for every agent in `squad-pause.md`, for yourself alone, as `/squad-pause` would.

## If you are the CTO
1. **Your own squad:** do what `/squad-pause` has the CTO do (`squad-pause.md`, its CTO part), and
   hold what it would tell the CEO for step 3.
2. **The other squads:** list the sessions open on this machine (`ListAgents`). Their names read
   `ROLE:<project-name>`: group them by project, leaving yours out. Send each other squad's CTO
   one message: "The CEO is closing the laptop (`/squad-pause-all`): run `/squad-pause`'s CTO part
   for your squad, from `squad-pause.md` in your main checkout's `.claude/commands/`, and tell me,
   instead of the CEO, how long your squad needs and when it is safe to close." For a squad with no
   CTO session open, send its DEV and QA one message each: "The CEO is closing the laptop
   (`/squad-pause-all`): follow the part for every agent in `squad-pause.md`, in your main
   checkout's `.claude/commands/`, and tell me when you are safe to close."
3. **Answer the CEO once, grouped by squad**, in the CEO's language (`AGENTS.md`, *Language*): how
   long each squad still needs, from its CTO's report or its agents'. Say "all N squads are safe
   to close" only when each squad has reported safe and `ListAgents` shows its sessions idle.
   Name any squad that did not answer after a few minutes, or whose main checkout has no
   `squad-pause.md` (a release older than v26), with what its sessions were doing (busy or idle)
   and what the CEO can do: wait, look at those sessions, or close anyway.
