import { describe, expect, test } from 'claude-code/testing'

import { asks, START, start, turnEnd, turnStart, world } from './world'

// What every squad session publishes (agent-squad #205): its own key, `<project>/<role>`, with
// its state, its context use, its session id and name, and the time; nothing at all in a session
// that is not a squad's.

describe('a session outside the squad', () => {
  test('does nothing: no key, no command, no pane, no host command', async ($, on) => {
    const w = world(on)
    await start($, 'modtest-1')
    await turnStart($)
    await asks($, 'Bash')
    await turnEnd($)
    await w.clock.advance(120_000)
    expect([...w.store.keys()]).toEqual([])
    expect(w.commands).toEqual([])
    expect(w.opened).toEqual([])
    expect(w.runs).toEqual([])
  })
})

describe("a squad session's key", () => {
  test('names the project and the role, and holds the state, context, id, name and time', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    expect([...w.store.keys()]).toEqual(['proj/DEV'])
    expect(w.store.get('proj/DEV')).toEqual({
      project: 'proj', role: 'DEV', name: 'DEV:proj', sessionId: 'sid-1',
      state: 'idle', tool: null, since: START, at: START, context: 42,
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
    expect(w.store.get('proj/DEV')).toEqual({ ...kept, at: START, context: 42 })
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
