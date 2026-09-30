---
description: The CEO is away and the machine stays on; every squad on it carries on with what needs no decision (agent-squad)
---
The CEO is away and leaves the machine on, for every squad open on it. It may still sleep:
closing a MacBook's lid sleeps it whatever runs. Your role is your session name. The squad's
commands are in the main checkout's `.claude/commands/`, not in the worktrees.

## If you are DEV or QA
Follow the part for every agent in `squad-away.md`, for yourself alone, as `/squad-away` would.

## If you are the CTO
1. **Your own squad:** do what `/squad-away` has the CTO do (`squad-away.md`, its CTO part). You
   keep the machine awake for every squad, with the one `caffeinate` it starts.
2. **The other squads:** list the sessions open on this machine (`ListAgents`). Their names read
   `ROLE:<project-name>`: group them by project, leaving yours out. Send each other squad's CTO
   one message: "The CEO is away and the machine stays on (`/squad-away-all`): run
   `/squad-away`'s CTO part for your squad, from `squad-away.md` in your main checkout's
   `.claude/commands/`, except its `caffeinate` step: I keep the machine awake for every squad.
   Tell me when your squad has nothing left that needs no decision." For a squad with no CTO
   session open, send its DEV and QA one message each: "The CEO is away and the machine stays on
   (`/squad-away-all`): follow the part for every agent in `squad-away.md`, in your main
   checkout's `.claude/commands/`, and tell me when you have nothing left that needs no decision."
3. **Keep the `caffeinate` running** while any squad still has work, and stop it (`kill <PID>`)
   when every squad has said it has nothing left, and at `/squad-resume-all`. Name to the CEO, on
   return, any squad whose main checkout has no `squad-away.md` (a release older than v26).
