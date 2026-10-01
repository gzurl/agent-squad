---
description: The CEO needs every squad on this machine stopped at a safe point (agent-squad)
---
The CEO needs every squad open on this machine stopped at a safe point, whatever the reason. Your
role is your session name. The squad's commands are in the main checkout's `.claude/commands/`,
not in the worktrees.

## If you are DEV or QA
Follow the part for every agent in `squad-pause.md`, for yourself alone, as `/squad-pause` would.

## If you are the CTO
1. **Your own squad:** do what `/squad-pause` has the CTO do (`squad-pause.md`, its CTO part), and
   hold what it would tell the CEO for step 3.
2. **The other squads:** list the sessions open on this machine (`ListAgents`). Their names read
   `ROLE:<project-name>`: group them by project, leaving yours out. Send each other squad's CTO
   one message: "The CEO needs every squad stopped at a safe point (`/squad-pause-all`): run
   `/squad-pause`'s CTO part for your squad, from `squad-pause.md` in your main checkout's
   `.claude/commands/`, and tell me, instead of the CEO, how long your squad needs and when it is
   at a safe point." For a squad with no CTO session open, send its DEV and QA one message each:
   "The CEO needs every squad stopped at a safe point (`/squad-pause-all`): follow the part for
   every agent in `squad-pause.md`, in your main checkout's `.claude/commands/`, and tell me when
   you are at a safe point. If there is no such file, your project runs no squad: get to a safe
   point your own way (nothing half-done, nothing running in the background, your work saved) and
   tell me what you did."
   Every message you send for this command ends with "Sent at <time>; if you read this more than
   10 minutes later, ask me whether it still holds before acting.", where `<time>` is
   `date '+%Y-%m-%d %H:%M'` when you send it.
   A squad whose CTO session `ListAgents` shows as **waiting** gets both messages: its CTO the
   one above, and its DEV and QA the one for a squad with no CTO session. That CTO is held by a
   question or a permission prompt in its own terminal, and reads your message only once the CEO
   answers it there; its sent time then tells it to check with you first.
3. **Answer the CEO once, grouped by squad**, in the CEO's language (`AGENTS.md`, *Language*): each
   squad as a block of §6's agent lines (one per agent, in the order CTO, DEV, QA, with its state
   emoji), from its CTO's report or its agents', with how long each still needs. Close with "all N
   squads are at a safe point" only when each squad has reported safe and `ListAgents` shows its
   sessions idle, and otherwise with how many are and what is missing. Name any session shown as
   waiting: only the CEO can answer it, in its own terminal. Name any squad that did not answer
   after a few minutes, or whose CTO or agents answered that their main checkout has no
   `squad-pause.md` (a release older than v26, or a project that runs no squad, whose agents say
   what they did instead): you cannot see other squads' checkouts, since `ListAgents` gives no
   paths. Say what its sessions were doing (busy or idle) and what the CEO can do: wait, look at
   those sessions, or go ahead anyway.
