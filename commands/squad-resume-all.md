---
description: The CEO is back; every squad on this machine resumes and reports (agent-squad)
---
The CEO is back, for every squad open on this machine. Your role is your session name. The
squad's commands are in the main checkout's `.claude/commands/`, not in the worktrees.

## If you are DEV or QA
Follow the part for every agent in `squad-resume.md`, for yourself alone, as `/squad-resume`
would.

## If you are the CTO
1. **Your own squad:** do what `/squad-resume` has the CTO do (`squad-resume.md`, its CTO part),
   which stops the `caffeinate` you started for `/squad-away-all`, if it still runs, and gathers
   your squad's summary. Hold that summary for step 3.
2. **The other squads:** list the sessions open on this machine (`ListAgents`), grouped by
   project, leaving yours out. Send each other squad's CTO one message: "The CEO is back
   (`/squad-resume-all`): run `/squad-resume`'s CTO part for your squad, from `squad-resume.md` in
   your main checkout's `.claude/commands/`, and send me, instead of the CEO, the summary it
   gives." For a squad with no CTO session open, send its DEV and QA one message each: "The CEO
   is back (`/squad-resume-all`): follow the part for every agent in `squad-resume.md`, in your
   main checkout's `.claude/commands/`, and send me your summary. If there is no such file, your
   project runs no squad: send me what you did while the CEO was away and what you do now, in
   three lines at most."
   Every message you send for this command ends with "Sent at <time>; if you read this more than
   10 minutes later, ask me whether it still holds before acting.", where `<time>` is
   `date '+%Y-%m-%d %H:%M'` when you send it.
   A squad whose CTO session `ListAgents` shows as **waiting** counts as a squad with no CTO
   session: that CTO is held by a question or a permission prompt in its own terminal, and would
   read your message only after the CEO answers it there.
3. **Give the CEO one summary, grouped by squad**, in the CEO's language (`AGENTS.md`,
   *Language*): for each squad, what its agents did while the CEO was away, what was merged or
   released, and what waits for the CEO (its open `needs-ceo` issues, each linked), then its plan
   ahead, as `/squad-resume`'s step 4 says (now, next, later, what the CEO will be asked next).
   Each other squad's CTO sends its own plan with its summary; a squad with no CTO session has no
   plan to report, so say so for it. Name any squad that did not answer, with what its sessions
   are doing, and any session shown as waiting, since only the CEO can answer it.
