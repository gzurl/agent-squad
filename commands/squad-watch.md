---
description: One pass of the stall watch; pings whoever owns stalled work, silent when there is none (agent-squad)
---
One pass of the squad's stall watch (agent-squad #174). Work stalls when the agent who owns its
next step is idle, and nothing will wake it: a ping that never arrived, or a next step announced
and never taken. Your role is your session name.

## If you are DEV or QA
This command is the CTO's. If the CEO typed it in your session, tell the CEO, in one line and in
the CEO's language (`AGENTS.md`, *Language*), to type `/squad-watch` in the CTO's session. Do
nothing else.

## If you are the CTO
1. **The sessions.** List the sessions open on this machine (`ListAgents`) and find your squad's
   three, named after your project: `CTO:<project>` or `<project>:CTO`, and the same for DEV and
   QA. Note each one's state: busy, idle, or waiting (on a question or a permission in its own
   terminal). Count your own session as idle, since all it does is this pass.
2. **The detector.** Run, from the main checkout, with `--session` only for the sessions that are
   open:
   `"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-stalls.sh" --session CTO=idle --session DEV=<state> --session QA=<state>`.
   Read its exit status before its output.
   - **1:** GitHub could not be read, so nothing was checked. Tell the CEO in one line, with the
     script's message. A watch that cannot see must not pass for a clear one.
   - **2:** it was not run from a checkout of a project the squad is installed in. Say so.
3. **Each line that starts with `ping`** names the role that owns a stalled item's next step,
   then the item, its URL, the step, and since when it has been quiet.
   - **DEV or QA:** send that session one message, in English: "**👷🏼‍♂️[CTO]:** ⏳ Your next step on
     <item> (<URL>) is to <step>, quiet since <since>: carry on, or say on it what you are waiting
     for, and from whom."
   - **You:** take the step now.
4. **Each line that starts with `ceo`** is for the CEO, in the CEO's language: the item, linked;
   whose step it is; the step; since when; and why it comes to the CEO, which is the line's last
   column. Then say what the CEO can do:
   - for a session waiting in its own terminal: answer it there;
   - for a role with no session open: open it;
   - for a ping an hour old with nothing since: look at that session, or tell its agent what to
     do.
5. **When the detector prints nothing,** send nothing to anyone, and tell the CEO nothing. Say at
   most one line in your own terminal: `squad-watch: nothing stalled`.

The detector reports each stall once: one ping, and one word to the CEO if the stall is still there
an hour later. It keeps what it reported in `.agent-squad/watch.tsv`, so running this command again
does not repeat itself.
