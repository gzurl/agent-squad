import { describe, expect, test } from 'claude-code/testing'

import { asks, runs, says, START, start, stops, turnEnd, turnStart, world } from './world'

// What every squad session publishes (agent-squad #205, #222): its own key, `<project>/<role>`,
// with its state, its pause, the issue or PR its gh calls put in focus, its context use, its session
// id and name, and the time; nothing at all in a session that is not a squad's.

describe('a session outside the squad', () => {
  test('does nothing: no key, no command, no pane, no host command', async ($, on) => {
    const w = world(on)
    await start($, 'modtest-1')
    await turnStart($)
    await asks($, 'Bash')
    await runs($, w, 'gh pr checkout 5')
    await says($, '/squad-pause')
    await turnEnd($)
    await w.clock.advance(120_000)
    expect([...w.store.keys()]).toEqual([])
    expect(w.commands).toEqual([])
    expect(w.opened).toEqual([])
    expect(w.runs).toEqual([])
    expect(w.written).toEqual({})
  })
})

describe("a squad session's key", () => {
  test('names the project and the role, and holds the state, pause, autopilot, item, context, id, name, time and the release its board loaded', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    expect([...w.store.keys()]).toEqual(['proj/DEV'])
    expect(w.store.get('proj/DEV')).toEqual({
      project: 'proj', role: 'DEV', name: 'DEV:proj', sessionId: 'sid-1',
      state: 'idle', tool: null, since: START, at: START, context: 42, paused: false, autopilot: false, background: false,
      release: 'v42', item: null, focus: [],
    })
  })

  // agent-squad #361: the record squad-sessions.sh reads, beside the key.
  test("writes its record in .agent-squad/sessions/<role>.json: its name, id, loaded release and time, again with each key", async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    const path = '/work/proj/.agent-squad/sessions/DEV.json'
    expect(JSON.parse(w.written[path])).toEqual({ name: 'DEV:proj', sessionId: 'sid-1', release: 'v42', at: START })
    expect(w.written[path].endsWith('}\n')).toBe(true)
    await w.clock.advance(60_000)
    expect(JSON.parse(w.written[path])).toMatchObject({ at: START + 60_000 })
  })

  test('outside a git checkout it writes no record, and a record it cannot write leaves its key as it is', async ($, on) => {
    const outside = world(on)
    outside.remote = null
    await start($, 'DEV:proj')
    expect(outside.written).toEqual({})
    expect(outside.store.get('proj/DEV')).toMatchObject({ release: 'v42' })
  })

  test('takes the project-first name too', async ($, on) => {
    const w = world(on)
    await start($, 'proj:QA')
    expect([...w.store.keys()]).toEqual(['proj/QA'])
  })

  test('is rewritten every minute, with the context use of the moment', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    w.percent = 57
    await w.clock.advance(60_000)
    expect(w.store.get('proj/DEV')).toMatchObject({ at: START + 60_000, context: 57, since: START })
  })

  test('goes when the session ends', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await $.session.end({ reason: 'prompt_input_exit', sessionId: 'sid-1', resume: { id: 'sid-1' } } as any)
    expect([...w.store.keys()]).toEqual([])
  })

  test('stays when another session of the role has written it since', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    w.store.set('proj/DEV', { ...(w.store.get('proj/DEV') as any), sessionId: 'sid-2' })
    await $.session.end({ reason: 'prompt_input_exit', sessionId: 'sid-1', resume: { id: 'sid-1' } } as any)
    expect(w.store.get('proj/DEV')).toMatchObject({ sessionId: 'sid-2' })
  })

  test('after a reload, comes back from the store with the name the session started with', async ($, on) => {
    const kept = {
      project: 'proj', role: 'DEV', name: 'DEV:proj', sessionId: 'sid-1',
      state: 'working', tool: null, since: START - 5_000, at: START - 5_000, context: 30,
    }
    const w = world(on, { 'proj/DEV': kept, 'other/DEV': { ...kept, project: 'other', name: 'DEV:other', sessionId: 'sid-9' } })
    // A reload runs session.start again, without the SessionStart hook that gave the name.
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    // The release is the one the reloaded code belongs to (agent-squad #362).
    expect(w.store.get('proj/DEV')).toEqual({ ...kept, at: START, context: 42, paused: false, autopilot: false, background: false, release: 'v42', item: null, focus: [] })
  })

  test('after a reload, keeps its pause and its item', async ($, on) => {
    const item = { item: 'PR #7', url: 'https://github.com/o/r/pull/7' }
    const kept = {
      project: 'proj', role: 'QA', name: 'QA:proj', sessionId: 'sid-1',
      state: 'idle', tool: null, since: START - 5_000, at: START - 5_000, context: 30, paused: true, item,
    }
    const w = world(on, { 'proj/QA': kept })
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    expect(w.store.get('proj/QA')).toEqual({ ...kept, at: START, context: 42, autopilot: false, background: false, release: 'v42', focus: [item] })
  })
})

describe('the states', () => {
  test('working during a turn, idle after it; a subagent ending its turn changes nothing', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await turnStart($)
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'working' })
    await turnEnd($, 'agent-1')
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'working' })
    await turnEnd($)
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle' })
  })

  test('a permission waits from its dialog until the call reports its use', async ($, on) => {
    const w = world(on)
    await start($, 'QA:proj')
    await turnStart($)
    await w.clock.advance(1_000)
    await asks($, 'Bash')
    expect(w.store.get('proj/QA')).toMatchObject({ state: 'permission', tool: 'Bash', since: START + 1_000 })
    await $.classic.PostToolUse({ tool_name: 'Bash', tool_input: {}, tool_response: {}, tool_use_id: 'u1' } as any)
    expect(w.store.get('proj/QA')).toMatchObject({ state: 'working', tool: null })
  })

  test('a question waits until its call ends', async ($, on) => {
    const w = world(on)
    await start($, 'QA:proj')
    await turnStart($)
    await asks($, 'AskUserQuestion')
    expect(w.store.get('proj/QA')).toMatchObject({ state: 'question', tool: null })
    await $.tool.call({ tool: 'AskUserQuestion', tool_use_id: 'u2', questions: [] } as any)
    expect(w.store.get('proj/QA')).toMatchObject({ state: 'working' })
  })

  test('a wait ends when the approved call shows progress', async ($, on) => {
    const w = world(on)
    await start($, 'QA:proj')
    await turnStart($)
    await asks($, 'Bash')
    const pill = await $.ui.mount({
      plugin: 'squad-board', surface: 'terminal', component: 'ToolProgress',
      props: { tool_use_id: 'u3', kind: 'background_hint', hint: '(ctrl+b to run in background)' },
    })
    await pill.drawn()
    expect(w.store.get('proj/QA')).toMatchObject({ state: 'working' })
  })

  test("tool.check's ask alone is no wait: auto mode asks it with no dialog", async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await turnStart($)
    await $.tool.check({ tool: 'Bash', input: { command: 'touch x' } })
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'working' })
  })
})

