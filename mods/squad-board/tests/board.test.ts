import { describe, expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { asks, says, START, start, turnEnd, turnStart, world } from './world'

// The board in the CTO's session (agent-squad #205, #212, #217, #222, #235, #240, #247): one line
// above the prompt, between two blue rules, opening with the wordmark and the board's release, then
// each agent of its own project in the order CTO, DEV, QA: its state, its signature and role, the
// role in its colour, the CTO's context from 90%, then, unless the agent is idle, a colon and a link
// to the issue or PR its session last acted on, `#123` or `PR #124`, cut at the end where the
// terminal is narrow; a toast when an agent turns to wait for the CEO, once per wait. Everything
// comes from the sessions' keys, nothing from GitHub.

// The signatures and the state marks, as the band draws them.
const SIGN = { CTO: '\u{1F477}\u{1F3FC}‍♂️', DEV: '\u{1F468}\u{1F3FC}‍\u{1F4BB}', QA: '\u{1F469}\u{1F3FC}‍\u{1F52C}' }
const MARK = { working: '\u23F3', reviewing: '\u{1F440}', paused: '\u23F8\uFE0F', waits: '\u270B', idle: '\u{1F4A4}', unknown: '\u2753' }

// How many cells a text takes on a terminal: each emoji two, however many code points it has, and
// any other character one.
function cells(text: string): number {
  let width = 0
  let rest = text
  for (const emoji of [...Object.values(SIGN), ...Object.values(MARK)]) {
    const pieces = rest.split(emoji)
    width += 2 * (pieces.length - 1)
    rest = pieces.join('')
  }
  return width + [...rest].length
}

// A key as another session of the squad writes it.
function agent(role: string, project: string, fields: Record<string, unknown> = {}) {
  return {
    project, role, name: `${role}:${project}`, sessionId: `sid-${role}-${project}`,
    state: 'idle', tool: null, since: START, at: START, context: 30, ...fields,
  }
}

// The line's prefix, as the world's plugin.json (version 42.0.0) makes it.
const P = 'agent-squad (v42)'

// The items the sessions of DEV and QA last acted on, as their keys hold them.
const ISSUE = { item: { item: '#205', url: 'https://github.com/o/r/issues/205' } }
const PR = { item: { item: 'PR #210', url: 'https://github.com/o/r/pull/210' } }

// The band as a terminal of `columns` cells draws it above the CTO's prompt: the rules above and
// below, each agent's part by its key, the keys in order, the links, and the whole line.
async function band($: Engine, columns = 120, hasSurvey = false) {
  const ui = await $.ui.mount({
    plugin: 'squad-board', surface: 'terminal', component: 'AbovePrompt',
    props: { hasSurvey, isWorking: false, maxRows: 10, bodyColumns: columns } as any,
  })
  const line = await ui.find({ key: 'line' })
  const keys = (await ui.findAll({ type: 'Box' })).map(box => box.key)
    .filter(key => key !== undefined && !['line', 'rule', 'rule-below', 'prefix'].includes(key))
  const part = async (role: string) => (await ui.find({ key: role }))?.text ?? ''
  const rule = (await ui.find({ key: 'rule' }))?.text ?? ''
  const ruleBelow = (await ui.find({ key: 'rule-below' }))?.text ?? ''
  const links = await ui.findAll({ type: 'Link' })
  // The texts drawn, the colour of the first that reads `text`, and the colours of all that do,
  // outermost first.
  const texts = await ui.findAll({ type: 'Text' })
  const colorOf = (text: string) => texts.find(found => found.text === text)?.props.color
  const colorsOf = (text: string) => texts.filter(found => found.text === text).map(found => found.props.color)
  // The colours of the texts that draw the rules.
  const ruleColors = rule === '' ? [] : texts.filter(found => found.text === rule).map(found => found.props.color)
  // The whole line as the person reads it, the engine's own when the board drew none; a Link's text
  // holds its href before its label.
  const whole = line?.text ?? (await ui.findAll({ type: 'Text' })).map(found => found.text).join('')
  const drawn = links.reduce((text, link) => text.replace(String(link.props.href), ''), whole)
  return { ui, keys, part, rule, ruleBelow, ruleColors, colorOf, colorsOf, links, drawn }
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
  test("each agent of the project, its state, signature and role, then a colon and its item; another project's never", async ($, on) => {
    const w = world(on, {
      'proj/DEV': agent('DEV', 'proj', { state: 'working', context: 68, ...ISSUE }),
      'proj/QA': agent('QA', 'proj', { state: 'question', context: 33, ...PR }),
      'other/DEV': agent('DEV', 'other', { state: 'permission', tool: 'Bash', item: { item: 'PR #1', url: 'https://github.com/x/y/pull/1' } }),
      'other/CTO': agent('CTO', 'other'),
    })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { keys, part, drawn } = await band($)
    expect(keys).toEqual(['CTO', 'DEV', 'QA'])
    expect(await part('CTO')).toBe(` │ ${MARK.idle} ${SIGN.CTO}CTO`)
    expect(await part('DEV')).toBe(` │ ${MARK.working} ${SIGN.DEV}DEV: https://github.com/o/r/issues/205#205`)
    expect(await part('QA')).toBe(` │ ${MARK.waits} ${SIGN.QA}QA: https://github.com/o/r/pull/210PR #210`)
    expect(drawn).toBe(`${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.waits} ${SIGN.QA}QA: PR #210`)
  })

  test('working is an hourglass for the CTO and DEV, and eyes for QA, who reviews', async ($, on) => {
    const w = world(on, {
      'proj/DEV': agent('DEV', 'proj', { state: 'working' }),
      'proj/QA': agent('QA', 'proj', { state: 'working' }),
    })
    await start($, 'CTO:proj')
    await $.turn.start({ text: 'go', turnId: 't1' })
    await w.clock.advance(3_000)
    const { part } = await band($)
    expect(await part('CTO')).toBe(` │ ${MARK.working} ${SIGN.CTO}CTO`)
    expect(await part('DEV')).toBe(` │ ${MARK.working} ${SIGN.DEV}DEV`)
    expect(await part('QA')).toBe(` │ ${MARK.reviewing} ${SIGN.QA}QA`)
  })

  test("the CTO's context shows from 90%, and DEV's and QA's never", async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { context: 99 }), 'proj/QA': agent('QA', 'proj', { context: 95 }) })
    w.percent = 89
    await start($, 'CTO:proj')
    await w.clock.settle()
    const below = await band($)
    expect(await below.part('CTO')).toBe(` │ ${MARK.idle} ${SIGN.CTO}CTO`)
    expect(await below.part('DEV')).toBe(` │ ${MARK.idle} ${SIGN.DEV}DEV`)
    expect(await below.part('QA')).toBe(` │ ${MARK.idle} ${SIGN.QA}QA`)
    await below.ui.unmount()
    for (const percent of [90, 96]) {
      w.percent = percent
      await w.clock.advance(60_000)
      const shown = await band($)
      expect(await shown.part('CTO')).toBe(` │ ${MARK.idle} ${SIGN.CTO}CTO (ctx: ${percent}%)`)
      await shown.ui.unmount()
    }
  })

  test('paused is its own mark while the agent is idle; working and waiting show over it', async ($, on) => {
    const w = world(on, {
      'proj/DEV': agent('DEV', 'proj', { paused: true, ...ISSUE }),
      'proj/QA': agent('QA', 'proj', { state: 'working', paused: true }),
    })
    await start($, 'CTO:proj')
    await says($, '/squad-pause')
    await w.clock.advance(3_000)
    const first = await band($)
    expect(first.drawn).toBe(`${P} │ ${MARK.paused} ${SIGN.CTO}CTO │ ${MARK.paused} ${SIGN.DEV}DEV: #205 │ ${MARK.reviewing} ${SIGN.QA}QA`)
    await first.ui.unmount()
    w.store.set('proj/DEV', agent('DEV', 'proj', { paused: true, state: 'permission', tool: 'Bash', at: START + 3_000 }))
    w.store.set('proj/QA', agent('QA', 'proj', { paused: true, at: START + 3_000 }))
    await says($, '/squad-resume')
    await w.clock.advance(3_000)
    const { drawn } = await band($)
    expect(drawn).toBe(`${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.waits} ${SIGN.DEV}DEV │ ${MARK.paused} ${SIGN.QA}QA`)
  })

  // agent-squad #240: the line opens with the wordmark and the board's own release.
  test('the line opens with agent-squad, -squad and the release in the blue of the rules, then a bar; no colon', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', ...ISSUE }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { ui, drawn } = await band($)
    const texts = await ui.findAll({ type: 'Text' })
    const style = (text: string) => texts.filter(found => found.text === text).map(found => [found.props.color, found.props.dimColor])
    expect(style('agent')).toEqual([[undefined, undefined]])
    expect(style('-squad')).toEqual([['#0A84FF', undefined]])
    expect(style(' (v42)')).toEqual([['#0A84FF', undefined]])
    expect(drawn).toBe(`${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.unknown} ${SIGN.QA}QA`)
  })

  test("the release is the major version of the plugin.json the mod ships", async ($, on) => {
    const w = world(on)
    w.manifest = '{ "name": "squad-board", "version": "7.3.1" }'
    await start($, 'CTO:proj')
    const { drawn } = await band($)
    expect(drawn.startsWith('agent-squad (v7) │ ')).toBe(true)
  })

  test('a plugin.json that cannot be read leaves agent-squad alone', async ($, on) => {
    const w = world(on)
    w.manifest = null
    await start($, 'CTO:proj')
    const { drawn } = await band($)
    expect(drawn).toBe(`agent-squad │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.unknown} ${SIGN.DEV}DEV │ ${MARK.unknown} ${SIGN.QA}QA`)
  })

  test('a plugin.json with no version leaves agent-squad alone', async ($, on) => {
    const w = world(on)
    w.manifest = '{ "name": "squad-board" }'
    await start($, 'CTO:proj')
    const { drawn } = await band($)
    expect(drawn.startsWith('agent-squad │ ')).toBe(true)
  })

  test('the release is read once, when the board starts: a newer plugin.json shows only after a restart', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    w.manifest = '{ "name": "squad-board", "version": "43.0.0" }'
    await w.clock.advance(600_000)
    const { drawn } = await band($)
    expect(drawn.startsWith(`${P} │ `)).toBe(true)
  })

  test("the CTO's context sits right after the role, before the colon and the item", async ($, on) => {
    const w = world(on, { 'proj/CTO': agent('CTO', 'proj', { sessionId: 'sid-1', state: 'working', item: { item: 'PR #231', url: 'https://github.com/o/r/pull/231' } }) })
    w.percent = 96
    // The CTO's session comes back from its key after a reload, its item with it.
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    const { part } = await band($)
    expect(await part('CTO')).toBe(` │ ${MARK.working} ${SIGN.CTO}CTO (ctx: 96%): https://github.com/o/r/pull/231PR #231`)
  })

  test('a key from an older board names an issue `Issue #N`, and the band shows it as #N', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', item: { item: 'Issue #217', url: 'https://github.com/o/r/issues/217' } }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { drawn, links } = await band($)
    expect(links.map(link => link.text.replace(String(link.props.href), ''))).toEqual(['#217'])
    expect(drawn).toBe(`${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #217 │ ${MARK.unknown} ${SIGN.QA}QA`)
  })

  test('a blue rule of light horizontal lines across the band, above the line and below it', async ($, on) => {
    world(on)
    await start($, 'CTO:proj')
    for (const columns of [10, 66, 120]) {
      const { ui, rule, ruleBelow, ruleColors } = await band($, columns)
      expect(rule).toBe('─'.repeat(columns))
      expect(ruleBelow).toBe(rule)
      expect(ruleColors).toEqual(['#0A84FF', '#0A84FF'])
      await ui.unmount()
    }
  })

  test('the bars between the agents are in the blue of the rules; the ellipsis of a cut stays dim', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', ISSUE), 'proj/QA': agent('QA', 'proj', PR) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const whole = await band($)
    expect(whole.colorsOf(' │ ')).toEqual(['#0A84FF', '#0A84FF', '#0A84FF'])
    await whole.ui.unmount()
    const cut = await band($, 32)
    const ellipsis = (await cut.ui.findAll({ type: 'Text' })).find(found => found.text === ' …')
    expect(cut.colorsOf(' │ ')).toEqual(['#0A84FF'])
    expect(ellipsis?.props.dimColor).toBe(true)
  })

  // The theme keys are undocumented: a key Claude Code does not know paints nothing, so the plain
  // colour of the text around it shows (agent-squad #222, the live probe in its evidence).
  test("each role's name in the colour its session gets with /color: the CTO yellow, DEV blue, QA green, the plain colour around the theme's", async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', ...ISSUE }), 'proj/QA': agent('QA', 'proj', { state: 'working' }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { colorOf, colorsOf, drawn } = await band($)
    expect(colorsOf('CTO')).toEqual(['yellow', 'yellow_FOR_SUBAGENTS_ONLY'])
    expect(colorsOf('DEV')).toEqual(['blue', 'blue_FOR_SUBAGENTS_ONLY'])
    expect(colorsOf('QA')).toEqual(['green', 'green_FOR_SUBAGENTS_ONLY'])
    // The mark, the signature and the item keep the terminal's own colour.
    expect(colorOf(`${MARK.working} ${SIGN.DEV}`)).toBeUndefined()
    expect(drawn).toBe(`${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.reviewing} ${SIGN.QA}QA`)
  })

  test('each links the item its session last acted on, named an issue or a PR; one with no address, or not https, is no link', async ($, on) => {
    const w = world(on, {
      'proj/CTO': agent('CTO', 'proj', { sessionId: 'sid-1', state: 'working', item: { item: 'Issue #1', url: 'javascript:alert(1)' } }),
      'proj/DEV': agent('DEV', 'proj', { state: 'working', ...ISSUE }),
      'proj/QA': agent('QA', 'proj', { paused: true, item: { item: 'PR #3', url: null } }),
    })
    // The CTO's session comes back from its key after a reload, its item with it.
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    const { links, drawn } = await band($)
    // A Link's text is its href, then its label.
    expect(links.map(link => link.props.href)).toEqual(['https://github.com/o/r/issues/205'])
    expect(links.map(link => link.text.replace(String(link.props.href), ''))).toEqual(['#205'])
    expect(drawn).toBe(`${P} │ ${MARK.working} ${SIGN.CTO}CTO: #1 │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.paused} ${SIGN.QA}QA: PR #3`)
  })

  test("the CTO's own gh call names its item on the band", async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await turnStart($)
    await $.tool.call({ tool: 'Bash', tool_use_id: 'u-cto', command: 'gh issue edit 222 --add-label "x"' } as any)
    await w.clock.advance(3_000)
    const { links } = await band($)
    expect(links.map(link => link.props.href)).toEqual(['https://github.com/o/r/issues/222'])
  })

  test('nothing is read from GitHub, and no host command runs, however long the board is drawn', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', ISSUE) })
    await start($, 'CTO:proj')
    for (let minute = 0; minute < 10; minute++) {
      await (await band($)).ui.unmount()
      await w.clock.advance(60_000)
    }
    expect(w.runs).toEqual([])
  })

  test('a key older than three minutes shows the unknown mark, with the item it last held; a role with no key, the mark alone', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', at: START - 240_000, ...ISSUE }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { part } = await band($)
    expect(await part('DEV')).toBe(` │ ${MARK.unknown} ${SIGN.DEV}DEV: https://github.com/o/r/issues/205#205`)
    expect(await part('QA')).toBe(` │ ${MARK.unknown} ${SIGN.QA}QA`)
  })

  test('a part follows its key: the board rereads the keys every few seconds', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj') })
    await start($, 'CTO:proj')
    w.store.set('proj/DEV', agent('DEV', 'proj', { state: 'permission', tool: 'Bash', at: START + 2_000 }))
    await w.clock.advance(3_000)
    const { part } = await band($)
    expect(await part('DEV')).toBe(` │ ${MARK.waits} ${SIGN.DEV}DEV`)
  })

  test('on a narrow terminal the line is cut at its end: the CTO first and whole, then only whole parts', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', ...ISSUE }), 'proj/QA': agent('QA', 'proj', { state: 'working', ...PR }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    // Each emoji takes two cells: the prefix takes 17 (agent-squad (v42)); the CTO's part 3 for the
    // bar and 8 for itself; DEV's 3 and 14 (its mark, signature and role, then ': #205'); QA's 3 and
    // 16; the ellipsis 2. The CTO shows from 30 columns, DEV from 47, and the whole line from 64.
    const cases: [number, string[], string][] = [
      [29, [], `${P} …`],
      [30, ['CTO'], `${P} │ ${MARK.idle} ${SIGN.CTO}CTO …`],
      [46, ['CTO'], `${P} │ ${MARK.idle} ${SIGN.CTO}CTO …`],
      [47, ['CTO', 'DEV'], `${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 …`],
      [63, ['CTO', 'DEV'], `${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 …`],
      [64, ['CTO', 'DEV', 'QA'], `${P} │ ${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.reviewing} ${SIGN.QA}QA: PR #210`],
      // Narrower than the prefix: the prefix alone, which the surface cuts at the edge.
      [4, [], P],
    ]
    for (const [columns, keys, drawn] of cases) {
      const cut = await band($, columns)
      expect([columns, cut.keys]).toEqual([columns, keys])
      expect(cut.drawn).toBe(drawn)
      await cut.ui.unmount()
    }
  })

  // QA's case on PR #213, now with the signatures: the ellipsis must fit too.
  test('the line drawn never takes more cells than the band has, once the prefix fits', async ($, on) => {
    const w = world(on, {
      'proj/DEV': agent('DEV', 'proj', { paused: true, ...ISSUE }),
      'proj/QA': agent('QA', 'proj', { state: 'working', ...PR }),
    })
    w.percent = 96
    await start($, 'CTO:proj')
    await w.clock.settle()
    const over: string[] = []
    for (let columns = 10; columns <= 80; columns++) {
      const { ui, drawn } = await band($, columns)
      if (cells(drawn) > columns && columns >= cells(P)) {
        over.push(`${columns}: ${cells(drawn)} cells, ${drawn}`)
      }
      await ui.unmount()
    }
    expect(over).toEqual([])
  })
})

