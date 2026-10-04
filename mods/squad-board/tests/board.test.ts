import { describe, expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { asks, START, start, world } from './world'

// The board in the CTO's session (agent-squad #205): one line per agent of its own project, in
// the order CTO, DEV, QA, with its state, its context use and a link to its item on GitHub; a toast
// when an agent turns to wait for the CEO, once per wait.

// A key as another session of the squad writes it.
function agent(role: string, project: string, fields: Record<string, unknown> = {}) {
  return {
    project, role, name: `${role}:${project}`, sessionId: `sid-${role}-${project}`,
    state: 'idle', tool: null, since: START, at: START, context: 30, ...fields,
  }
}

// What squad-stalls.sh --current prints for the project.
const CURRENT = [
  'DEV\t#205\thttps://github.com/o/r/issues/205\tcarry on with it',
  'QA\tPR #210\thttps://github.com/o/r/pull/210\treview its head abc1234',
  'CTO\t#1\tjavascript:alert(1)\tnot a link',
].join('\n') + '\n'

// The board as the CTO's terminal draws it: each role's line, by its key, and the whole text.
async function board($: Engine) {
  const ui = await $.ui.mount({
    plugin: 'squad-board', surface: 'terminal', component: 'Pane', requestId: 'squad-board',
    props: { title: 'Squad board', isFocused: false, bodyColumns: 100, placement: 'dock' } as any,
  })
  const rows = await ui.findAll({ type: 'Box' })
  const line = async (role: string) => (await ui.find({ key: role }))?.text ?? ''
  return { ui, keys: rows.map(row => row.key).filter(key => key !== undefined), line, links: await ui.findAll({ type: 'Link' }) }
}

describe('where the board is', () => {
  test("the CTO's session opens it, and offers /squad-board to open it again", async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    expect(w.opened).toEqual(['squad-board'])
    expect(w.commands).toEqual(['squad-board'])
  })

  test('the sessions of DEV and QA have no board', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    await start($, 'QA:proj')
    expect(w.opened).toEqual([])
    expect(w.commands).toEqual([])
  })
})