describe('what the board leaves alone', () => {
  test("it answers no permission and changes no tool call's result", async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    expect(await $.classic.PermissionRequest({ tool_name: 'Bash', tool_input: {} } as any)).toEqual({})
    expect(await $.tool.call({ tool: 'Bash', tool_use_id: 'u4', command: 'ls' } as any))
      .toEqual({ result: { stdout: 'ran', stderr: '', interrupted: false } })
  })
})

describe("the focus: the issue or PR its agent works on, as its own gh calls declare it (agent-squad #289)", () => {
  // Each form, with what the key holds after it; the session's remote is git@github.com:o/r.git.
  const issue = (n: number) => ({ item: `#${n}`, url: `https://github.com/o/r/issues/${n}` })
  const pr = (n: number) => ({ item: `PR #${n}`, url: `https://github.com/o/r/pull/${n}` })
  const IN_PROGRESS = '"🚧 status:in-progress"'
  // `focusIs <w> <item or null>` checks what the band shows: the key's item, the latest focus.
  const focusIs = (w: any, item: { item: string; url: string | null } | null) =>
    expect(w.store.get('proj/DEV')).toMatchObject({ item })

  // What sets the focus: an issue declared in progress, a PR checked out or reviewed, in every form.
  const forms: [string, { item: string; url: string | null }][] = [
    [`gh issue edit 11 --add-label ${IN_PROGRESS} --remove-label "👀 status:in-review"`, issue(11)],
    ['gh issue edit 12 --add-label="🚧 status:in-progress"', issue(12)],
    ['gh issue edit 13 --add-label "🔴 P1,🚧 status:in-progress"', issue(13)],
    ['gh issue edit 14 --remove-label "👀 status:in-review" --add-label "🚧 status:in-progress"', issue(14)],
    ['gh pr checkout 22 --detach', pr(22)],
    ['gh pr checkout --detach 37', pr(37)],
    ['gh pr review 23 --comment --body-file review.md', pr(23)],
    ['gh pr review https://github.com/a/b/pull/27 --comment -b ok', { item: 'PR #27', url: 'https://github.com/a/b/pull/27' }],
    [`gh issue edit https://github.com/a/b/issues/28 --add-label ${IN_PROGRESS}`, { item: '#28', url: 'https://github.com/a/b/issues/28' }],
    [`gh issue edit 29 --repo a/b --add-label ${IN_PROGRESS}`, { item: '#29', url: 'https://github.com/a/b/issues/29' }],
    ['gh pr checkout --repo a/b 30', { item: 'PR #30', url: 'https://github.com/a/b/pull/30' }],
    ['gh pr checkout -R a/b 31 --detach', { item: 'PR #31', url: 'https://github.com/a/b/pull/31' }],
    ['rtk gh pr checkout 32', pr(32)],
    [`cd /work/proj && gh issue edit 33 --add-label ${IN_PROGRESS} </dev/null >/dev/null`, issue(33)],
    ['out=$(gh pr review 34 --comment -b ok)', pr(34)],
    ['gh issue edit 35 --add-label "🚧 status:in-progress" --body "see https://github.com/o/r/pull/9; gh pr checkout 9"', issue(35)],
    ['rtk proxy gh pr checkout 36', pr(36)],
    // QA's way of checking a PR out and reviewing it, with or without rtk proxy (agent-squad #334).
    ['git -C /work/proj/.agent-squad/worktrees/qa fetch origin pull/70/head', pr(70)],
    ['rtk proxy git -C /work/qa fetch -q origin pull/71/head && git -C /work/qa switch --detach abc1234', pr(71)],
    ['git fetch origin +refs/pull/72/head:refs/remotes/origin/pr/72', pr(72)],
    ['git fetch https://github.com/a/b.git pull/73/head', { item: 'PR #73', url: 'https://github.com/a/b/pull/73' }],
    ['gh api repos/o/r/pulls/74/reviews --input review.json', pr(74)],
    ['rtk proxy gh api repos/a/b/pulls/75/reviews -f event=COMMENT -f body=ok', { item: 'PR #75', url: 'https://github.com/a/b/pull/75' }],
    ['gh api -X POST repos/{owner}/{repo}/pulls/76/reviews', pr(76)],
    ['gh api --method=POST /repos/o/r/pulls/77/reviews --jq .html_url', pr(77)],
    ['gh api repos/o/r/pulls/78/reviews -F event=COMMENT </dev/null >/dev/null', pr(78)],
  ]
  for (const [command, item] of forms) {
    test(`sets it: ${command}`, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await runs($, w, command)
      focusIs(w, item)
    })
  }

  // QA's cases on PR #223, now with calls that set the focus: a heredoc body, a quoted body or a
  // comment is no command, whatever its apostrophes or its lines say.
  const heredocs: [string, string[], { item: string; url: string | null }][] = [
    ['an apostrophe in a heredoc, then gh pr review and a single-quoted jq filter (QA-H1)', [
      'cat > "$S/body.md" <<\'EOF\'',
      '**QA:** the CTO\'s decline holds by default.',
      'EOF',
      'gh pr review 216 --comment --body-file "$S/body.md" && gh pr view 216 --json labels --jq \'[.labels[].name]\'',
    ], pr(216)],
    ['a heredoc line that starts with gh pr checkout, then the real call (QA-H2)', [
      'cat > notes.md <<\'EOF\'',
      'gh pr checkout 9 is how QA starts a review',
      'EOF',
      'gh pr checkout 216 --detach',
    ], pr(216)],
    ['a closed single-quoted body, then gh pr review (QA-H3)', [
      "printf '%s\\n' '**QA:** waiting since 21:15, the CTO'\\''s call' > wait.md && gh pr review 221 --comment --body-file wait.md",
    ], pr(221)],
    ['an unquoted heredoc word, and a gh call in its body', [
      'cat > a.md <<EOF', 'gh pr checkout 1', 'EOF', `gh issue edit 230 --add-label ${IN_PROGRESS}`,
    ], issue(230)],
    ['a <<- heredoc whose end is indented with a tab', [
      'cat > a.md <<-"END"', '\tgh pr checkout 2', '\tEND', 'gh pr review 231 --comment --body-file a.md',
    ], pr(231)],
    ['two heredocs on one line, each body left out in turn', [
      'diff <(cat <<A) <(cat <<B)', 'gh pr checkout 3', 'A', 'gh pr checkout 4', 'B', 'gh pr checkout 232',
    ], pr(232)],
    ['a here-string has no body: the next line is a command', [
      'tr a-z A-Z <<<hello', 'gh pr checkout 233',
    ], pr(233)],
    ['a << inside double quotes, then a gh call on the next line', [
      'echo "write bodies with << EOF"', 'gh pr checkout 234',
    ], pr(234)],
    ['a << inside single quotes, then a gh call on the next line', [
      "echo 'a <<EOF b'", 'gh pr checkout 235',
    ], pr(235)],
    ['a real heredoc after a quoted << on the same line', [
      'echo "x << y" && cat > a.md <<\'EOF\'', 'gh pr checkout 1', 'EOF', 'gh pr checkout 236',
    ], pr(236)],
    ['a double-quoted body over several lines, with a gh line inside it', [
      'git commit -q -m "fix: x', '', 'gh pr checkout 3 is not a call"', 'gh pr checkout 237',
    ], pr(237)],
    ['an escaped double quote inside double quotes', [
      'echo "say \\"hi\\" << now"', 'gh pr checkout 238',
    ], pr(238)],
    ['a heredoc whose line goes on in a quote over two lines', [
      'cat <<EOF; echo "a', 'b"', 'gh pr checkout 4', 'EOF', 'gh pr checkout 239',
    ], pr(239)],
    ['an apostrophe in a comment line, then the call (QA-C1, on PR #226)', [
      "# the CTO's check", 'gh pr checkout 240',
    ], pr(240)],
    ['an apostrophe in a comment after a command, then the call', [
      "cd /work/proj # don't move", 'gh pr checkout 241',
    ], pr(241)],
    ['a heredoc named in a comment opens none', [
      '# cat <<EOF would start one', 'gh pr checkout 242',
    ], pr(242)],
    ['a # inside a word starts no comment: the quote after it still opens', [
      "echo a#b'c", "d' && gh pr checkout 243",
    ], pr(243)],
    ['a # after ${ starts no comment either', [
      "echo ${#x}'", "' && gh pr checkout 244",
    ], pr(244)],
    ['a # inside double quotes is text, its apostrophe too', [
      'git commit -q -m "x', "# not a comment, it's text", '" && gh pr checkout 245',
    ], pr(245)],
    ['a # right after a > starts a comment, as the shell reads it: its apostrophe opens nothing', [
      "echo hi >#don't", 'gh pr checkout 246',
    ], pr(246)],
    // A backslash at the end of a line joins the next one, as agents split a long gh call.
    ['a gh call split over lines with backslashes, its labels on the lines after', [
      'gh issue edit 247 \\', `  --remove-label "👀 status:in-review" \\`, `  --add-label ${IN_PROGRESS}`,
    ], issue(247)],
    ['a gh call whose number comes on the line after a backslash', [
      'gh pr checkout --detach \\', '  248',
    ], pr(248)],
    ['QA\'s review through gh api, its body in a heredoc that names another call (agent-squad #334)', [
      'gh api repos/o/r/pulls/249/reviews --input - <<\'EOF\'',
      '{"commit_id": "abc1234", "event": "COMMENT", "body": "QA\'s review; gh pr checkout 9"}',
      'EOF',
    ], pr(249)],
    ['gh pr create from a heredoc body: the PR gh prints', [
      'gh pr create --title "x" --body-file - <<\'EOF\'', 'Closes #5; gh pr checkout 6', 'EOF',
    ], pr(40)],
  ]
  for (const [name, lines, item] of heredocs) {
    test(name, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await runs($, w, lines.join('\n'), 'https://github.com/o/r/pull/40\n')
      focusIs(w, item)
    })
  }

  test('bookkeeping changes nothing: views, comments, other labels, and text that only names a call', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 50 --add-label ${IN_PROGRESS}`)
    for (const command of [
      'gh issue view 51 --json title,body', 'gh issue comment 52 --body-file /tmp/body.md', 'gh pr view 53 --json headRefOid',
      'gh pr comment 54 --body "fixed"', 'gh pr edit 55 --add-label "👀 status:in-review"',
      'gh issue edit 50 --add-label "👀 status:in-review" --remove-label "🚧 status:in-progress"',
      'gh issue edit 56 --add-label "🚧 status:in-progress-later"', 'gh issue edit 57 --remove-label "🚧 status:in-progress"',
      'gh pr create --fill', 'gh issue list --label x --limit 1000', 'gh pr checks 58', 'gh api repos/o/r/pulls/59',
      'git log -3', 'echo "gh pr checkout 60"', "printf '%s' 'gh issue edit 61 --add-label \"🚧 status:in-progress\"'",
      'echo "done; gh pr checkout 62"', "git commit -m 'x\ngh pr checkout 63'", 'gh pr checkout', 'gh pr merge --squash',
      // The shell reads #64 as a comment: the call names no number.
      'gh pr checkout #64', '# gh pr review 65',
      // Reading a PR or its reviews through gh api, fetching anything but a PR's head, or a comment
      // posted through gh api, is bookkeeping too (agent-squad #334).
      'gh api repos/o/r/pulls/66/reviews', 'rtk proxy gh api repos/o/r/pulls/66/reviews --paginate --jq ".[].id"',
      'gh api -X GET repos/o/r/pulls/66/reviews -f per_page=100', 'gh api repos/o/r/pulls/66 --jq .headRefOid',
      'gh api repos/o/r/pulls/66/comments -f body=fixed', 'gh api repos/o/r/pulls/66/reviews/1/comments --input -',
      'git fetch origin', 'rtk proxy git -C /work/qa fetch -q origin main', 'git log pull/67/head',
      'echo "git fetch origin pull/68/head"', 'git -C /work/qa switch --detach origin/main',
    ]) {
      await runs($, w, command, '')
      focusIs(w, issue(50))
    }
  })

  // agent-squad #289: trivial-tape's sequence, confirmed by its DEV. The agent declared #113 and #114
  // in progress, commented on #117, merged PR #118, which QA had approved, from that same worktree,
  // edited #117's labels, read PR #118 and #117, and merged main in: it never left #114.
  test("trivial-tape's sequence shows #114 from its first line to its end, where it showed PR #118", async ($, on) => {
    const w = world(on)
    await start($, 'DEV:trivial-tape')
    const focusOn = (item: any) => expect(w.store.get('trivial-tape/DEV')).toMatchObject({ item })
    for (const command of [
      `gh issue edit 113 --add-label ${IN_PROGRESS} && gh issue edit 114 --add-label ${IN_PROGRESS}`,
      'git switch -c feature/expo-iap origin/main',
      'gh issue comment 117 --body "Sequencing: #113 and #114 first, as you asked."',
      'git add -A && git commit -qm "wip: expo-iap"',
      'p="$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook" && head=$("$p/scripts/squad-merge-gate.sh" 118) && gh pr merge 118 --squash --match-head-commit "$head" && gh issue edit 117 --remove-label "👀 status:in-review"',
      'gh pr view 118 --json state,mergeCommit',
      'gh issue view 117 --json state',
      'git fetch -q origin && git merge --no-edit origin/main',
    ]) {
      await runs($, w, command, '')
      focusOn(issue(114))
    }
  })

  test('the normal flow: #117 in progress, then its PR, then in review, then merged: the role alone', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 117 --add-label ${IN_PROGRESS} --remove-label "👀 status:in-review"`)
    focusIs(w, issue(117))
    await runs($, w, 'gh pr create --title "fix: x" --body-file pr.md', 'Creating pull request\nhttps://github.com/o/r/pull/120\n')
    focusIs(w, pr(120))
    await runs($, w, 'gh pr edit 120 --add-label "👀 status:in-review" && gh issue edit 117 --add-label "👀 status:in-review" --remove-label "🚧 status:in-progress"')
    focusIs(w, pr(120))
    await runs($, w, 'head=$(squad-merge-gate.sh 120) && gh pr merge 120 --squash --match-head-commit "$head"')
    // pr.md is a relative path, so the board read no body: the PR is tied to nothing, and #117 ends
    // with the author's next step, its status label removed (agent-squad #354).
    focusIs(w, issue(117))
    await runs($, w, 'gh issue edit 117 --remove-label "👀 status:in-review" --remove-label "🚧 status:in-progress"')
    focusIs(w, null)
  })

  // agent-squad #367: the playbook's squad-set-status.sh sets the status label, and the board reads
  // it as it reads gh issue edit, however the script is reached: in progress, the issue becomes the
  // focus; in review, blocked or none, it leaves it.
  const SET = '"$p/scripts/squad-set-status.sh"'
  const scriptForms: [string, { item: string; url: string | null }][] = [
    [`p="$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook" && ${SET} issue 81 in-progress`, issue(81)],
    ['"$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook/scripts/squad-set-status.sh" issue 82 in-progress', issue(82)],
    ['/work/proj/.agent-squad/playbook/scripts/squad-set-status.sh issue 83 in-progress </dev/null >/dev/null', issue(83)],
    [`out=$(${SET} issue 84 in-progress 2>&1)`, issue(84)],
    [`rtk proxy ${SET} issue 85 in-progress > /tmp/status.out`, issue(85)],
    ['squad-set-status.sh issue 86 in-progress', issue(86)],
  ]
  for (const [command, item] of scriptForms) {
    test(`squad-set-status.sh sets it: ${command}`, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await runs($, w, command, 'status: issue is 🚧 status:in-progress\n')
      focusIs(w, item)
    })
  }

  for (const state of ['in-review', 'blocked', 'none']) {
    test(`squad-set-status.sh issue <n> ${state} ends the issue: the band shows the item before it`, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await runs($, w, `${SET} issue 89 in-progress && ${SET} issue 90 in-progress`)
      focusIs(w, issue(90))
      await runs($, w, `${SET} issue 90 ${state}`)
      focusIs(w, issue(89))
      await runs($, w, `${SET} issue 89 ${state} >/dev/null`)
      focusIs(w, null)
    })
  }

  test("squad-set-status.sh on a PR, and a call the script refuses or that only names it, change nothing", async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `${SET} issue 50 in-progress`)
    for (const command of [
      `${SET} pr 120 in-progress`, `${SET} pr 120 in-review`, `${SET} pr 120 approved`, `${SET} pr 50 none`,
      `${SET} issue 91 approved`, `${SET} issue 50 approved`, `${SET} issue 50 bogus`, `${SET} issues 91 in-progress`,
      `${SET} issue 91a in-progress`, `${SET} issue 91 in-progress now`, `${SET} issue 50 none now`, `${SET} issue 91`,
      `${SET} pr 50 blocked`, `echo ${SET} issue 91 in-progress`, 'squad-set-status.shx issue 91 in-progress',
      'other-squad-set-status.sh issue 50 none', "printf '%s' 'squad-set-status.sh issue 50 none'",
    ]) {
      await runs($, w, command, '')
      focusIs(w, issue(50))
    }
  })

  test('the normal flow through squad-set-status.sh: the issue, its PR, in review, merged: the role alone', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `${SET} issue 117 in-progress`)
    focusIs(w, issue(117))
    await runs($, w, 'gh pr create --title "fix: x" --body "Closes #117"', 'https://github.com/o/r/pull/120\n')
    focusIs(w, pr(120))
    await runs($, w, `${SET} pr 120 in-review && ${SET} issue 117 in-review`)
    expect(w.store.get('proj/DEV')).toMatchObject({ item: pr(120), focus: [{ ...pr(120), tied: issue(117) }] })
    await runs($, w, 'head=$(squad-merge-gate.sh 120) && gh pr merge 120 --squash --match-head-commit "$head"')
    focusIs(w, null)
    await runs($, w, `${SET} issue 117 none`)
    focusIs(w, null)
  })

  test('an issue squad-set-status.sh names on the line is never the one gh issue create made', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `${SET} issue 117 none && gh issue create --title x --label "🚧 status:in-progress"`,
      'https://github.com/o/r/issues/117\nhttps://github.com/o/r/issues/130\n')
    focusIs(w, issue(130))
  })

  // QA's finding on PR #294: the other calls of a line print addresses too, gh issue edit the
  // issue's and a comment the comment's, before or after the one gh pr create prints.
  const created: [string, string, string][] = [
    ['after gh issue edit (QA-F2)', `gh issue edit 117 --add-label "👀 status:in-review" --remove-label "🚧 status:in-progress" && gh pr create --fill`,
      'https://github.com/o/r/issues/117\nhttps://github.com/o/r/pull/120\n'],
    ['after gh issue comment (QA-F3)', 'gh issue comment 117 --body "PR next" && gh pr create --fill',
      'https://github.com/o/r/issues/117#issuecomment-1\nhttps://github.com/o/r/pull/120\n'],
    ['after gh pr comment on another PR', 'gh pr comment 50 --body "superseded" && gh pr create --fill',
      'https://github.com/o/r/pull/50#issuecomment-2\nhttps://github.com/o/r/pull/120\n'],
    ['before gh issue edit', 'gh pr create --fill && gh issue edit 117 --add-label "👀 status:in-review"',
      'Creating pull request for x into main in o/r\n\nhttps://github.com/o/r/pull/120\nhttps://github.com/o/r/issues/117\n'],
    // agent-squad #299: gh pr edit prints its PR's address alone, as gh pr create does (QA-F10).
    ['after gh pr edit of another PR (QA-F10)', 'gh pr edit 50 --add-label "superseded" && gh pr create --fill',
      'https://github.com/o/r/pull/50\nhttps://github.com/o/r/pull/120\n'],
    ['before gh pr edit of another PR', 'gh pr create --fill && gh pr edit 50 --add-label "superseded"',
      'https://github.com/o/r/pull/120\nhttps://github.com/o/r/pull/50\n'],
    ['after gh pr edit of another repository\'s PR', 'gh pr edit https://github.com/a/b/pull/50 --add-label x && gh pr create --fill',
      'https://github.com/a/b/pull/50\nhttps://github.com/o/r/pull/120\n'],
  ]
  for (const [name, command, output] of created) {
    test(`gh pr create ${name}: the PR it made, tied to nothing with no body to read; its merge gives the issue back`, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await runs($, w, `gh issue edit 117 --add-label ${IN_PROGRESS}`)
      await runs($, w, command, output)
      expect(w.store.get('proj/DEV')).toMatchObject({ item: pr(120), focus: [{ ...issue(117), tied: null }, { ...pr(120), tied: null }] })
      await runs($, w, 'gh pr merge 120 --squash')
      focusIs(w, issue(117))
    })
  }

  // QA's P3 on PR #294 (QA-F8): a PR the session created keeps its tie when it is entered again.
  test('a created PR checked out or reviewed again keeps its tie: its merge still ends the issue', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 117 --add-label ${IN_PROGRESS}`)
    await runs($, w, 'gh pr create --title "fix: x" --body "Closes #117"', 'https://github.com/o/r/pull/120\n')
    await runs($, w, 'gh pr checkout 120')
    await runs($, w, 'gh pr review 120 --comment -b "self-review"')
    focusIs(w, pr(120))
    await runs($, w, 'gh pr merge 120 --squash')
    focusIs(w, null)
  })

  test("QA: pr checkout, then pr review, show the PR; QA's next checkout replaces it", async ($, on) => {
    const w = world(on)
    await start($, 'QA:proj')
    await runs($, w, 'gh pr checkout 120 --detach')
    expect(w.store.get('proj/QA')).toMatchObject({ item: pr(120) })
    await runs($, w, 'gh pr review 120 --comment --body-file review.md')
    expect(w.store.get('proj/QA')).toMatchObject({ item: pr(120) })
    await runs($, w, 'gh pr checkout 121 --detach')
    expect(w.store.get('proj/QA')).toMatchObject({ item: pr(121) })
  })

  test('a chained line counts every call, in order, and takes its last focus', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 5 --add-label ${IN_PROGRESS} && gh issue edit 6 --add-label ${IN_PROGRESS}`)
    focusIs(w, issue(6))
    await runs($, w, `gh pr merge 70 --squash; gh issue edit 7 --add-label ${IN_PROGRESS} | cat`)
    focusIs(w, issue(7))
    await runs($, w, 'gh issue close 7 --comment "done" && gh issue close 6')
    focusIs(w, issue(5))
  })

  test('ending one goes back to the one before; ending a PR the session created ends its issue too', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 10 --add-label ${IN_PROGRESS}`)
    await runs($, w, 'gh pr review 50 --approve')
    focusIs(w, pr(50))
    // A detour: a PR reviewed, then merged, gives the issue back.
    await runs($, w, 'gh pr merge 50 --squash')
    focusIs(w, issue(10))
    await runs($, w, `gh issue edit 11 --add-label ${IN_PROGRESS}`)
    await runs($, w, 'gh pr create --title "fix: y" --body "Fixes #11"', 'https://github.com/o/r/pull/60\n')
    focusIs(w, pr(60))
    // PR #60's body fixes #11: closing it ends #11 too, and #10 shows again.
    await runs($, w, 'gh pr close 60 --comment "superseded"')
    focusIs(w, issue(10))
    // Ending something not in the focus changes nothing.
    await runs($, w, 'gh issue close 99 && gh pr merge 98')
    focusIs(w, issue(10))
    await runs($, w, 'gh issue close 10')
    focusIs(w, null)
  })

  // agent-squad #354: an issue created already in progress is a focus, as gh issue edit adding the
  // label is; the issue is the one gh issue create prints, not one another call of the line names.
  const createdIssues: [string, string, string, { item: string; url: string | null }][] = [
    ['--label', `gh issue create --title "x" --label ${IN_PROGRESS} --body "y"`, 'https://github.com/o/r/issues/90\n', issue(90)],
    ['-l in a comma list', 'gh issue create -t x -l "🐛 bug,🚧 status:in-progress" -b y', 'https://github.com/o/r/issues/91\n', issue(91)],
    ['--label=', 'gh issue create --title x --label="🚧 status:in-progress" --body y', 'https://github.com/o/r/issues/92\n', issue(92)],
    ['in another repository', `gh issue create --repo a/b --title x --label ${IN_PROGRESS} --body y`,
      'https://github.com/a/b/issues/93\n', { item: '#93', url: 'https://github.com/a/b/issues/93' }],
    ['in a $( ), its body from a heredoc that names another call, after an edit that prints #5', [
      `gh issue edit 5 --add-label "🐛 bug" && url=$(gh issue create --title "x" --label ${IN_PROGRESS} --body-file - </dev/null 2>&1 <<'EOF' | tail -1`,
      'It names gh issue edit 6 --add-label "🚧 status:in-progress".', 'EOF', ')', 'echo "$url"',
    ].join('\n'), 'https://github.com/o/r/issues/5\nhttps://github.com/o/r/issues/94\n', issue(94)],
  ]
  for (const [name, command, output, item] of createdIssues) {
    test(`gh issue create with the in-progress label, ${name}: the issue it made`, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await runs($, w, command, output)
      focusIs(w, item)
    })
  }
  test('gh issue create without the in-progress label, or a label set through a variable, is no focus', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, 'gh issue create --title x --label "🐛 bug" --body y', 'https://github.com/o/r/issues/95\n')
    await runs($, w, `n=96; gh issue edit "$n" --add-label ${IN_PROGRESS}`, '')
    focusIs(w, null)
  })

  // agent-squad #354: a PR is tied to the issue its body closes, when the board can read the body:
  // inline, or in a file whose absolute path is written out; otherwise to none.
  const bodies: [string, string, Record<string, string>, { item: string; url: string | null } | null][] = [
    ['--body "Closes #117"', 'gh pr create --title "fix: x" --body "Closes #117"', {}, issue(117)],
    ['-b "fixes #117"', 'gh pr create -t x -b "It fixes #117."', {}, issue(117)],
    ['--body="Resolves: #117"', 'gh pr create --title x --body="Resolves: #117"', {}, issue(117)],
    ['a --body-file with an absolute path', 'gh pr create --title x --body-file /tmp/pr.md', { '/tmp/pr.md': 'What it does.\n\nCloses #117\n' }, issue(117)],
    ['-F with an absolute path', 'gh pr create --title x -F /tmp/pr.md', { '/tmp/pr.md': 'closed #117' }, issue(117)],
    ['a --body-file through a variable', 'S=/tmp; gh pr create --title x --body-file "$S/pr.md"', { '/tmp/pr.md': 'Closes #117' }, null],
    // An absolute path that holds a variable is the shell's to expand: the board reads none.
    ['an absolute --body-file that holds a variable', 'gh pr create --title x --body-file "/scratch/$S/pr.md"',
      { '/scratch/$S/pr.md': 'Closes #117' }, null],
    // A relative path is the shell's, not the session's: the board, which would read it from the
    // session's root, reads none.
    ['a --body-file with a relative path', 'gh pr create --title x --body-file pr.md',
      { 'pr.md': 'Closes #117', '/work/proj/pr.md': 'Closes #117' }, null],
    ['a body that closes nothing', 'gh pr create --title x --body "Part of #117"', {}, null],
    ['--fill', 'gh pr create --fill', {}, null],
  ]
  for (const [name, command, files, tied] of bodies) {
    test(`gh pr create with ${name}: tied to ${tied ? 'the issue it closes' : 'nothing'}`, async ($, on) => {
      const w = world(on)
      w.files = files
      await start($, 'DEV:proj')
      await runs($, w, `gh issue edit 117 --add-label ${IN_PROGRESS}`)
      await runs($, w, command, 'https://github.com/o/r/pull/120\n')
      expect(w.store.get('proj/DEV')).toMatchObject({ item: pr(120), focus: [{ ...issue(117), tied: null }, { ...pr(120), tied }] })
      await runs($, w, 'gh pr merge 120 --squash')
      focusIs(w, tied ? null : issue(117))
    })
  }
  test('a PR whose body closes another issue than the one in focus leaves that one in focus when it merges', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 246 --add-label ${IN_PROGRESS}`)
    await runs($, w, 'gh pr create --title x --body "Closes #348"', 'https://github.com/o/r/pull/349\n')
    expect(w.store.get('proj/DEV')).toMatchObject({ focus: [{ ...issue(246), tied: null }, { ...pr(349), tied: issue(348) }] })
    await runs($, w, 'gh pr merge 349 --squash')
    focusIs(w, issue(246))
  })

  // agent-squad #354: removing an issue's in-progress or in-review label, and adding no status
  // label, ends the work on it, as the author does once its PR is merged (SQUAD.md §4.9).
  test('an issue whose status label is removed, with none added, leaves the focus; a label swap does not', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 10 --add-label ${IN_PROGRESS} && gh issue edit 11 --add-label ${IN_PROGRESS}`)
    await runs($, w, 'gh issue edit 11 --add-label "👀 status:in-review" --remove-label "🚧 status:in-progress"')
    await runs($, w, 'gh issue edit 11 --remove-label "⛔ status:blocked"')
    focusIs(w, issue(11))
    await runs($, w, 'gh issue edit 11 --remove-label "👀 status:in-review" --remove-label "🚧 status:in-progress" </dev/null >/dev/null')
    focusIs(w, issue(10))
    await runs($, w, 'gh issue edit 10 --remove-label="🚧 status:in-progress"')
    focusIs(w, null)
  })

  // agent-squad #354's criterion: a parent issue whose sub-issues' PRs merge one by one stays in
  // focus, and the last PR, which closes the parent, takes it with it.
  test('a parent issue stays in focus while its sub-issues merge one by one, and goes with the PR that closes it', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 246 --add-label ${IN_PROGRESS}`)
    for (const [sub, n] of [[350, 351], [352, 353]]) {
      await runs($, w, `gh issue create --title "part of #246" --label ${IN_PROGRESS} --body "Part of #246."`, `https://github.com/o/r/issues/${sub}\n`)
      focusIs(w, issue(sub))
      await runs($, w, `gh pr create --title "test: part (#${sub})" --body "Closes #${sub}, part of #246."`, `https://github.com/o/r/pull/${n}\n`)
      focusIs(w, pr(n))
      await runs($, w, `gh pr merge ${n} --squash && gh issue edit ${sub} --remove-label "👀 status:in-review" --remove-label "🚧 status:in-progress"`)
      focusIs(w, issue(246))
    }
    await runs($, w, 'gh pr create --title "test: the last part (#246)" --body "Closes #246."', 'https://github.com/o/r/pull/355\n')
    await runs($, w, 'gh pr merge 355 --squash')
    focusIs(w, null)
  })

  // agent-squad #354, point 3: DEV's own commands of 2026-10-12, word for word but for the paths,
  // from #246 in progress to PR #349's merge. Its body file was named through a variable, so the
  // PR was tied to nothing; #348 was set in progress through a variable too. #246 stays.
  test("DEV's sequence of 2026-10-12 keeps #246 in focus through PR #349's merge", async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    const sequence: [string, string][] = [
      [`gh issue edit 246 --add-label "🚧 status:in-progress" --remove-label "👀 status:in-review" --remove-label "⛔ status:blocked" </dev/null >/dev/null; gh issue view 246 --json title,labels,milestone,body,comments --jq '.title, ([.labels[].name]|join(",")) + " | " + (.milestone.title // "none"), "", .body, (.comments[] | "--- " + .createdAt + " " + .author.login + "\\n" + .body)' </dev/null`, 'title\n'],
      [[`url=$(gh issue create --title "The coverage job has read 44% since PR #322" --label "👨🏼‍💻 owner:dev" --label "🐛 bug" --label "🟡 P2" --milestone "v53 — every script line covered or excused" --body-file - </dev/null 2>&1 <<'EOF' | tail -1`,
        '**DEV:** Found while refreshing #246.', 'EOF',
        `); echo "$url"; case "$url" in https://github.com/o/r/issues/[0-9]*) n=\${url##*/}; gh issue edit "$n" --add-label "🚧 status:in-progress" </dev/null >/dev/null; echo "labelled #$n";; esac`].join('\n'),
        'https://github.com/o/r/issues/348\nlabelled #348\n'],
      [`cd "/work/proj/.agent-squad/worktrees/dev" && S=/scratch; cat > "$S/pr-348.md" <<'EOF'\nCloses #348.\nEOF\ngh pr create --title "fix: the coverage summary reads kcov's records (#348)" --body-file "$S/pr-348.md" --base main </dev/null 2>&1 | tail -1; sleep 30; for i in $(seq 1 36); do s=$(gh pr checks fix/coverage-unescaped-paths --json name,bucket </dev/null 2>/dev/null); if [ -n "$s" ] && echo "$s" | jq -e '([.[] | select(.name != "label")] | length) >= 5 and all(.bucket != "pending")' >/dev/null; then break; fi; sleep 15; done; echo "$s" | jq -r '.[] | "\\(.name) \\(.bucket)"'; gh pr view fix/coverage-unescaped-paths --json number,headRefOid --jq '"\\(.number) \\(.headRefOid)"' </dev/null`,
        'https://github.com/o/r/pull/349\nchecks pass\n349 a590dfd8eee7bc69699e95d879e9b2ff89c30885\n'],
      [`cd "/work/proj/.agent-squad/worktrees/dev" && gh pr edit 349 --add-label "👀 status:in-review" --remove-label "🚧 status:in-progress" --remove-label "✅ status:approved" </dev/null >/dev/null && gh issue edit 348 --add-label "👀 status:in-review" --remove-label "🚧 status:in-progress" --remove-label "⛔ status:blocked" </dev/null >/dev/null; now=$(date '+%H:%M'); gh pr comment 349 --body "**DEV:** Waiting for QA's review since $now." </dev/null >/dev/null`, ''],
      [`cd "/work/proj/.agent-squad/worktrees/dev" && p="$(git rev-parse --path-format=absolute --git-common-dir)/../.agent-squad/playbook" && head=$("$p/scripts/squad-merge-gate.sh" 349 </dev/null 2>/dev/null) && gh pr merge 349 --squash --match-head-commit "$head" </dev/null && git fetch -q origin && git branch -D fix/coverage-unescaped-paths && git push origin --delete fix/coverage-unescaped-paths </dev/null 2>&1 | tail -1; gh pr view 349 --json state,mergeCommit --jq '.state + " " + .mergeCommit.oid' </dev/null; gh issue view 348 --json state --jq .state </dev/null; gh issue edit 348 --remove-label "👀 status:in-review" --remove-label "🚧 status:in-progress" </dev/null >/dev/null; gh issue view 348 --json labels --jq '[.labels[].name]|join(",")' </dev/null`,
        ' - [deleted]         fix/coverage-unescaped-paths\nMERGED 48f3597\nCLOSED\n'],
    ]
    for (const [command, output] of sequence) {
      await runs($, w, command, output)
      expect(w.store.get('proj/DEV').focus.map((entry: any) => entry.item)).toContain('#246')
    }
    focusIs(w, issue(246))
  })

  test('it holds five at most: a sixth drops the oldest', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    for (const n of [1, 2, 3, 4, 5, 6]) await runs($, w, `gh issue edit ${n} --add-label ${IN_PROGRESS}`)
    expect(w.store.get('proj/DEV')).toMatchObject({ item: issue(6), focus: [2, 3, 4, 5, 6].map(n => ({ ...issue(n), tied: null })) })
  })

  test('a command that failed, or another tool, changes nothing', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    w.isError = true
    await runs($, w, 'gh pr checkout 60')
    focusIs(w, null)
    w.isError = false
    await $.tool.call({ tool: 'mcp__shell__run', tool_use_id: 'u-mcp', command: 'gh pr checkout 61' } as any)
    focusIs(w, null)
    await runs($, w, `gh issue edit 62 --add-label ${IN_PROGRESS}`)
    w.isError = true
    await runs($, w, 'gh issue close 62')
    focusIs(w, issue(62))
  })

  // A key as this release writes it, and one from before #289, with its item alone.
  const kept = {
    project: 'proj', role: 'DEV', name: 'DEV:proj', sessionId: 'sid-1',
    state: 'idle', tool: null, since: START - 5_000, at: START - 5_000, context: 30,
  }
  test('after a reload, the focus comes back from the key, ties included', async ($, on) => {
    const focus = [{ ...issue(1), tied: null }, { ...pr(2), tied: issue(1) }]
    const w = world(on, { 'proj/DEV': { ...kept, item: pr(2), focus } })
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    expect(w.store.get('proj/DEV')).toMatchObject({ item: pr(2), focus })
    await runs($, w, 'gh pr merge 2')
    focusIs(w, null)
  })

  test('a key from before #289, with an item alone, comes back as a focus of that item', async ($, on) => {
    const w = world(on, { 'proj/DEV': { ...kept, item: issue(3) } })
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    expect(w.store.get('proj/DEV')).toMatchObject({ item: issue(3), focus: [issue(3)] })
  })

  test('a repository that is not on GitHub: the focus, with no address', async ($, on) => {
    const w = world(on)
    w.remote = 'git@gitlab.com:o/r.git'
    await start($, 'DEV:proj')
    await runs($, w, `gh issue edit 70 --add-label ${IN_PROGRESS}`)
    focusIs(w, { item: '#70', url: null })
  })

  for (const remote of [null, 'unreadable']) {
    test(`a session whose repository is ${remote ?? 'none'} keeps its key, and a focus with no address`, async ($, on) => {
      const w = world(on)
      w.remote = remote
      await start($, 'DEV:proj')
      expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle', item: null, at: START })
      await w.clock.advance(60_000)
      expect(w.store.get('proj/DEV')).toMatchObject({ at: START + 60_000 })
      await runs($, w, 'gh pr checkout 72')
      expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle', item: { item: 'PR #72', url: null } })
    })
  }

  test('an https remote gives the same address as an ssh one', async ($, on) => {
    const w = world(on)
    w.remote = 'https://github.com/o/r.git'
    await start($, 'DEV:proj')
    await runs($, w, 'gh pr checkout 71')
    focusIs(w, pr(71))
  })

  test('the focus goes with the key at the session end; after a /clear the session goes on with none', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, 'gh pr checkout 80')
    await $.session.end({ reason: 'clear', sessionId: 'sid-1', resume: { id: 'sid-1' } } as any)
    expect([...w.store.keys()]).toEqual([])
    w.sessionId = 'sid-2'
    await w.clock.advance(60_000)
    expect(w.store.get('proj/DEV')).toMatchObject({ sessionId: 'sid-2', item: null, focus: [] })
  })

  test('no host command is run, and nothing is read from GitHub', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await runs($, w, 'gh pr checkout 90')
    // A heartbeat and a tick past it: every timer of the board has run since the call, in 21 ticks
    // rather than the 200 of ten minutes (agent-squad #379).
    await w.clock.advance(63_000)
    expect(w.runs).toEqual([])
  })
})

