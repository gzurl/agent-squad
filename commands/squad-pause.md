---
description: The CEO is closing the laptop; get the squad to a safe point (agent-squad)
---
The CEO is about to close the laptop. Everything on this machine will stop: running commands,
long runs, messages in flight. Get to a safe point now. Your role is your session name.

## If you are the CTO
1. Send DEV and QA one message each: "The CEO is closing the laptop (`/squad-pause`): follow the
   part for every agent in `.claude/commands/squad-pause.md` now, and tell me how long you still
   need." Then do that part yourself.
2. Tell the CEO, in one line and in the CEO's language (`AGENTS.md`, *Language*), how long each of
   the three still needs, from their answers.
3. Tell the CEO that all three are safe to close only when each agent has posted its state on its
   issue (check GitHub, not the reply alone) and its session shows as idle (`ListAgents`). If an
   agent has not answered after a few minutes, or its session is still busy, name it and say what
   the CEO can do: wait, look at that session, or close anyway, knowing what it was doing.

## For every agent (and, typed in DEV's or QA's session, for that agent alone)
1. **The step in hand:** finish it if it is short (a push, a merge, a comment, a short test run).
   Do not start a long one (a benchmark, a long test run); stop one that is running, cleanly, and
   note on its issue where it stopped and how to restart it.
2. **A review left halfway:** note on its PR what was checked and what is left.
3. **Nothing in the background:** stop what you started and left running (a server, a watcher, a
   command sent to the background), and check with `ps` that none of it is left.
4. **Your state:** save it on your issue, as `/squad-save-state` does
   (`.claude/commands/squad-save-state.md`, steps 1 to 3), and check that it was posted.
5. **Stop:** start nothing new until `/squad-resume`, or until the CEO says otherwise. Say
   "safe to close" in one line: to the CTO by message when the CTO relayed this, or to the CEO,
   in the CEO's language, when the CEO typed it in your session.
