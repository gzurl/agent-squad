---
description: The CEO is away and the machine stays on; every squad on it carries on with what needs no decision (agent-squad)
---
The CEO is away and leaves the machine on, for every squad open on it. It may still sleep:
closing a MacBook's lid sleeps it whatever runs. Your role is your session name. The squad's
commands are in the main checkout's `.claude/commands/`, not in the worktrees.

## If you are DEV or QA
Follow the part for every agent in `squad-away.md`, for yourself alone, as `/squad-away` would.

## If you are the CTO
1. **Your own squad:** do what `/squad-away` has the CTO do (`squad-away.md`, its CTO part),
   except when to stop the `caffeinate` it starts: that one keeps the machine awake for every
   squad, and step 3 says when it stops.
2. **The other squads:** list the sessions open on this machine (`ListAgents`). Their names read
   `ROLE:<project-name>`: group them by project, leaving yours out. Send each other squad's CTO
   one message: "The CEO is away and the machine stays on (`/squad-away-all`): run
   `/squad-away`'s CTO part for your squad, from `squad-away.md` in your main checkout's
   `.claude/commands/`, except its `caffeinate` step: I keep the machine awake for every squad.
   Tell me when your squad has nothing left that needs no decision." For a squad with no CTO
   session open, send its DEV and QA one message each: "The CEO is away and the machine stays on
   (`/squad-away-all`): follow the part for every agent in `squad-away.md`, in your main
   checkout's `.claude/commands/`, and tell me when you have nothing left that needs no decision.
   If there is no such file, your project runs no squad: go on with what needs no decision, save
   your work as you go, and tell me when nothing is left."
   Every message you send for this command ends with "Sent at <time>; if you read this more than
   10 minutes later, ask me whether it still holds before acting.", where `<time>` is
   `date '+%Y-%m-%d %H:%M'` when you send it.
   A squad whose CTO session `ListAgents` shows as **waiting** gets both messages: its CTO the
   one above, and its DEV and QA the one for a squad with no CTO session. That CTO is held by a
   question or a permission prompt in its own terminal, and reads your message only once the CEO
   answers it there; its sent time then tells it to check with you first.
3. **Keep the `caffeinate` running** while any squad still has work, and stop it (`kill <PID>`)
   when every squad has said it has nothing left, and at `/squad-resume-all`. Name to the CEO, on
   return, any squad whose CTO or agents answered that their main checkout has no `squad-away.md`
   (a release older than v26, or a project that runs no squad), or that did not answer, and any
   session shown as waiting, since only the CEO can answer it.