describe('the autopilot (agent-squad #244)', () => {
  // Set by /squad-autopilot, typed or relayed; cleared by a resume or a pause; a pause and the
  // autopilot clear each other.
  for (const [set, clear] of [['/squad-autopilot', '/squad-resume'], ['/squad-autopilot-all', '/squad-pause'],
    ['The CEO is away and the machine stays on (`/squad-autopilot`): follow the part for every agent.', '/squad-resume-all']]) {
    test(`set by "${set.slice(0, 40)}", cleared by "${clear}"`, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await says($, set, set.startsWith('/') ? 'composer' : 'peer')
      expect(w.store.get('proj/DEV')).toMatchObject({ autopilot: true, paused: false })
      await says($, clear)
      expect(w.store.get('proj/DEV')).toMatchObject({ autopilot: false, paused: clear === '/squad-pause' })
    })
  }

  test('a pause clears the autopilot, and the autopilot the pause', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await says($, '/squad-pause')
    await says($, '/squad-autopilot')
    expect(w.store.get('proj/DEV')).toMatchObject({ autopilot: true, paused: false })
    await says($, '/squad-pause')
    expect(w.store.get('proj/DEV')).toMatchObject({ autopilot: false, paused: true })
  })

  test('a message that only quotes the command sets nothing', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await says($, 'The CTO may relay (`/squad-autopilot`) later.', 'peer')
    expect(w.store.get('proj/DEV')).toMatchObject({ autopilot: false })
  })
})

