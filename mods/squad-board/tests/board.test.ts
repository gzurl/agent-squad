import { describe, expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { asks, START, start, world } from './world'

// The board in the CTO's session (agent-squad #205, #212): one line above the prompt, with each
// agent of its own project in the order CTO, DEV, QA, its state, its context use and a link to its
// item on GitHub, cut at the end where the terminal is narrow; a toast when an agent turns to wait
// for the CEO, once per wait.

// How many cells a text takes on a terminal: the state marks two, any other character one.
function cells(text: string): number {
  let width = 0
  for (const char of text) width += ['\u23F3', '\u270B', '\u{1F4A4}', '\u2753'].includes(char) ? 2 : 1
  return width
}

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

// The band as a terminal of `columns` cells draws it above the CTO's prompt: each agent's part by
// its key, the keys in order, the links, and the whole line.
async function band($: Engine, columns = 120, hasSurvey = false) {
  const ui = await $.ui.mount({
    plugin: 'squad-board', surface: 'terminal', component: 'AbovePrompt',
    props: { hasSurvey, isWorking: false, maxRows: 10, bodyColumns: columns } as any,
  })
  const boxes = await ui.findAll({ type: 'Box' })
  const part = async (role: string) => (await ui.find({ key: role }))?.text ?? ''
  const links = await ui.findAll({ type: 'Link' })
  // The whole line as the person reads it, the engine's own when no Box was drawn; a Link's text
  // holds its href before its label.
  const whole = boxes[0]?.text ?? (await ui.findAll({ type: 'Text' })).map(found => found.text).join('')
  const drawn = links.reduce((text, link) => text.replace(String(link.props.href), ''), whole)
  return { ui, keys: boxes.map(box => box.key).filter(key => key !== undefined), part, links, drawn }
}

describe('where the board is', () => {
  test("above the CTO's prompt, with no pane and no command", async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    expect(w.opened).toEqual([])
    expect(w.commands).toEqual([])
    expect((await band($)).keys).toEqual(['CTO', 'DEV', 'QA'])
  })

  test('the sessions of DEV and QA leave the band to the engine', async ($, on) => {
    const w = world(on)
    await start($, 'DEV:proj')
    const { keys, drawn } = await band($)
    expect(keys).toEqual([])
    expect(drawn).toBe('drawn by the engine')
    expect(w.opened).toEqual([])
    expect(w.commands).toEqual([])
  })

  test('a survey that holds the band goes first', async ($, on) => {
    world(on)
    await start($, 'CTO:proj')
    const { keys, drawn } = await band($, 120, true)
    expect(keys).toEqual([])
    expect(drawn).toBe('drawn by the engine')
  })
})

