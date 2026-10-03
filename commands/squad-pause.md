---
description: The CEO needs the squad stopped at a safe point (agent-squad)
---
The CEO needs the squad stopped at a safe point: to close the laptop, to use the machine for
something else, or for any other reason. Act as if everything on this machine were about to
stop: running commands, long runs, messages in flight. Get to a safe point now. Your role is your
session name. The squad's commands are in the main checkout's `.claude/commands/`, not in the
worktrees.

## If you are the CTO
1. Send DEV and QA one message each: "The CEO needs the squad stopped at a safe point
   (`/squad-pause`): follow the part for every agent in `squad-pause.md`, in the main checkout's
   `.claude/commands/`, now, and tell me how long you still need." Then do that part yourself.
   Every message you send for this command ends with "Sent at <time>; if you read this more than
   10 minutes later, ask me whether it still holds before acting.", where `<time>` is
   `date '+%Y-%m-%d %H:%M'` when you send it.
   A session that `ListAgents` shows as **waiting** is held by a question or a permission prompt
   in its own terminal and reads no message until the CEO answers it there: name it to the CEO.
   Stop the stall watch, if it runs: delete the scheduled job that `/loop 30m /squad-watch` made
   (`CronList` shows it, `CronDelete` removes it).
2. Report to the CEO in §6's agent lines (one per agent, in the order CTO, DEV, QA, with its state
   emoji), in the CEO's language (`AGENTS.md`, *Language*): how long each of the three still needs,
   from their answers, and where each one's state is. Repeat the same lines in every update.
3. Close with "the three are at a safe point" only when each agent has saved its state on
   GitHub, on its issue or on the PR it is reviewing, or has said that it works on neither (check
   GitHub, not the reply alone), and its session shows as idle (`ListAgents`). If an agent has not
   answered after a few minutes (❓), or its session is still busy, or it waits for the CEO (✋),
   say on its line what the CEO can do: wait, look at that session, or go ahead anyway, knowing
   what it was doing.

## For every agent (and, typed in DEV's or QA's session, for that agent alone)
1. **The step in hand:** finish it if it is short (a push, a merge, a comment, a short test run).
   Do not start a long one (a benchmark, a long test run); stop one that is running, cleanly, and
   note on its issue where it stopped and how to restart it.
2. **A review left halfway:** note on its PR what was checked and what is left.
3. **Nothing in the background:** stop what you started and left running (a server, a watcher, a
   command sent to the background), and check with `ps` that none of it is left.
4. **Your state:** save it on your issue, or on the PR you are reviewing, as `/squad-save-state`
   does (`squad-save-state.md`, steps 1 to 3), and check that it was posted. If you work on
   neither, say so in your one line below.
5. **Stop:** start nothing new until `/squad-resume`, or until the CEO says otherwise. Say
   "at a safe point" in one line: to the CTO by message when the CTO relayed this, or to the CEO,
   in the CEO's language, when the CEO typed it in your session.