describe('the lines', () => {
  test("one per agent of the project, in the order CTO, DEV, QA; another project's never", async ($, on) => {
    const w = world(on, {
      'proj/DEV': agent('DEV', 'proj', { state: 'working' }),
      'proj/QA': agent('QA', 'proj', { state: 'question', context: 61 }),
      'other/DEV': agent('DEV', 'other', { state: 'permission', tool: 'Bash' }),
      'other/CTO': agent('CTO', 'other'),
    })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { keys, line } = await board($)
    expect(keys).toEqual(['CTO', 'DEV', 'QA'])
    expect(await line('CTO')).toContain('idle')
    expect(await line('CTO')).toContain('ctx 42%')
    expect(await line('DEV')).toContain('\u23F3')
    expect(await line('DEV')).toContain('working')
    expect(await line('DEV')).toContain('ctx 30%')
    expect(await line('DEV')).not.toContain('permission')
    expect(await line('QA')).toContain('\u270B')
    expect(await line('QA')).toContain('waits for you: a question')
    expect(await line('QA')).toContain('ctx 61%')
  })

  test('each links the item it works on, from squad-stalls.sh --current; a URL that is not https is no link', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj'), 'proj/QA': agent('QA', 'proj') })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { line, links } = await board($)
    // A Link's text is its href, then its label.
    expect(links.map(link => link.props.href)).toEqual(['https://github.com/o/r/issues/205', 'https://github.com/o/r/pull/210'])
    expect(links.map(link => link.text.replace(String(link.props.href), ''))).toEqual(['#205', 'PR #210'])
    expect(await line('DEV')).toContain('carry on with it')
    expect(await line('CTO')).not.toContain('not a link')
    expect(w.runs).toEqual([
      ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
      ['/work/proj/.agent-squad/playbook/scripts/squad-stalls.sh', '--current'],
    ])
  })

  test('GitHub is read again every three minutes, not on every redraw', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await w.clock.settle()
    await (await board($)).ui.unmount()
    await board($)
    expect(w.runs).toHaveLength(2)
    await w.clock.advance(180_000)
    expect(w.runs).toHaveLength(4)
  })

  test('GitHub unreadable: the lines stay, without links, and the board says why', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj') })
    w.currentExit = 1
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { ui, links, line } = await board($)
    expect(links).toEqual([])
    expect(await line('DEV')).toContain('idle')
    expect((await ui.findAll({ type: 'Text', text: 'GitHub not read' })).map(found => found.text))
      .toEqual(['GitHub not read: squad-stalls: cannot read the open pull requests; nothing was checked'])
  })

  // QA's case on PR #208: links read once may no longer hold when the next read fails.
  test('GitHub unreadable after a read that succeeded: the earlier links go too', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj') })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    const first = await board($)
    expect(first.links).toHaveLength(2)
    await first.ui.unmount()
    w.currentExit = 1
    await w.clock.advance(180_000)
    const { ui, links, line } = await board($)
    expect(links).toEqual([])
    expect(await line('DEV')).toContain('idle')
    expect(await ui.findAll({ type: 'Text', text: 'GitHub not read' })).toHaveLength(1)
  })

  test('a key older than three minutes reads unknown, and a role with no key too', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', at: START - 240_000 }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { line } = await board($)
    expect(await line('DEV')).toContain('\u2753')
    expect(await line('DEV')).toContain('no sign for 4 min')
    expect(await line('QA')).toContain('\u2753')
    expect(await line('QA')).toContain('no session seen')
  })

  test('a line follows its key: the board rereads the keys every few seconds', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj') })
    await start($, 'CTO:proj')
    w.store.set('proj/DEV', agent('DEV', 'proj', { state: 'permission', tool: 'Bash', at: START + 2_000 }))
    await w.clock.advance(3_000)
    const { line } = await board($)
    expect(await line('DEV')).toContain('waits for you: a permission for Bash')
  })
})

describe('the toasts', () => {
  test('one when DEV or QA turns to wait for the CEO, once per wait', async ($, on) => {
    const w = world(on, { 'proj/QA': agent('QA', 'proj', { state: 'permission', tool: 'Bash' }) })
    await start($, 'CTO:proj')
    await w.clock.advance(9_000)
    expect(w.toasts).toEqual(['QA waits for you: a permission for Bash'])
    // The CTO's own key keeps the waits it showed, so that a reload does not show them again.
    expect(w.store.get('proj/CTO')).toMatchObject({ toasted: [`QA:sid-QA-proj:${START}`] })
    w.store.set('proj/QA', agent('QA', 'proj', { state: 'working', since: START + 10_000, at: START + 10_000 }))
    await w.clock.advance(3_000)
    w.store.set('proj/QA', agent('QA', 'proj', { state: 'question', since: START + 13_000, at: START + 13_000 }))
    await w.clock.advance(6_000)
    expect(w.toasts).toEqual(['QA waits for you: a permission for Bash', 'QA waits for you: a question'])
  })

  test("none for the CTO's own wait, which is on the CEO's screen already", async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await asks($, 'Bash')
    await w.clock.advance(6_000)
    expect(w.toasts).toEqual([])
  })

  test('none again after a reload for a wait already shown', async ($, on) => {
    const wait = agent('QA', 'proj', { state: 'question' })
    const cto = agent('CTO', 'proj', { sessionId: 'sid-1', toasted: [`QA:${wait.sessionId}:${wait.since}`] })
    const w = world(on, { 'proj/QA': wait, 'proj/CTO': cto })
    // A reload runs session.start again, without the SessionStart hook that gave the name.
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    await w.clock.advance(6_000)
    expect(w.toasts).toEqual([])
  })
})