describe('the pause (agent-squad #222)', () => {
  // The step-away commands as the CEO types them, and as /squad-pause.md and the others relay them.
  const pauses = [
    '/squad-pause',
    '/squad-pause-all',
    'The CEO needs the squad stopped at a safe point (`/squad-pause`): follow the part for every agent',
    'The CEO needs every squad stopped at a safe point (`/squad-pause-all`): follow the part for every agent',
    'The CEO is upgrading the squad and needs it at a safe point (`/squad-pause`): follow the part for every agent',
  ]
  const clears = [
    '/squad-resume', '/squad-resume-all', '/squad-autopilot', '/squad-autopilot-all',
    'The CEO is back (`/squad-resume`): follow the part for every agent',
    'The CEO is back (`/squad-resume-all`): follow the part for every agent',
    'The CEO is away and the machine stays on (`/squad-autopilot`): follow the part for every agent',
    'The CEO is away and the machine stays on (`/squad-autopilot-all`): follow the part for every agent',
  ]
  for (const pause of pauses) {
    for (const clear of clears) {
      test(`set by "${pause.slice(0, 50)}", cleared by "${clear.slice(0, 50)}"`, async ($, on) => {
        const w = world(on)
        await start($, 'DEV:proj')
        await says($, pause, 'peer')
        expect(w.store.get('proj/DEV')).toMatchObject({ paused: true, state: 'idle' })
        await says($, clear)
        expect(w.store.get('proj/DEV')).toMatchObject({ paused: false })
      })
    }
  }

  test('a turn while paused works as usual, and the pause holds after it', async ($, on) => {
    const w = world(on)
    await start($, 'QA:proj')
    await says($, '/squad-pause')
    await turnStart($)
    expect(w.store.get('proj/QA')).toMatchObject({ paused: true, state: 'working' })
    await turnEnd($)
    await says($, 'what is your state?')
    expect(w.store.get('proj/QA')).toMatchObject({ paused: true, state: 'idle' })
  })

  test('a prompt that only mentions a command, or a command of another name, changes nothing', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    for (const text of [
      'set by `/squad-pause` or `-all`, typed or relayed', 'please do not /squad-pause yet', '/squad-pauses',
      '/squad-save-state', '/squad-watch', '(`/squad-paused`):',
      // QA's case on PR #223 (QA-P1): a message that quotes the relay form, with no colon after it.
      'DEV: in PR #223 the relay names the command as "(`/squad-pause`)", and check-mods checks it.',
    ]) {
      await says($, text)
      expect(w.store.get('proj/DEV')).toMatchObject({ paused: false })
    }
  })
})

