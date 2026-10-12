import { describe, expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { asks, says, START, start, stops, turnEnd, turnStart, world } from './world'

// The board in the CTO's session (agent-squad #205, #212, #217, #222, #235, #240, #244, #247): one
// line above the prompt, between two blue rules: each agent of its own project in the order CTO,
// DEV, QA: its state, its signature and role, the role in its colour, the CTO's context from 90%,
// then, unless the agent is idle, a colon and a link to the issue or PR its session works on, `#123`
// or `PR #124`; then, on the right, the squad's part: fast-forward on autopilot, the wordmark and
// the board's release, and the notice of a newer release. A narrow terminal shortens the squad's
// part first, then cuts the agents at their end. A toast when an agent turns to wait for the CEO,
// once per wait. Everything comes from the sessions' keys and one file, nothing from GitHub.

// The signatures, the state marks and the fast-forward of autopilot, as the band draws them.
const SIGN = { CTO: '\u{1F477}\u{1F3FC}‍♂️', DEV: '\u{1F468}\u{1F3FC}‍\u{1F4BB}', QA: '\u{1F469}\u{1F3FC}‍\u{1F52C}' }
const MARK = { working: '\u23F3', reviewing: '\u{1F440}', background: '\u2699\uFE0F', paused: '\u23F8\uFE0F', waits: '\u270B', idle: '\u{1F4A4}', unknown: '\u2753' }
const AUTOPILOT = '\u23E9'

// How many cells a text takes on a terminal: each emoji two, however many code points it has, and
// any other character one.
function cells(text: string): number {
  let width = 0
  let rest = text
  for (const emoji of [...Object.values(SIGN), ...Object.values(MARK), AUTOPILOT]) {
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

// The wordmark, as the world's plugin.json (version 42.0.0) makes it.
const P = 'agent-squad (v42)'
// The line as a terminal of `columns` cells draws it: the agents, then spaces, then the squad's part
// right-aligned (agent-squad #244).
function line(agents: string, squad = P, columns = 120): string {
  return `${agents}${' '.repeat(columns - cells(agents) - cells(squad))}${squad}`
}

// The items the sessions of DEV and QA work on, as their keys hold them.
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
    .filter(key => key !== undefined && !['line', 'rule', 'rule-below', 'squad', 'space'].includes(key))
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
    expect(await part('CTO')).toBe(`${MARK.idle} ${SIGN.CTO}CTO`)
    expect(await part('DEV')).toBe(` │ ${MARK.working} ${SIGN.DEV}DEV: https://github.com/o/r/issues/205#205`)
    expect(await part('QA')).toBe(` │ ${MARK.waits} ${SIGN.QA}QA: https://github.com/o/r/pull/210PR #210`)
    expect(drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.waits} ${SIGN.QA}QA: PR #210`))
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
    expect(await part('CTO')).toBe(`${MARK.working} ${SIGN.CTO}CTO`)
    expect(await part('DEV')).toBe(` │ ${MARK.working} ${SIGN.DEV}DEV`)
    expect(await part('QA')).toBe(` │ ${MARK.reviewing} ${SIGN.QA}QA`)
  })

  test("the CTO's context shows from 90%, and DEV's and QA's never", async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { context: 99 }), 'proj/QA': agent('QA', 'proj', { context: 95 }) })
    w.percent = 89
    await start($, 'CTO:proj')
    await w.clock.settle()
    const below = await band($)
    expect(await below.part('CTO')).toBe(`${MARK.idle} ${SIGN.CTO}CTO`)
    expect(await below.part('DEV')).toBe(` │ ${MARK.idle} ${SIGN.DEV}DEV`)
    expect(await below.part('QA')).toBe(` │ ${MARK.idle} ${SIGN.QA}QA`)
    await below.ui.unmount()
    for (const percent of [90, 96]) {
      w.percent = percent
      await w.clock.advance(60_000)
      const shown = await band($)
      expect(await shown.part('CTO')).toBe(`${MARK.idle} ${SIGN.CTO}CTO (ctx: ${percent}%)`)
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
    expect(first.drawn).toBe(line(`${MARK.paused} ${SIGN.CTO}CTO │ ${MARK.paused} ${SIGN.DEV}DEV: #205 │ ${MARK.reviewing} ${SIGN.QA}QA`))
    await first.ui.unmount()
    w.store.set('proj/DEV', agent('DEV', 'proj', { paused: true, state: 'permission', tool: 'Bash', at: START + 3_000 }))
    w.store.set('proj/QA', agent('QA', 'proj', { paused: true, at: START + 3_000 }))
    await says($, '/squad-resume')
    await w.clock.advance(3_000)
    const { drawn } = await band($)
    expect(drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.waits} ${SIGN.DEV}DEV │ ${MARK.paused} ${SIGN.QA}QA`))
  })

  // agent-squad #240: the line opens with the wordmark and the board's own release.
  test('the line ends with agent-squad, -squad and the release in the blue of the rules, with no bar and no colon', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', ...ISSUE }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { ui, drawn } = await band($)
    const texts = await ui.findAll({ type: 'Text' })
    const style = (text: string) => texts.filter(found => found.text === text).map(found => [found.props.color, found.props.dimColor])
    expect(style('agent')).toEqual([[undefined, undefined]])
    expect(style('-squad')).toEqual([['#0A84FF', undefined]])
    expect(style(' (v42)')).toEqual([['#0A84FF', undefined]])
    expect(drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.unknown} ${SIGN.QA}QA`))
  })

  test("the release is the major version of the plugin.json the mod ships", async ($, on) => {
    const w = world(on)
    w.manifest = '{ "name": "squad-board", "version": "7.3.1" }'
    await start($, 'CTO:proj')
    const { drawn } = await band($)
    expect(drawn.endsWith('   agent-squad (v7)')).toBe(true)
  })

  test('a plugin.json that cannot be read leaves agent-squad alone', async ($, on) => {
    const w = world(on)
    w.manifest = null
    await start($, 'CTO:proj')
    const { drawn } = await band($)
    expect(drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.unknown} ${SIGN.DEV}DEV │ ${MARK.unknown} ${SIGN.QA}QA`, 'agent-squad'))
  })

  test('a plugin.json with no version leaves agent-squad alone', async ($, on) => {
    const w = world(on)
    w.manifest = '{ "name": "squad-board" }'
    await start($, 'CTO:proj')
    const { drawn } = await band($)
    expect(drawn.endsWith('   agent-squad')).toBe(true)
  })

  test('the release is read once, when the board starts: a newer plugin.json shows only after a restart', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    w.manifest = '{ "name": "squad-board", "version": "43.0.0" }'
    await w.clock.advance(600_000)
    const { drawn } = await band($)
    expect(drawn.endsWith(`   ${P}`)).toBe(true)
  })

  test("the CTO's context sits right after the role, before the colon and the item", async ($, on) => {
    const w = world(on, { 'proj/CTO': agent('CTO', 'proj', { sessionId: 'sid-1', state: 'working', item: { item: 'PR #231', url: 'https://github.com/o/r/pull/231' } }) })
    w.percent = 96
    // The CTO's session comes back from its key after a reload, its item with it.
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    const { part } = await band($)
    expect(await part('CTO')).toBe(`${MARK.working} ${SIGN.CTO}CTO (ctx: 96%): https://github.com/o/r/pull/231PR #231`)
  })

  test('a key from an older board names an issue `Issue #N`, and the band shows it as #N', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', item: { item: 'Issue #217', url: 'https://github.com/o/r/issues/217' } }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const { drawn, links } = await band($)
    expect(links.map(link => link.text.replace(String(link.props.href), ''))).toEqual(['#217'])
    expect(drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #217 │ ${MARK.unknown} ${SIGN.QA}QA`))
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
    expect(whole.colorsOf(' │ ')).toEqual(['#0A84FF', '#0A84FF'])
    await whole.ui.unmount()
    // At 45 columns the CTO and DEV fit, then the ellipsis, beside the squad's part.
    const cut = await band($, 45)
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
    expect(drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.reviewing} ${SIGN.QA}QA`))
  })

  test('each links the item its session works on, named an issue or a PR; one with no address, or not https, is no link', async ($, on) => {
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
    expect(drawn).toBe(line(`${MARK.working} ${SIGN.CTO}CTO: #1 │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.paused} ${SIGN.QA}QA: PR #3`))
  })

  test("the CTO's own focus names its item on the band", async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await turnStart($)
    await $.tool.call({ tool: 'Bash', tool_use_id: 'u-cto', command: 'gh issue edit 222 --add-label "🚧 status:in-progress"' } as any)
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

  // agent-squad #244: the squad's part shortens first, step by step, while every agent fits whole;
  // only then are the agents cut, the CTO first and whole; and the squad's part goes only when not
  // even the CTO's part fits beside it.
  test('on a narrow terminal the squad part shortens first, then the agents are cut, the CTO first and whole', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', ...ISSUE }), 'proj/QA': agent('QA', 'proj', { state: 'working', ...PR }) })
    w.latest = '{"tag": "v43", "checkedAt": 1760263200, "attemptedAt": 1760263200}'
    await start($, 'CTO:proj')
    await w.clock.settle()
    // Each emoji takes two cells: the CTO's part takes 8; DEV's 14 and QA's 16, each after a bar of
    // 3; the ellipsis 2; the agents 44 in all. The squad's part takes 17 (agent-squad (v42)), 23 with
    // the notice's version, 49 with the whole notice, and at least 3 cells of space before it.
    const [cto, dev, qa] = [`${MARK.idle} ${SIGN.CTO}CTO`, `${MARK.working} ${SIGN.DEV}DEV: #205`, `${MARK.reviewing} ${SIGN.QA}QA: PR #210`]
    const all = `${cto} │ ${dev} │ ${qa}`
    const [whole, short] = [`${P} → v43 available: /squad-upgrade`, `${P} → v43`]
    const cases: [number, string[], string][] = [
      [120, ['CTO', 'DEV', 'QA'], line(all, whole, 120)],
      [96, ['CTO', 'DEV', 'QA'], line(all, whole, 96)],
      [95, ['CTO', 'DEV', 'QA'], line(all, short, 95)],
      [70, ['CTO', 'DEV', 'QA'], line(all, short, 70)],
      [69, ['CTO', 'DEV', 'QA'], line(all, P, 69)],
      [64, ['CTO', 'DEV', 'QA'], line(all, P, 64)],
      [63, ['CTO', 'DEV'], line(`${cto} │ ${dev} …`, P, 63)],
      [47, ['CTO', 'DEV'], line(`${cto} │ ${dev} …`, P, 47)],
      [46, ['CTO'], line(`${cto} …`, P, 46)],
      [30, ['CTO'], line(`${cto} …`, P, 30)],
      [29, ['CTO'], line(cto, P, 29)],
      [28, ['CTO'], line(cto, P, 28)],
      // Narrower: the squad's part goes, and the agents take the whole band.
      [27, ['CTO', 'DEV'], `${cto} │ ${dev} …`],
      [4, ['CTO'], cto],
    ]
    for (const [columns, keys, drawn] of cases) {
      const cut = await band($, columns)
      expect([columns, cut.keys]).toEqual([columns, keys])
      expect([columns, cut.drawn]).toEqual([columns, drawn])
      await cut.ui.unmount()
    }
  })

  test('on autopilot, fast-forward is the last the squad part gives up, after the notice', async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { state: 'working', ...ISSUE }), 'proj/QA': agent('QA', 'proj', { state: 'working', ...PR }) })
    w.latest = '{"tag": "v43", "checkedAt": 1760263200, "attemptedAt": 1760263200}'
    await start($, 'CTO:proj')
    await says($, '/squad-autopilot')
    await w.clock.settle()
    // Fast-forward and its space take 3 more cells.
    const all = `${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.working} ${SIGN.DEV}DEV: #205 │ ${MARK.reviewing} ${SIGN.QA}QA: PR #210`
    const cases: [number, string][] = [
      [99, line(all, `${AUTOPILOT} ${P} → v43 available: /squad-upgrade`, 99)],
      [98, line(all, `${AUTOPILOT} ${P} → v43`, 98)],
      [73, line(all, `${AUTOPILOT} ${P} → v43`, 73)],
      [72, line(all, `${AUTOPILOT} ${P}`, 72)],
      [67, line(all, `${AUTOPILOT} ${P}`, 67)],
      [66, line(all, P, 66)],
      [64, line(all, P, 64)],
    ]
    for (const [columns, drawn] of cases) {
      const cut = await band($, columns)
      expect([columns, cut.drawn]).toEqual([columns, drawn])
      await cut.ui.unmount()
    }
  })

  // QA's case on PR #213, now with the signatures: the ellipsis must fit too.
  test("the line drawn never takes more cells than the band has, once the CTO's part fits", async ($, on) => {
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
      if (cells(drawn) > columns && columns >= cells(`${MARK.idle} ${SIGN.CTO}CTO (ctx: 96%)`)) {
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
    expect(drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO (ctx: 96%) │ ${MARK.idle} ${SIGN.DEV}DEV │ ${MARK.idle} ${SIGN.QA}QA`))
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
    ['with a background shell after its turn', 'DEV', { background: true }, MARK.background],
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
    await $.tool.call({ tool: 'Bash', tool_use_id: 'u-cto', command: 'gh pr checkout 243' } as any)
    await w.clock.advance(3_000)
    const working = await band($)
    expect(await working.part('CTO')).toBe(`${MARK.working} ${SIGN.CTO}CTO: https://github.com/o/r/pull/243PR #243`)
    await working.ui.unmount()
    await turnEnd($)
    await w.clock.advance(3_000)
    const idle = await band($)
    expect(await idle.part('CTO')).toBe(`${MARK.idle} ${SIGN.CTO}CTO`)
    expect(w.store.get('proj/CTO')).toMatchObject({ item: { item: 'PR #243', url: 'https://github.com/o/r/pull/243' } })
    await idle.ui.unmount()
    await turnStart($)
    await w.clock.advance(3_000)
    const again = await band($)
    expect(await again.part('CTO')).toBe(`${MARK.working} ${SIGN.CTO}CTO: https://github.com/o/r/pull/243PR #243`)
  })
})

