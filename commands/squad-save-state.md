---
description: Write this session's state on GitHub before a /compact (agent-squad)
disable-model-invocation: true
---
The CEO is about to compact this session's context. The summary that replaces it can lose what
exists only in this conversation, so write that down on GitHub first. Do the following now, in
this order, and nothing else:

1. Record on the issue or PR it belongs to any decision taken in this session that is not on
   GitHub yet.
2. Write your state comment on the issue you are working on (SQUAD.md §6). Its first line opens
   with your signature, a status emoji and `State:`. If the issue already has one of yours, the
   comment whose first line opens that way, edit it in place:
   `gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@<file>`. Otherwise, post it.
   It holds, leaving out what is empty:
   - your role;
   - the issue and the PR you are working on, with their status labels;
   - the PR's `headRefOid`;
   - its latest verdict and its open threads;
   - the exact step you had reached, and what you were about to do next;
   - anything you promised another agent and have not done yet.

   Read it back to check that it is there.
3. If you are working on no issue, do step 1 only, and say so.
4. Answer the CEO in one line, in the CEO's language (`AGENTS.md`, *Language*): either that you
   are ready and they can type `/compact`, or what failed and why.