describe('an idle agent shows its role alone (agent-squad #247)', () => {
  test('idle hides the item and its colon, the CTO keeps its context, and each key keeps its item', async ($, on) => {
    const cto = agent('CTO', 'proj', { sessionId: 'sid-1', item: { item: 'PR #243', url: 'https://github.com/o/r/pull/243' } })
    const w = world(on, { 'proj/CTO': cto, 'proj/DEV': agent('DEV', 'proj', ISSUE), 'proj/QA': agent('QA', 'proj', PR) })
    w.percent = 96
    // The CTO's session comes back from its key after a reload, its item with it.
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    const { drawn, links } = await band($)
    expect(drawn).toBe(`${P} │ ${MARK.idle} ${SIGN.CTO}CTO (ctx: 96%) │ ${MARK.idle} ${SIGN.DEV}DEV │ ${MARK.idle} ${SIGN.QA}QA`)
    expect(links).toEqual([])
    expect(w.store.get('proj/CTO')).toMatchObject({ item: cto.item })
    expect(w.store.get('proj/DEV')).toMatchObject(ISSUE)
    expect(w.store.get('proj/QA')).toMatchObject(PR)
  })

  // Every state but idle shows the item: working, reviewing, waiting for the CEO, paused, and the
  // unknown mark of a key gone stale.
  const shown: [string, string, Record<string, unknown>, string][] = [
    ['working', 'DEV', { state: 'working' }, MARK.working],
    ['reviewing', 'QA', { state: 'working' }, MARK.reviewing],
    ['waiting on a permission', 'DEV', { state: 'permission', tool: 'Bash' }, MARK.waits],
    ['waiting on a question', 'QA', { state: 'question' }, MARK.waits],
    ['paused', 'DEV', { paused: true }, MARK.paused],
    ['unknown, its key gone stale', 'QA', { state: 'working', at: START - 240_000 }, MARK.unknown],
  ]
  for (const [name, role, fields, mark] of shown) {
    test(`${name}: the item shows`, async ($, on) => {
      const w = world(on, { [`proj/${role}`]: agent(role, 'proj', { ...fields, ...ISSUE }) })
      await start($, 'CTO:proj')
      await w.clock.settle()
      const { part } = await band($)
      expect(await part(role)).toBe(` │ ${mark} ${SIGN[role as keyof typeof SIGN]}${role}: https://github.com/o/r/issues/205#205`)
    })
  }

  test('idle, then back to work: the same item shows again, with no new gh call', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await turnStart($)
    await $.tool.call({ tool: 'Bash', tool_use_id: 'u-cto', command: 'gh pr view 243' } as any)
    await w.clock.advance(3_000)
    const working = await band($)
    expect(await working.part('CTO')).toBe(` │ ${MARK.working} ${SIGN.CTO}CTO: https://github.com/o/r/pull/243PR #243`)
    await working.ui.unmount()
    await turnEnd($)
    await w.clock.advance(3_000)
    const idle = await band($)
    expect(await idle.part('CTO')).toBe(` │ ${MARK.idle} ${SIGN.CTO}CTO`)
    expect(w.store.get('proj/CTO')).toMatchObject({ item: { item: 'PR #243', url: 'https://github.com/o/r/pull/243' } })
    await idle.ui.unmount()
    await turnStart($)
    await w.clock.advance(3_000)
    const again = await band($)
    expect(await again.part('CTO')).toBe(` │ ${MARK.working} ${SIGN.CTO}CTO: https://github.com/o/r/pull/243PR #243`)
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
