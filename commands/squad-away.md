---
description: The CEO is away and the machine stays on; carry on with what needs no decision (agent-squad)
---
The CEO is away and leaves the machine on. It may still sleep: closing a MacBook's lid sleeps it
whatever runs. Carry on with the work that needs no decision from the CEO. Your role is your
session name. The squad's commands are in the main checkout's `.claude/commands/`, not in the
worktrees.

## If you are the CTO
1. Send DEV and QA one message each: "The CEO is away and the machine stays on (`/squad-away`):
   follow the part for every agent in `squad-away.md`, in the main checkout's `.claude/commands/`,
   and tell me when you have nothing left that needs no decision." Then do that part yourself.
   Every message you send for this command ends with "Sent at <time>; if you read this more than
   10 minutes later, ask me whether it still holds before acting.", where `<time>` is
   `date '+%Y-%m-%d %H:%M'` when you send it.
   A session that `ListAgents` shows as **waiting** is held by a question or a permission prompt
   in its own terminal and reads no message until the CEO answers it there: name it to the CEO.
2. While any agent still has work, keep macOS awake: start `caffeinate -i -t 43200` in the
   background on purpose (§2.4 allows it; the 12-hour limit ends a forgotten one by itself), and
   note its PID on your issue. Stop it with `kill <PID>` when every agent has said it has nothing
   left, and at `/squad-resume`.
3. Report to the CEO in §6's agent lines (one per agent, in the order CTO, DEV, QA, with its state
   emoji), in the CEO's language (`AGENTS.md`, *Language*): what each goes on with (⏳), or that it
   has nothing left (💤). Repeat the same lines when one changes.

## For every agent (and, typed in DEV's or QA's session, for that agent alone)
1. **Go on** with the work that needs no decision from the CEO.
2. **A decision for the CEO:** write it on its issue as options with a recommendation, label the
   issue `👨🏻‍💼 needs-ceo`, and go on with something else. Leave no question pending in the
   conversation: the CEO will read GitHub, not this session.
3. **Your state after every step:** save it on your issue, or on the PR you are reviewing, as
   `/squad-save-state` does (`squad-save-state.md`, steps 1 to 3), so that the work survives a
   sleep at any moment. If you work on neither, there is nothing to save until you take something.
4. **No notifications:** do not try to reach the CEO outside GitHub and this session.
5. **When nothing is left** that needs no decision: say so in one line, to the CTO by message when
   the CTO relayed this, and wait.
