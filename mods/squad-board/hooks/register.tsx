import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { BoardAgent, BoardAgents, BoardItem, BoardRole, BoardState } from '../types'

// The squad board (agent-squad #205, #212, #217, #222, #235, #240). Every session of a squad
// publishes its own state in this mod's store, under `<project>/<role>`, and only that key: what it
// is doing, whether the CEO paused it, and the last issue or PR its agent acted on with gh. The
// CTO's session reads its project's keys and draws them on one line above its prompt, after the
// wordmark and the board's release, and shows a toast when an agent waits for the CEO. The band shows each session's own state, not GitHub's: nothing is read from
// GitHub, and no command is run. A session whose name is not a squad role's does nothing. The
// signals are the ones agent-squad #199 measured.

const ROLES: readonly BoardRole[] = ['CTO', 'DEV', 'QA']
// How often a session rewrites its key, and how old a key may grow before its part reads unknown.
const HEARTBEAT_MS = 60_000
const STALE_MS = 180_000
// How often the CTO's session reads the keys.
const TICK_MS = 3_000
// The state marks of SQUAD.md §6, written as escapes since emojis stay out of code: hourglass
// (working), eyes (QA working, since it reviews), pause (paused by the CEO; a text character made an
// emoji by its selector), raised hand (waits for the CEO), zzz (idle), question mark (no recent
// state).
const MARK = {
  working: '\u23F3', reviewing: '\u{1F440}', paused: '\u23F8\uFE0F', waits: '\u270B', idle: '\u{1F4A4}',
  unknown: '\u2753',
}
// The members' signatures of SQUAD.md §6, as escapes: each a person, a skin tone, a joiner and what
// they do (and for the CTO a presentation selector), which a terminal draws as one emoji.
const SIGNATURE: Record<BoardRole, string> = {
  CTO: '\u{1F477}\u{1F3FC}\u200D\u2642\uFE0F',
  DEV: '\u{1F468}\u{1F3FC}\u200D\u{1F4BB}',
  QA: '\u{1F469}\u{1F3FC}\u200D\u{1F52C}',
}
// Every emoji the band draws takes two cells of a terminal, however many code points it has, as
// Claude Code measures it; every other character one. The longest are matched first. A terminal
// that draws the pause in one cell leaves the line one cell shorter, which the cut allows for.
const WIDE = [...new Set([...Object.values(SIGNATURE), ...Object.values(MARK)])].sort((a, b) => b.length - a.length)
// Between two agents, a light vertical bar; where the band is cut, an ellipsis; above the agents and
// below them, a rule of light horizontal lines across the band. The bars and the rules are in the
// blue of cmux's active pane.
const SEPARATOR = ' \u2502 '
const ELLIPSIS = ' \u2026'
const RULE = '\u2500'
const RULE_COLOR = '#0A84FF'
// Each role's name in the colour its session gets with /color (agent-squad #222): the theme key
// Claude Code paints that colour with, in every theme, inside the plain colour of the same name. The
// keys are undocumented and may change in any release; a key Claude Code does not know paints
// nothing, so the plain colour around it shows instead. A mod cannot read a session's /color, so
// the colours are fixed here, and the README says which /color each session takes.
const ROLE_COLOR: Record<BoardRole, { key: string; plain: string }> = {
  CTO: { key: 'yellow_FOR_SUBAGENTS_ONLY', plain: 'yellow' },
  DEV: { key: 'blue_FOR_SUBAGENTS_ONLY', plain: 'blue' },
  QA: { key: 'green_FOR_SUBAGENTS_ONLY', plain: 'green' },
}
// The CTO's context shows from this share of its window, as the CEO decided (agent-squad #217).
const CONTEXT_FROM = 90

const agents = atom({ plugin: 'squad-board', key: 'agents' } as const, { byRole: {}, now: 0 } as BoardAgents)

