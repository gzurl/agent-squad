import { describe, expect, test } from 'claude-code/testing'

import { asks, runs, says, START, start, stops, turnEnd, turnStart, world } from './world'

// What every squad session publishes (agent-squad #205, #222): its own key, `<project>/<role>`,
// with its state, its pause, the issue or PR it last acted on with gh, its context use, its session
// id and name, and the time; nothing at all in a session that is not a squad's.

describe('a session outside the squad', () => {
  test('does nothing: no key, no command, no pane, no host command', async ($, on) => {
    const w = world(on)
    await start($, 'modtest-1')
    await turnStart($)
    await asks($, 'Bash')
    await runs($, w, 'gh pr view 5')
    await says($, '/squad-pause')
    await turnEnd($)
    await w.clock.advance(120_000)
    expect([...w.store.keys()]).toEqual([])
    expect(w.commands).toEqual([])
    expect(w.opened).toEqual([])
    expect(w.runs).toEqual([])
  })
})

describe("a squad session's key", () => {
  test('names the project and the role, and holds the state, pause, item, context, id, name and time', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    expect([...w.store.keys()]).toEqual(['proj/DEV'])
    expect(w.store.get('proj/DEV')).toEqual({
      project: 'proj', role: 'DEV', name: 'DEV:proj', sessionId: 'sid-1',
      state: 'idle', tool: null, since: START, at: START, context: 42, paused: false, background: false, item: null,
    })
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
    expect(w.store.get('proj/DEV')).toEqual({ ...kept, at: START, context: 42, paused: false, background: false, item: null })
  })

  test('after a reload, keeps its pause and its item', async ($, on) => {
    const item = { item: 'PR #7', url: 'https://github.com/o/r/pull/7' }
    const kept = {
      project: 'proj', role: 'QA', name: 'QA:proj', sessionId: 'sid-1',
      state: 'idle', tool: null, since: START - 5_000, at: START - 5_000, context: 30, paused: true, item,
    }
    const w = world(on, { 'proj/QA': kept })
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    expect(w.store.get('proj/QA')).toEqual({ ...kept, at: START, context: 42, background: false })
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

describe('the item: the issue or PR its session last acted on with gh (agent-squad #222)', () => {
  // Each form, with what the key holds after it; the session's remote is git@github.com:o/r.git.
  const issue = (n: number) => ({ item: `#${n}`, url: `https://github.com/o/r/issues/${n}` })
  const pr = (n: number) => ({ item: `PR #${n}`, url: `https://github.com/o/r/pull/${n}` })
  const forms: [string, { item: string; url: string | null }][] = [
    ['gh issue edit 11 --add-label "x" --remove-label "y"', issue(11)],
    ['gh issue comment 12 --body-file /tmp/body.md', issue(12)],
    ['gh issue view 13 --json title,body', issue(13)],
    ['gh issue close 14 --comment "done"', issue(14)],
    ['gh pr view 21 --json headRefOid', pr(21)],
    ['gh pr checkout 22 --detach', pr(22)],
    ['gh pr review 23 --comment --body-file review.md', pr(23)],
    ['gh pr comment 24 --body "fixed"', pr(24)],
    ['gh pr merge 25 --squash --match-head-commit "$head"', pr(25)],
    ['gh pr edit 26 --add-label "x"', pr(26)],
    ['gh pr view https://github.com/a/b/pull/27', { item: 'PR #27', url: 'https://github.com/a/b/pull/27' }],
    ['gh issue view https://github.com/a/b/issues/28', { item: '#28', url: 'https://github.com/a/b/issues/28' }],
    ['gh issue view 29 --repo a/b', { item: '#29', url: 'https://github.com/a/b/issues/29' }],
    ['gh pr view --repo a/b 30', { item: 'PR #30', url: 'https://github.com/a/b/pull/30' }],
    ['gh issue comment --body-file f 31', issue(31)],
    ['gh pr merge --squash --match-head-commit "$head" 36', pr(36)],
    ['gh pr checkout --detach 37', pr(37)],
    ['rtk gh pr view 32', pr(32)],
    ['cd /work/proj && gh issue edit 33 --add-label x </dev/null >/dev/null', issue(33)],
    ['head=$(gh pr view 34 --json headRefOid --jq .headRefOid)', pr(34)],
    ['gh issue comment 35 --body "see https://github.com/o/r/pull/9; gh pr view 9"', issue(35)],
    ['gh issue comment --body "see https://github.com/o/r/pull/9" 38', issue(38)],
  ]
  for (const [command, item] of forms) {
    test(`${command}`, async ($, on) => {
      const w = world(on)
      await start($, 'DEV:proj')
      await runs($, w, command)
      expect(w.store.get('proj/DEV')).toMatchObject({ item })
    })
  }

  // QA's cases on PR #223: a heredoc body, as the agents write most bodies, is no command and no
  // quote, whatever its apostrophes or its lines say.
  const heredocs: [string, string[], { item: string; url: string | null }][] = [
    ['an apostrophe in a heredoc, then gh pr edit and a single-quoted jq filter (QA-H1)', [
      'cat > "$S/body.md" <<\'EOF\'',
      '**QA:** the CTO\'s decline holds by default.',
      'EOF',
      'gh pr edit 216 --add-label "x" && gh pr view 216 --json labels --jq \'[.labels[].name]\'',
    ], pr(216)],
    ['a heredoc line that starts with gh pr merge, then the real call (QA-H2)', [
      'cat > notes.md <<\'EOF\'',
      'gh pr merge 9 is how DEV merges, after the gate',
      'EOF',
      'gh pr view 216 --json headRefOid',
    ], pr(216)],
    // QA-H3 wrote the apostrophe as \' inside single quotes, which bash refuses (`bash -n` exits 2), so
    // that call would fail and name no item; this is the form bash runs (agent-squad #225).
    ['a closed single-quoted body, then gh pr comment (QA-H3)', [
      "printf '%s\\n' '**QA:** waiting since 21:15, the CTO'\\''s call' > wait.md && gh pr comment 221 --body-file wait.md",
    ], pr(221)],
    ['an unquoted heredoc word, and a gh call in its body', [
      'cat > a.md <<EOF', 'gh issue view 1', 'EOF', 'gh issue comment 230 --body-file a.md',
    ], issue(230)],
    ['a <<- heredoc whose end is indented with a tab', [
      'cat > a.md <<-"END"', '\tgh pr view 2', '\tEND', 'gh pr review 231 --comment --body-file a.md',
    ], pr(231)],
    ['two heredocs on one line, each body left out in turn', [
      'diff <(cat <<A) <(cat <<B)', 'gh pr view 3', 'A', 'gh pr view 4', 'B', 'gh pr view 232',
    ], pr(232)],
    ['a here-string has no body: the next line is a command', [
      'tr a-z A-Z <<<hello', 'gh pr view 233',
    ], pr(233)],
    // agent-squad #225: a << inside quotes opens no heredoc.
    ['a << inside double quotes, then a gh call on the next line', [
      'echo "write bodies with << EOF"', 'gh pr view 234',
    ], pr(234)],
    ['a << inside single quotes, then a gh call on the next line', [
      "echo 'a <<EOF b'", 'gh pr view 235',
    ], pr(235)],
    ['a real heredoc after a quoted << on the same line', [
      'echo "x << y" && cat > a.md <<\'EOF\'', 'gh pr view 1', 'EOF', 'gh pr view 236',
    ], pr(236)],
    ['a double-quoted body over several lines, with a gh line inside it', [
      'git commit -q -m "fix: x', '', 'gh pr view 3 is not a call"', 'gh pr view 237',
    ], pr(237)],
    ['an escaped double quote inside double quotes', [
      'echo "say \\"hi\\" << now"', 'gh pr view 238',
    ], pr(238)],
    // As bash reads it: a heredoc's body starts once the quote its line opened is closed.
    ['a heredoc whose line goes on in a quote over two lines', [
      'cat <<EOF; echo "a', 'b"', 'gh pr view 4', 'EOF', 'gh pr view 239',
    ], pr(239)],
    // agent-squad #227: a comment opens no quote and no heredoc; a # inside a word starts none.
    ['an apostrophe in a comment line, then the call (QA-C1, on PR #226)', [
      "# the CTO's check", 'gh pr view 240',
    ], pr(240)],
    ['an apostrophe in a comment after a command, then the call', [
      "cd /work/proj # don't move", 'gh pr view 241',
    ], pr(241)],
    ['a heredoc named in a comment opens none', [
      '# cat <<EOF would start one', 'gh pr view 242',
    ], pr(242)],
    ['a # inside a word starts no comment: the quote after it still opens', [
      "echo a#b'c", "d' && gh pr view 243",
    ], pr(243)],
    ['a # after ${ starts no comment either', [
      "echo ${#x}'", "' && gh pr view 244",
    ], pr(244)],
    ['a # inside double quotes is text, its apostrophe too', [
      'git commit -q -m "x', "# not a comment, it's text", '" && gh pr view 245',
    ], pr(245)],
    ['gh pr create from a heredoc body: the PR gh prints', [
      'gh pr create --title "x" --body-file - <<\'EOF\'', 'Closes #5; gh pr view 6', 'EOF',
    ], pr(40)],
  ]
  for (const [name, lines, item] of heredocs) {
    test(name, async ($, on) => {
      const w = world(on)
      await start($, 'QA:proj')
      await runs($, w, lines.join('\n'), 'https://github.com/o/r/pull/40\n')
      expect(w.store.get('proj/QA')).toMatchObject({ item })
    })
  }

  test('gh pr create: the new PR, from the address gh prints', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, 'gh pr create --title "feat: x (#62)" --body-file pr.md', 'Creating pull request\nhttps://github.com/o/r/pull/40\n')
    expect(w.store.get('proj/DEV')).toMatchObject({ item: pr(40) })
  })

  test('a command that names no number, or no gh issue or pr call, leaves the item as it was', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, 'gh issue view 50')
    for (const command of [
      'gh pr create --fill', 'gh issue list --label x --limit 1000', 'gh pr view --json number',
      'gh pr checks 51', 'gh api repos/o/r/pulls/52', 'git log -3', 'echo "gh pr view 53"', 'gh pr diff 54',
      "printf '%s' 'gh issue edit 55'", 'echo "done; gh pr view 56"', "git commit -m 'x\ngh pr view 57'",
      // The shell reads #58 as a comment: the call names no number.
      'gh issue view #58', '# gh pr view 59',
    ]) {
      await runs($, w, command, '')
      expect(w.store.get('proj/DEV')).toMatchObject({ item: issue(50) })
    }
  })

  test('a gh call that failed, or another tool, leaves the item as it was', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    w.isError = true
    await runs($, w, 'gh pr view 60')
    expect(w.store.get('proj/DEV')).toMatchObject({ item: null })
    w.isError = false
    await $.tool.call({ tool: 'mcp__shell__run', tool_use_id: 'u-mcp', command: 'gh pr view 61' } as any)
    expect(w.store.get('proj/DEV')).toMatchObject({ item: null })
  })

  test('a repository that is not on GitHub: the item, with no address', async ($, on) => {
    const w = world(on)
    w.remote = 'git@gitlab.com:o/r.git'
    await start($, 'DEV:proj')
    await runs($, w, 'gh issue view 70')
    expect(w.store.get('proj/DEV')).toMatchObject({ item: { item: '#70', url: null } })
  })

  for (const remote of [null, 'unreadable']) {
    test(`a session whose repository is ${remote ?? 'none'} keeps its key, and an item with no address`, async ($, on) => {
      const w = world(on)
      w.remote = remote
      await start($, 'DEV:proj')
      expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle', item: null, at: START })
      await w.clock.advance(60_000)
      expect(w.store.get('proj/DEV')).toMatchObject({ at: START + 60_000 })
      await runs($, w, 'gh pr view 72')
      expect(w.store.get('proj/DEV')).toMatchObject({ state: 'idle', item: { item: 'PR #72', url: null } })
    })
  }

  test('an https remote gives the same address as an ssh one', async ($, on) => {
    const w = world(on)
    w.remote = 'https://github.com/o/r.git'
    await start($, 'DEV:proj')
    await runs($, w, 'gh pr view 71')
    expect(w.store.get('proj/DEV')).toMatchObject({ item: pr(71) })
  })

  test('the item goes with the key at the session end; after a /clear the session goes on with none', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await runs($, w, 'gh pr view 80')
    await $.session.end({ reason: 'clear', sessionId: 'sid-1', resume: { id: 'sid-1' } } as any)
    expect([...w.store.keys()]).toEqual([])
    w.sessionId = 'sid-2'
    await w.clock.advance(60_000)
    expect(w.store.get('proj/DEV')).toMatchObject({ sessionId: 'sid-2', item: null })
  })

  test('no host command is run, and nothing is read from GitHub', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await runs($, w, 'gh pr view 90')
    await w.clock.advance(600_000)
    expect(w.runs).toEqual([])
  })
})

describe('the pause (agent-squad #222)', () => {
  // The step-away commands as the CEO types them, and as /squad-pause.md and the others relay them.
  const pauses = [
    '/squad-pause',
    '/squad-pause-all',
    'The CEO needs the squad stopped at a safe point (`/squad-pause`): follow the part for every agent',
    'The CEO needs every squad stopped at a safe point (`/squad-pause-all`): follow the part for every agent',
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