describe('a background shell (agent-squad #264)', () => {
  test('a turn that ends with a background shell running sets it in the key; a later turn that ends with none clears it', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await turnStart($)
    await stops($, ['shell'])
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle', background: true })
    // The shell's end opens a turn of its own, whose Stop lists none.
    await says($, 'Background command "sleep 30" completed', 'task-notification' as any)
    await turnStart($)
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'working', background: true })
    await stops($)
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle', background: false })
  })

  test('a Stop that comes after turn.complete still writes the key at once, with no heartbeat', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await turnStart($)
    await turnEnd($)
    await $.classic.Stop({ hook_event_name: 'Stop', stop_hook_active: false, background_tasks: [{ id: 'b0', type: 'shell', status: 'running', description: 'sleep' }] } as any)
    expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle', background: true, at: START })
  })

  test('only a shell counts: a background subagent or monitor does not', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await turnStart($)
    await stops($, ['subagent', 'monitor'])
    expect(w.store.get('proj/DEV')).toMatchObject({ background: false })
  })

  test('the shell survives a reload, and goes with the key at the session end', async ($, on) => {
    const kept = {
      project: 'proj', role: 'QA', name: 'QA:proj', sessionId: 'sid-1',
      state: 'idle', tool: null, since: START - 5_000, at: START - 5_000, context: 30, background: true,
    }
    const w = world(on, { 'proj/QA': kept })
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    expect(w.store.get('proj/QA')).toMatchObject({ background: true })
    await $.session.end({ reason: 'clear', sessionId: 'sid-1', resume: { id: 'sid-1' } } as any)
    w.sessionId = 'sid-2'
    await w.clock.advance(60_000)
    expect(w.store.get('proj/QA')).toMatchObject({ sessionId: 'sid-2', background: false })
  })

  test('outside the squad, a Stop writes nothing', async ($, on) => {
    const w = world(on)
    await start($, 'modtest-1')
    await turnStart($)
    await stops($, ['shell'])
    expect([...w.store.keys()]).toEqual([])
  })
})