// This session: the title it started with, who it is once that title names a squad role, whether
// its work has started, what it is doing, whether the CEO paused it, the last item its agent acted
// on, and its repository's web address. A reload starts all of it over (recover, below).
let title: string | null = null
let me: { project: string; role: BoardRole; name: string } | null = null
let isStarted = false
let isActive = false
let state: BoardState = 'idle'
let tool: string | null = null
let since = 0
let isPaused = false
let item: BoardItem | null = null
let repository: string | null = null
// The CTO's session only: the release its board belongs to, as `v42`, read once when the board starts.
let release: string | null = null
// The CTO's session only: the waits it has already shown a toast for.
let toasted: string[] = []

// A squad session's name is `ROLE:<project>` or `<project>:ROLE` (SQUAD.md §1); any other is not.
function squadName(name: string): { project: string; role: BoardRole } | null {
  const roleFirst = /^(CTO|DEV|QA):(.+)$/.exec(name)
  if (roleFirst) return { role: roleFirst[1] as BoardRole, project: roleFirst[2] }
  const roleLast = /^(.+):(CTO|DEV|QA)$/.exec(name)
  if (roleLast) return { role: roleLast[2] as BoardRole, project: roleLast[1] }
  return null
}

// Takes the session's name as its identity, when it names a squad role.
function identify(name: string | undefined) {
  if (me || !name) return
  title = name
  const found = squadName(name)
  if (found) me = { ...found, name }
}

function keyOf(project: string, role: BoardRole): string {
  return `${project}/${role}`
}

// Whether a stored value is a session's key, whole.
function isAgent(value: unknown): value is BoardAgent {
  const v = value as BoardAgent | null
  return typeof v === 'object' && v !== null && typeof v.project === 'string' && ROLES.includes(v.role)
    && typeof v.name === 'string' && typeof v.sessionId === 'string' && typeof v.state === 'string'
    && typeof v.since === 'number' && typeof v.at === 'number'
}

function isWaiting(now: BoardState): boolean {
  return now === 'permission' || now === 'question'
}

// What a wait is, in the words the toast uses.
function waitText(agent: BoardAgent): string {
  return agent.state === 'question' ? 'a question' : `a permission for ${agent.tool ?? 'a tool'}`
}

// A GitHub repository's web address from a git remote, https or ssh; null for any other host.
function webOf(remote: string | null): string | null {
  const found = /github\.com[:/]([^/\s]+)\/([^/\s]+?)(?:\.git)?\/?$/.exec(remote ?? '')
  return found ? `https://github.com/${found[1]}/${found[2]}` : null
}

// An issue or PR from its GitHub web address; null for any other text.
function itemAt(text: string): BoardItem | null {
  const found = /https:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/(issues|pull)\/(\d+)/.exec(text)
  if (!found) return null
  return { item: `${found[3] === 'pull' ? 'PR ' : ''}#${found[4]}`, url: `https://github.com/${found[1]}/${found[2]}/${found[3]}/${found[4]}` }
}