describe('the line', () => {
  test("each agent of the project, in the order CTO, DEV, QA, between bars; another project's never", async ($, on) => {
    const w = world(on, {
      'proj/DEV': agent('DEV', 'proj', { state: 'working', context: 68 }),
      'proj/QA': agent('QA', 'proj', { state: 'question', context: 33 }),
      'other/DEV': agent('DEV', 'other', { state: 'permission', tool: 'Bash' }),
      'other/CTO': agent('CTO', 'other'),
    })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { keys, part, drawn } = await band($)
    expect(keys).toEqual(['CTO', 'DEV', 'QA'])
    expect(await part('CTO')).toBe('\u{1F4A4} CTO 42%')
    expect(await part('DEV')).toBe(' \u2502 \u23F3 DEV 68% https://github.com/o/r/issues/205#205')
    expect(await part('QA')).toBe(' \u2502 \u270B QA 33% https://github.com/o/r/pull/210PR #210')
    expect(drawn).toBe('\u{1F4A4} CTO 42% \u2502 \u23F3 DEV 68% #205 \u2502 \u270B QA 33% PR #210')
  })

  test('each links the item it works on, from squad-stalls.sh --current; a URL that is not https is no link', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj'), 'proj/QA': agent('QA', 'proj') })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { part, links } = await band($)
    // A Link's text is its href, then its label.
    expect(links.map(link => link.props.href)).toEqual(['https://github.com/o/r/issues/205', 'https://github.com/o/r/pull/210'])
    expect(links.map(link => link.text.replace(String(link.props.href), ''))).toEqual(['#205', 'PR #210'])
    expect(await part('CTO')).not.toContain('#1')
    expect(w.runs).toEqual([
      ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
      ['/work/proj/.agent-squad/playbook/scripts/squad-stalls.sh', '--current'],
    ])
  })

  test('GitHub is read again every three minutes, not on every redraw', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await w.clock.settle()
    await (await band($)).ui.unmount()
    await band($)
    expect(w.runs).toHaveLength(2)
    await w.clock.advance(180_000)
    expect(w.runs).toHaveLength(4)
  })

  test('GitHub unreadable: the agents stay, without links, and the line ends with why', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj') })
    w.currentExit = 1
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { keys, links, part } = await band($, 200)
    expect(links).toEqual([])
    expect(keys).toEqual(['CTO', 'DEV', 'QA', 'github'])
    expect(await part('DEV')).toBe(' \u2502 \u{1F4A4} DEV 30%')
    expect(await part('github')).toBe(' \u2502 GitHub not read: squad-stalls: cannot read the open pull requests; nothing was checked')
  })

  // QA's case on PR #208: links read once may no longer hold when the next read fails.
  test('GitHub unreadable after a read that succeeded: the earlier links go too', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj') })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    const first = await band($)
    expect(first.links).toHaveLength(2)
    await first.ui.unmount()
    w.currentExit = 1
    await w.clock.advance(180_000)
    const { links, part, keys } = await band($, 200)
    expect(links).toEqual([])
    expect(await part('DEV')).toContain('DEV 30%')
    expect(keys).toContain('github')
  })

  test('a key older than three minutes shows the unknown mark and the role alone, and so does a role with no key', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', at: START - 240_000 }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { part } = await band($)
    expect(await part('DEV')).toBe(' \u2502 \u2753 DEV')
    expect(await part('QA')).toBe(' \u2502 \u2753 QA')
  })

  test('a part follows its key: the board rereads the keys every few seconds', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj') })
    await start($, 'CTO:proj')
    w.store.set('proj/DEV', agent('DEV', 'proj', { state: 'permission', tool: 'Bash', at: START + 2_000 }))
    await w.clock.advance(3_000)
    const { part } = await band($)
    expect(await part('DEV')).toBe(' \u2502 \u270B DEV 30%')
  })

  test('on a narrow terminal the line is cut at its end: the CTO first and whole, then only whole parts', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { context: 68 }), 'proj/QA': agent('QA', 'proj') })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    // The CTO's part takes 10 cells (its mark two); DEV's 3 more for the bar and 15 for itself, its
    // link included; QA's 20, its link included; the ellipsis 2. DEV shows from 30 columns, with room
    // for the ellipsis, and the whole line from 48.
    const wide = await band($, 30)
    expect(wide.keys).toEqual(['CTO', 'DEV'])
    expect(wide.drawn).toBe('\u{1F4A4} CTO 42% \u2502 \u{1F4A4} DEV 68% #205 \u2026')
    await wide.ui.unmount()
    const narrow = await band($, 29)
    expect(narrow.keys).toEqual(['CTO'])
    expect(narrow.drawn).toBe('\u{1F4A4} CTO 42% \u2026')
    await narrow.ui.unmount()
    const whole = await band($, 48)
    expect(whole.keys).toEqual(['CTO', 'DEV', 'QA'])
    expect(whole.drawn.endsWith('\u2026')).toBe(false)
    await whole.ui.unmount()
    const tiny = await band($, 4)
    expect(tiny.keys).toEqual(['CTO'])
    expect(tiny.drawn).toBe('\u{1F4A4} CTO 42%')
  })

  // QA's case on PR #213: the ellipsis must fit too.
  test('the line drawn never takes more cells than the band has, once the CTO part fits', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { context: 68 }), 'proj/QA': agent('QA', 'proj') })
    w.current = CURRENT
    await start($, 'CTO:proj')
    await w.clock.settle()
    const over: string[] = []
    for (let columns = 10; columns <= 60; columns++) {
      const { ui, drawn } = await band($, columns)
      if (cells(drawn) > columns) over.push(`${columns}: ${cells(drawn)} cells, ${drawn}`)
      await ui.unmount()
    }
    expect(over).toEqual([])
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