describe('a background shell after the turn (agent-squad #264)', () => {
  test('shows the gear with the item; working shows over it; it goes before a pause', async ($, on) => {
    const w = world(on, {
      'proj/DEV': agent('DEV', 'proj', { background: true, ...ISSUE }),
      'proj/QA': agent('QA', 'proj', { state: 'working', background: true, ...PR }),
    })
    await start($, 'CTO:proj')
    await w.clock.settle()
    const first = await band($)
    expect(first.drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.background} ${SIGN.DEV}DEV: #205 │ ${MARK.reviewing} ${SIGN.QA}QA: PR #210`))
    await first.ui.unmount()
    w.store.set('proj/DEV', agent('DEV', 'proj', { background: true, paused: true, at: START + 3_000, ...ISSUE }))
    await w.clock.advance(3_000)
    const { part } = await band($)
    expect(await part('DEV')).toBe(` │ ${MARK.background} ${SIGN.DEV}DEV: https://github.com/o/r/issues/205#205`)
  })

  test("the CTO's own turn that ends with a shell running shows the gear, and its end shows the idle mark", async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    await turnStart($)
    await $.tool.call({ tool: 'Bash', tool_use_id: 'u-cto', command: 'gh pr checkout 265' } as any)
    await stops($, ['shell'])
    await w.clock.advance(3_000)
    const running = await band($)
    expect(await running.part('CTO')).toBe(`${MARK.background} ${SIGN.CTO}CTO: https://github.com/o/r/pull/265PR #265`)
    await running.ui.unmount()
    await turnStart($)
    await stops($)
    await w.clock.advance(3_000)
    const done = await band($)
    expect(await done.part('CTO')).toBe(`${MARK.idle} ${SIGN.CTO}CTO`)
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

describe('the squad part: fast-forward on autopilot, and the notice of a newer release (agent-squad #244)', () => {
  const NOTICE = ' → v43 available: /squad-upgrade'
  const IDLE = `${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.unknown} ${SIGN.DEV}DEV │ ${MARK.unknown} ${SIGN.QA}QA`
  // .agent-squad/latest-release as squad-latest.sh writes it (agent-squad #302).
  const latest = (tag: unknown) => JSON.stringify({ tag, checkedAt: 1760263200, attemptedAt: 1760263200 })

  test("a newer release than the board's shows its notice after the wordmark, in the CTO's yellow", async ($, on) => {
    const w = world(on)
    w.latest = latest('v43')
    await start($, 'CTO:proj')
    const { drawn, colorsOf } = await band($)
    expect(drawn).toBe(line(IDLE, `${P}${NOTICE}`))
    expect(colorsOf(NOTICE)).toEqual(['yellow', 'yellow_FOR_SUBAGENTS_ONLY'])
    expect(colorsOf('-squad')).toEqual(['#0A84FF'])
  })

  // The file is missing, holds the board's own release or an older one, is not the shape
  // squad-latest.sh writes, or the board's release is not known: nothing changes.
  const none: [string, string | null, string | null][] = [
    ['no file', null, null],
    ['the same release', latest('v42'), null],
    ['an older release', latest('v41'), null],
    ['a tag that is not vN, though it reads as a greater number', latest('v1e9'), null],
    ['a bare v', latest('v'), null],
    ['a tag that is no string', latest(43), null],
    ['no tag yet', latest(null), null],
    ['a file that is not JSON', 'v43', null],
    ['a JSON that is no object', '["v43"]', null],
    ['a board whose release is not known', latest('v43'), 'unknown'],
  ]
  for (const [name, file, release] of none) {
    test(`no notice with ${name}`, async ($, on) => {
      const w = world(on)
      w.latest = file
      if (release === 'unknown') w.manifest = null
      await start($, 'CTO:proj')
      const { drawn } = await band($)
      expect(drawn).toBe(line(IDLE, release === 'unknown' ? 'agent-squad' : P))
    })
  }

  test('the file is read again with the keys: the notice comes and goes with it, and no command runs', async ($, on) => {
    const w = world(on)
    await start($, 'CTO:proj')
    const before = await band($)
    expect(before.drawn).toBe(line(IDLE))
    await before.ui.unmount()
    w.latest = latest('v43')
    await w.clock.advance(3_000)
    const after = await band($)
    expect(after.drawn).toBe(line(IDLE, `${P}${NOTICE}`))
    await after.ui.unmount()
    w.latest = null
    await w.clock.advance(3_000)
    expect((await band($)).drawn).toBe(line(IDLE))
    expect(w.runs).toEqual([])
  })

  test('a session whose repository cannot be read shows no notice', async ($, on) => {
    const w = world(on)
    w.remote = 'unreadable'
    w.latest = latest('v43')
    await start($, 'CTO:proj')
    expect((await band($)).drawn).toBe(line(IDLE))
  })

  // The step-away commands as the CEO types them in the CTO's session, and as the CTO relays them.
  for (const command of ['/squad-autopilot', '/squad-autopilot-all']) {
    test(`fast-forward heads the squad part from ${command}, and goes on a resume and on a pause`, async ($, on) => {
      const w = world(on)
      await start($, 'CTO:proj')
      await says($, command)
      await w.clock.advance(3_000)
      const on1 = await band($)
      expect(on1.drawn).toBe(line(IDLE, `${AUTOPILOT} ${P}`))
      await on1.ui.unmount()
      await says($, '/squad-resume')
      await w.clock.advance(3_000)
      const off = await band($)
      expect(off.drawn).toBe(line(IDLE))
      await off.ui.unmount()
      await says($, command)
      await says($, '/squad-pause')
      await w.clock.advance(3_000)
      expect((await band($)).drawn).toBe(line(`${MARK.paused} ${SIGN.CTO}CTO │ ${MARK.unknown} ${SIGN.DEV}DEV │ ${MARK.unknown} ${SIGN.QA}QA`))
    })
  }

  test('fast-forward goes before the wordmark and the notice, and stays after a reload', async ($, on) => {
    const cto = agent('CTO', 'proj', { sessionId: 'sid-1', autopilot: true })
    const w = world(on, { 'proj/CTO': cto })
    w.latest = latest('v43')
    // The CTO's session comes back from its key after a reload, its autopilot with it.
    await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
    await w.clock.settle()
    expect((await band($)).drawn).toBe(line(IDLE, `${AUTOPILOT} ${P}${NOTICE}`))
  })

  test("DEV's own autopilot, typed in its session alone, shows nothing on the CTO's band", async ($, on) => {
    const w = world(on, { 'proj/DEV': agent('DEV', 'proj', { autopilot: true }) })
    await start($, 'CTO:proj')
    await w.clock.settle()
    expect((await band($)).drawn).toBe(line(`${MARK.idle} ${SIGN.CTO}CTO │ ${MARK.idle} ${SIGN.DEV}DEV │ ${MARK.unknown} ${SIGN.QA}QA`))
  })
})