// A command as the parser reads it (agent-squad #225), scanned as the shell does: each quoted string
// becomes '', and each heredoc's body is left out, from the line after its `<<WORD` or `<<-WORD`,
// the word quoted or not, up to the line that holds the word alone. A `<<` inside quotes opens no
// heredoc, nor does a here-string (`<<<`). A single quote ends at the next one; a double quote
// ends at the next one that no backslash escapes, and may span lines. A `#` that starts a word
// outside quotes starts a comment, which runs to the end of its line and opens nothing (#227).
function bareOf(command: string): string {
  let bare = ''
  let quote: string | null = null
  const ends: string[] = []
  for (const line of command.split('\n')) {
    // A heredoc's body: skipped whole, up to the line that ends it.
    if (quote === null && ends.length > 0) {
      if (line.trim() === ends[0]) ends.shift()
      continue
    }
    let i = 0
    while (i < line.length) {
      const c = line[i]
      if (quote !== null) {
        if (quote === '"' && c === '\\') i += 2
        else {
          if (c === quote) quote = null
          i += 1
        }
        continue
      }
      if (c === '#' && (i === 0 || /[\s;&|()<>]/.test(line[i - 1]))) break
      const heredoc = line[i - 1] === '<' ? null : /^<<-?\s*(['"]?)([A-Za-z_]\w*)\1/.exec(line.slice(i))
      if (heredoc) {
        ends.push(heredoc[2])
        bare += '<<'
        i += heredoc[0].length
      } else if (c === '\\') {
        bare += line.slice(i, i + 2)
        i += 2
      } else if (c === '"' || c === "'") {
        quote = c
        bare += "''"
        i += 1
      } else {
        bare += c
        i += 1
      }
    }
    if (quote === null) bare += '\n'
  }
  return bare
}

// The issue or PR a gh command acts on (agent-squad #222): the first `gh issue` or `gh pr` the
// command runs, at its start or after a separator, with its heredoc bodies and its quoted text left
// out (bareOf), so that a body or a title is never read as a command or as its target.
// - issue edit, comment, view or close, and pr view, checkout, review, comment, merge or edit:
//   their first number or GitHub address, flags before it or not; `--repo owner/name` names
//   another repository than the session's;
// - pr create: the address of the new PR, which gh prints.
// Null for any other command, and for one that names no number.
function itemOf(command: string, output: string, home: string | null): BoardItem | null {
  const bare = bareOf(command)
  const call = /(?:^|[\n;&|(]\s*)(?:rtk\s+)?gh\s+(issue|pr)\s+([a-z]+)\b([^\n;&|)]*)/.exec(bare)
  if (!call) return null
  const [, noun, verb, rest] = call
  const verbs = noun === 'issue' ? ['edit', 'comment', 'view', 'close'] : ['create', 'view', 'checkout', 'review', 'comment', 'merge', 'edit']
  if (!verbs.includes(verb)) return null
  if (verb === 'create') return itemAt(output)
  const target = rest.trim().split(/\s+/).find(token => /^(\d+|https:\/\/\S+)$/.test(token))
  if (!target) return null
  if (target.startsWith('https://')) return itemAt(target)
  const other = /(?:^|\s)(?:-R|--repo)[\s=]([^\s/]+\/[^\s/]+)/.exec(rest)
  const base = other ? `https://github.com/${other[1]}` : home
  return { item: `${noun === 'pr' ? 'PR ' : ''}#${target}`, url: base ? `${base}/${noun === 'pr' ? 'pull' : 'issues'}/${target}` : null }
}

// The step-away commands of SQUAD.md §6 a prompt carries, typed (the prompt starts with the
// command) or relayed (the relay names it in parentheses, then a colon and its instruction, as
// `(`/squad-pause`): follow`): a pause sets the session's pause; a resume, or autopilot, clears it.
// A message that only quotes the form, with no colon after it, is no relay. Each command's own file
// names only itself that way, so an expanded command reads the same. Null for any other prompt.
function stepAwayOf(text: string): 'pause' | 'clear' | null {
  const found = /^\s*\/squad-(pause|resume|autopilot)(?:-all)?\b/.exec(text) ?? /\(`\/squad-(pause|resume|autopilot)(?:-all)?`\):/.exec(text)
  if (!found) return null
  return found[1] === 'pause' ? 'pause' : 'clear'
}

// One part of the band (agent-squad #235): an agent's role, its state mark, the CTO's context when
// it shows, and its item when it has one.
type Part = { key: BoardRole; mark: string; context: string; item: BoardItem | null }

// An item as the band names it: `#123` for an issue, `PR #124` for a pull request. A key written by
// a session still on an older board says `Issue #123`, and reads the same.
function labelOf(item: BoardItem): string {
  return item.item.replace(/^Issue #/, '#')
}

// A part's text as the band draws it: the mark, the signature and the role, the context, then a
// colon and the item when there is one.
function textOf(part: Part): string {
  const head = `${part.mark} ${SIGNATURE[part.key]}${part.key}${part.context}`
  return part.item ? `${head}: ${labelOf(part.item)}` : head
}

// An agent's mark: working (eyes for QA, who reviews), paused while it is idle and the CEO has
// paused it, waiting for the CEO, idle.
function markOf(role: BoardRole, agent: BoardAgent): string {
  if (agent.state === 'working') return role === 'QA' ? MARK.reviewing : MARK.working
  if (isWaiting(agent.state)) return MARK.waits
  return agent.paused === true ? MARK.paused : MARK.idle
}

// An agent's part: its mark, the CTO's context once it reaches CONTEXT_FROM, and the item its
// session last acted on; with no key, or one gone stale, the unknown mark.
function partOf(role: BoardRole, agent: BoardAgent | undefined, now: number): Part {
  if (!agent || now - agent.at > STALE_MS) return { key: role, mark: MARK.unknown, context: '', item: agent?.item ?? null }
  const isFull = role === 'CTO' && agent.context !== null && agent.context >= CONTEXT_FROM
  return { key: role, mark: markOf(role, agent), context: isFull ? ` (ctx: ${agent.context}%)` : '', item: agent.item ?? null }
}

// How many cells a text takes on a terminal.
function widthOf(text: string): number {
  let width = 0
  let rest = text
  for (const emoji of WIDE) {
    const pieces = rest.split(emoji)
    width += 2 * (pieces.length - 1)
    rest = pieces.join('')
  }
  return width + [...rest].length
}

// The line's first part (agent-squad #240): the wordmark, then the board's release when it is known.
function prefixOf(known: string | null): string {
  return known ? `agent-squad (${known})` : 'agent-squad'
}

// How many of the line's parts, given their widths, fit in `columns`, a bar between each two, and
// whether the ellipsis that marks a cut is drawn. The first part always shows, and the surface cuts
// it at the edge if even it is too wide. Each later one shows only whole, and only if it leaves room
// for the ellipsis, unless it is the last, after which nothing can be cut. The ellipsis is drawn
// where it fits.
function fit(widths: number[], columns: number): { count: number; hasEllipsis: boolean } {
  let used = 0
  for (const [index, width] of widths.entries()) {
    const step = (index === 0 ? 0 : widthOf(SEPARATOR)) + width
    const room = index === widths.length - 1 ? 0 : widthOf(ELLIPSIS)
    if (index > 0 && used + step + room > columns) return { count: index, hasEllipsis: used + widthOf(ELLIPSIS) <= columns }
    used += step
  }
  return { count: widths.length, hasEllipsis: false }
}

// The release this session's board belongs to, as `v42`: the major version of the plugin.json the
// mod ships, which check-version.sh keeps equal to the release. It is read with no host command,
// once, when the board starts, so a session not restarted since an upgrade shows the release of
// the code it loaded. Null when it cannot be read.
async function releaseOf($: any): Promise<string | null> {
  try {
    const manifest = JSON.parse(await $.fs.read(`${$.plugin.root}/.claude-plugin/plugin.json`))
    const major = /^(\d+)\./.exec(String(manifest?.version ?? ''))
    return major ? `v${major[1]}` : null
  } catch {
    return null
  }
}

// Writes this session's key: its state, its pause, its item, its context use, and the time.
async function publish($: any) {
  if (!me) return
  const usage = await $.session.usage()
  const agent: BoardAgent = {
    project: me.project,
    role: me.role,
    name: me.name,
    sessionId: await $.session.id(),
    state,
    tool,
    since,
    at: await $.clock.now(),
    context: usage.context?.percent ?? null,
    paused: isPaused,
    item,
  }
  if (me.role === 'CTO') agent.toasted = toasted
  await $.store.set(keyOf(me.project, me.role), agent)
}

// Moves this session to another state, and publishes it.
async function become($: any, next: BoardState, nextTool: string | null = null) {
  if (!me || (next === state && nextTool === tool)) return
  state = next
  tool = nextTool
  since = await $.clock.now()
  await publish($)
}

// A wait ends when the call it held goes on: the tool shows progress, ends, or reports its use.
async function resume($: any) {
  if (isWaiting(state)) await become($, 'working')
}

// After a reload the module has lost the session's title: its own key, found by the session's
// id, gives back its name, its state, its pause, its item and its toasts.
async function recover($: any) {
  const sessionId = await $.session.id()
  for (const key of await $.store.keys()) {
    const value = await $.store.get(key)
    if (isAgent(value) && value.sessionId === sessionId && key === keyOf(value.project, value.role)) {
      identify(value.name)
      state = value.state
      tool = value.tool
      since = value.since
      isPaused = value.paused === true
      item = value.item ?? null
      toasted = value.toasted ?? []
      return
    }
  }
}

// At the session's end its key goes, unless another session of its role has written it since;
// after a /clear the session goes on under a new id, idle, with no item.
async function leave($: any, sessionId: string) {
  if (!me) return
  const key = keyOf(me.project, me.role)
  const value = await $.store.get(key)
  if (isAgent(value) && value.sessionId === sessionId) await $.store.delete(key)
  state = 'idle'
  tool = null
  item = null
}

// The CTO's session: reads its project's keys for the board, and shows a toast for each wait of
// DEV or QA it has not shown yet (the CTO's own wait is on the CEO's screen already).
async function readAgents($: any) {
  if (!me) return
  const now = await $.clock.now()
  const byRole: Partial<Record<BoardRole, BoardAgent>> = {}
  for (const role of ROLES) {
    const value = await $.store.get(keyOf(me.project, role))
    if (isAgent(value) && value.project === me.project && value.role === role) byRole[role] = value
  }
  await update($, agents, () => ({ byRole, now }))
  const waits = ROLES.filter(role => role !== 'CTO')
    .map(role => byRole[role])
    .filter((agent): agent is BoardAgent => agent !== undefined && isWaiting(agent.state) && now - agent.at <= STALE_MS)
  const ids = waits.map(agent => `${agent.role}:${agent.sessionId}:${agent.since}`)
  for (const agent of waits) {
    if (!toasted.includes(`${agent.role}:${agent.sessionId}:${agent.since}`)) {
      $.ui.toast(`${agent.role} waits for you: ${waitText(agent)}`, { timeoutMs: 10_000 })
    }
  }
  const isSame = ids.length === toasted.length && ids.every(id => toasted.includes(id))
  if (!isSame) {
    toasted = ids
    await publish($)
  }
}

// Starts the session's work once it is known to be a squad's: its repository's address (none
// outside a git checkout), its heartbeat and, in the CTO's session, the board's release and what
// the band shows.
async function activate($: any) {
  if (!me || !isStarted || isActive) return
  isActive = true
  repository = webOf((await $.session.repo().catch(() => null))?.remote ?? null)
  if (since === 0) since = await $.clock.now()
  await publish($)
  $.clock.every(HEARTBEAT_MS, () => void publish($))
  if (me.role !== 'CTO') return
  release = await releaseOf($)
  await readAgents($)
  $.clock.every(TICK_MS, () => void readAgents($))
}

export const register: Register = on => {
  // The session's name: given at its start, or later with its first prompt.
  on('classic.SessionStart', async ($, e, next) => {
    identify(e.session_title)
    return next(e)
  })
  on('session.start', async ($, e, next) => {
    isStarted = true
    if (title === null) await recover($)
    await activate($)
    return next(e)
  })
  on('classic.UserPromptSubmit', async ($, e, next) => {
    identify(e.session_title)
    await activate($)
    return next(e)
  })
  // A prompt, typed or delivered by another session: a pause set or cleared by the CEO.
  on('prompt.submit', async ($, e, next) => {
    const step = stepAwayOf(e.text)
    if (me && step !== null && isPaused !== (step === 'pause')) {
      isPaused = step === 'pause'
      await publish($)
    }
    return next(e)
  })

  // The states (agent-squad #199): a turn of the main loop runs; a permission or a question waits
  // for the CEO until the call goes on; the turn ends. tool.check is not used: in auto mode it asks
  // with no dialog drawn.
  on('turn.start', async ($, e, next) => {
    await become($, 'working')
    return next(e)
  })
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) await become($, 'idle')
    return next(e)
  })
  on('classic.PermissionRequest', async ($, e, next) => {
    const isQuestion = e.tool_name === 'AskUserQuestion'
    await become($, isQuestion ? 'question' : 'permission', isQuestion ? null : e.tool_name)
    return next(e)
  })
  // A tool call ends a wait; a gh call that worked names the item the session acts on.
  on('tool.call', async ($, e, next) => {
    const ran: any = await next(e)
    await resume($)
    if (me && e.tool === 'Bash' && !ran?.isError && !ran?.deny) {
      const input = e as any
      const found = itemOf(String(input.command ?? ''), String(ran?.result?.stdout ?? ''), repository)
      if (found && (found.item !== item?.item || found.url !== item?.url)) {
        item = found
        await publish($)
      }
    }
    return ran
  })
  on('classic.PostToolUse', async ($, e, next) => {
    await resume($)
    return next(e)
  })
  on('ui.render', { component: 'ToolProgress' }, async ($, e, next) => {
    await resume($)
    return next(e)
  })
  on('session.end', async ($, e, next) => {
    await leave($, e.sessionId)
    return next(e)
  })

  // The board, in the CTO's session: one line above the prompt between two blue rules. It opens
  // with the wordmark and the board's release, `-squad` and the release in blue; then the agents,
  // each after a blue bar, its state first, as the CTO's reports on the agents read, then the role's
  // name in its colour. A narrow terminal cuts it at its end, the prefix first and the CTO's part
  // whole next. A survey that holds the band goes first.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (me?.role !== 'CTO' || e.props.hasSurvey) return next(e)
    const { Box, Text, Link } = $.ui.resolve(e)
    const seen = await read($, agents)
    const parts = ROLES.map(role => partOf(role, seen.byRole[role], seen.now))
    const widths = [widthOf(prefixOf(release)), ...parts.map(part => widthOf(textOf(part)))]
    const { count, hasEllipsis } = fit(widths, e.props.bodyColumns)
    const shown = parts.slice(0, count - 1)
    const rule = RULE.repeat(Math.max(1, e.props.bodyColumns))
    return (
      <Box flexDirection="column">
        <Box key="rule">
          <Text color={RULE_COLOR} wrap="truncate-end">{rule}</Text>
        </Box>
        <Box key="line" flexDirection="row" overflow="hidden">
          <Box key="prefix">
            <Text wrap="truncate-end">agent</Text>
            <Text color={RULE_COLOR} wrap="truncate-end">-squad</Text>
            {release !== null && <Text color={RULE_COLOR} wrap="truncate-end">{` (${release})`}</Text>}
          </Box>
          {shown.map(part => (
            <Box key={part.key}>
              <Text color={RULE_COLOR} wrap="truncate-end">{SEPARATOR}</Text>
              <Text wrap="truncate-end">{`${part.mark} ${SIGNATURE[part.key]}`}</Text>
              <Text color={ROLE_COLOR[part.key].plain} wrap="truncate-end">
                <Text color={ROLE_COLOR[part.key].key}>{part.key}</Text>
              </Text>
              {part.context !== '' && <Text wrap="truncate-end">{part.context}</Text>}
              {part.item && <Text>: </Text>}
              {part.item && (part.item.url?.startsWith('https://')
                ? <Link href={part.item.url}>{labelOf(part.item)}</Link>
                : <Text>{labelOf(part.item)}</Text>)}
            </Box>
          ))}
          {hasEllipsis && <Text dimColor>{ELLIPSIS}</Text>}
        </Box>
        <Box key="rule-below">
          <Text color={RULE_COLOR} wrap="truncate-end">{rule}</Text>
        </Box>
      </Box>
    )
  })
}
