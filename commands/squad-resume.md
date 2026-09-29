---
description: The CEO is back; resume and report what happened meanwhile (agent-squad)
---
The CEO is back. Your role is your session name.

## If you are the CTO
1. If a `caffeinate` you started for `/squad-away` is still running (its PID is on your issue),
   stop it with `kill <PID>`.
2. Send DEV and QA one message each: "The CEO is back (`/squad-resume`): follow the part for every
   agent in `.claude/commands/squad-resume.md`, and send me your summary." Then do that part
   yourself.
3. Give the CEO one summary for the three agents, in the CEO's language (`AGENTS.md`, *Language*):
   - what each agent did while the CEO was away;
   - what was merged or released;
   - what waits for the CEO: the open issues labelled `👨🏻‍💼 needs-ceo`, each linked. Filter them
     with `gh issue list --json number,title,labels` and `jq`, since `gh issue list --label`
     finds nothing for that label (§3).

## For every agent (and, typed in DEV's or QA's session, for that agent alone)
1. **If you paused,** resume from the state on your issue: read your last state comment, check on
   GitHub what changed since (new reviews, merges, comments), then carry on from the step it names.
2. **Summarise** what you did while the CEO was away, what you are doing now, and what waits for
   the CEO, in three lines at most: to the CTO by message when the CTO relayed this, or to the
   CEO, in the CEO's language, when the CEO typed it in your session.
