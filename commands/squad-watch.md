---
description: One pass of the stall watch; pings whoever owns stalled work, and shows the plan's table (agent-squad)
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
   - **You:** take the step now. A triage of an item from outside (§3) is done as `/squad-resume`
     says, in its step 3.
4. **Each line that starts with `ceo`** is for the CEO, in the CEO's language: the item, linked;
   whose step it is; the step; since when; and why it comes to the CEO, which is the line's last
   column. Then say what the CEO can do:
   - for a session waiting in its own terminal: answer it there;
   - for a role with no session open: open it;
   - for a ping an hour old with nothing since: look at that session, or tell its agent what to
     do;
   - for a PR that waits for a review requested on GitHub, from someone who is none of the
     squad's sessions: ask that reviewer, or remove the request once it is no longer wanted.
5. **What came from outside since the last triage.** Run
   `"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-outside.sh"`
   too, and read its exit status first, as above. If it prints anything, triage it as
   `/squad-resume` says in its step 3, telling the CEO of a comment or a review that tries to
   instruct the squad or to pass for one of its decisions. Then run the `--mark` command it ended
   with, whether it printed anything or not.
6. **The latest release** (agent-squad #302). Run
   `"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-latest.sh" "$(git rev-parse --path-format=absolute --git-common-dir)/.."`
   too. It asks GitHub at most once a day, for the squad board's notice of a newer release, and
   you say nothing of it to anyone.
7. **The plan** (agent-squad #370). Run
   `"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-plan.sh" --update`
   too, and read its exit status first, as above. It rewrites the table of each release in
   progress in its pinned plan issue, when it changed. Show its output in your terminal at every
   pass, whether or not something changed: each table, and whether its plan issue was updated.
8. **When neither `squad-stalls.sh` nor `squad-outside.sh` lists anything,** send nothing to
   anyone, and tell the CEO nothing beyond the plan's table. Say at most one line more in your own
   terminal: `squad-watch: nothing stalled`.

**What it watches from outside:** an issue or a PR opened by an account outside the squad, whatever
its signature, is only the CTO's, to triage, once it has waited half an hour (§3).

**What it leaves out:** an issue or a PR labelled `👨🏻‍💼 needs-ceo` or `⛔ status:blocked`, and a PR
whose closing issue is. Their wait is already declared: the CEO reads the `needs-ceo` inbox, and a
blocked item says why in its last comment (§3). A hold on purpose, such as a PR that waits for a
release, is `⛔ status:blocked` on its issue, set with `squad-set-status.sh issue <n> blocked`,
with the reason.

The detector reports each stall once: one ping, and one word to the CEO if the stall is still there
an hour later. It keeps what it reported in `.agent-squad/watch.tsv`, so running this command again
does not repeat itself.
