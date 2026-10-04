import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { BoardAgent, BoardAgents, BoardItem, BoardItems, BoardRole, BoardState } from '../types'

// The squad board (agent-squad #205). Every session of a squad publishes its own state in this
// mod's store, under `<project>/<role>`, and only that key; the CTO's session reads its project's
// keys and draws one line per agent, with a link to the item GitHub says it works on, and shows a
// toast when an agent waits for the CEO. A session whose name is not a squad role's does nothing.
// The signals are the ones agent-squad #199 measured.

const ROLES: readonly BoardRole[] = ['CTO', 'DEV', 'QA']
const BOARD = 'squad-board'
// How often a session rewrites its key, and how old a key may grow before its line reads unknown.
const HEARTBEAT_MS = 60_000
const STALE_MS = 180_000
// How often the CTO's session reads the keys, and GitHub.
const TICK_MS = 3_000
const GITHUB_MS = 180_000
// The state marks of SQUAD.md §6, written as escapes since emojis stay out of code: hourglass
// (working), raised hand (waits for the CEO), zzz (idle), question mark (no sign of life).
const MARK: Record<BoardState | 'unknown', string> = {
  working: '\u23F3', permission: '\u270B', question: '\u270B', idle: '\u{1F4A4}', unknown: '\u2753',
}

const agents = atom({ plugin: 'squad-board', key: 'agents' } as const, { byRole: {}, now: 0 } as BoardAgents)
const items = atom({ plugin: 'squad-board', key: 'items' } as const, { byRole: {}, readAt: null, error: null } as BoardItems)

// This session: the title it started with, who it is once that title names a squad role, whether
// its work has started, and what it is doing. A reload starts all of it over (recover, below).
let title: string | null = null
let me: { project: string; role: BoardRole; name: string } | null = null
let isStarted = false
let isActive = false
let state: BoardState = 'idle'
let tool: string | null = null
let since = 0
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

// What a wait is, in the words the board and the toast use.
function waitText(agent: BoardAgent): string {
  return agent.state === 'question' ? 'a question' : `a permission for ${agent.tool ?? 'a tool'}`
}

// One agent's line on the board: its mark, what it does, and its context use.
function lineOf(agent: BoardAgent | undefined, now: number): { mark: string; text: string; context: string } {
  if (!agent) return { mark: MARK.unknown, text: 'no session seen', context: '' }
  const context = agent.context === null ? '  ctx -' : `  ctx ${agent.context}%`
  if (now - agent.at > STALE_MS) {
    return { mark: MARK.unknown, text: `no sign for ${Math.floor((now - agent.at) / 60_000)} min`, context }
  }
  const text = { working: 'working', permission: '', question: '', idle: 'idle' }[agent.state]
  return { mark: MARK[agent.state], text: isWaiting(agent.state) ? `waits for you: ${waitText(agent)}` : text, context }
}

// Writes this session's key: its state, its context use, and the time.
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
// id, gives back its name, its state and its toasts.
async function recover($: any) {
  const sessionId = await $.session.id()
  for (const key of await $.store.keys()) {
    const value = await $.store.get(key)
    if (isAgent(value) && value.sessionId === sessionId && key === keyOf(value.project, value.role)) {
      identify(value.name)
      state = value.state
      tool = value.tool
      since = value.since
      toasted = value.toasted ?? []
      return
    }
  }
}

// At the session's end its key goes, unless another session of its role has written it since;
// after a /clear the session goes on under a new id, idle.
async function leave($: any, sessionId: string) {
  if (!me) return
  const key = keyOf(me.project, me.role)
  const value = await $.store.get(key)
  if (isAgent(value) && value.sessionId === sessionId) await $.store.delete(key)
  state = 'idle'
  tool = null
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

// The CTO's session: reads from GitHub the item each role works on, through the playbook's
// `squad-stalls.sh --current`, which makes read-only gh calls. A failed read clears the items,
// which may no longer hold, and says why.
async function readGitHub($: any) {
  const now = await $.clock.now()
  try {
    const root = await $.session.root()
    const git = await $.process.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd: root })
    if (git.exitCode !== 0) throw new Error('the session is not in a git checkout')
    const main = git.stdout.trim().replace(/\/[^/]+\/?$/, '')
    const ran = await $.process.run([`${main}/.agent-squad/playbook/scripts/squad-stalls.sh`, '--current'], { cwd: root, timeoutMs: 120_000 })
    if (ran.exitCode !== 0) throw new Error(ran.stderr.trim().split('\n').pop() || `squad-stalls.sh exited ${ran.exitCode}`)
    const byRole: Partial<Record<BoardRole, BoardItem>> = {}
    for (const line of ran.stdout.split('\n')) {
      const [role, item, url, step] = line.split('\t')
      if (ROLES.includes(role as BoardRole) && item && /^https:\/\//.test(url ?? '')) byRole[role as BoardRole] = { item, url, step: step ?? '' }
    }
    await update($, items, () => ({ byRole, readAt: now, error: null }))
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error)
    await update($, items, old => ({ byRole: {}, readAt: old.readAt, error: reason }))
  }
}

// Starts the session's work once it is known to be a squad's: its heartbeat and, in the CTO's
// session, the board.
async function activate($: any) {
  if (!me || !isStarted || isActive) return
  isActive = true
  if (since === 0) since = await $.clock.now()
  await publish($)
  $.clock.every(HEARTBEAT_MS, () => void publish($))
  if (me.role !== 'CTO') return
  await $.command.register({ name: BOARD, description: "Open the squad board: each agent's state, context and current issue or PR" })
  void $.ui.open({ id: BOARD, title: 'Squad board' })
  await readAgents($)
  $.clock.every(TICK_MS, () => void readAgents($))
  $.clock.after(0, () => void readGitHub($))
  $.clock.every(GITHUB_MS, () => void readGitHub($))
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
  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    await resume($)
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

  // The board, in the CTO's session: its command, and its pane.
  on('command.run', { command: BOARD }, async $ => {
    await $.ui.open({ id: BOARD, title: 'Squad board' })
    return { text: 'The squad board is open.' }
  })
  on('ui.render', { component: 'Pane', requestId: BOARD }, async ($, e, next) => {
    if (me?.role !== 'CTO') return next(e)
    const { Box, Text, Link } = $.ui.resolve(e)
    const seen = await read($, agents)
    const github = await read($, items)
    return (
      <Box flexDirection="column">
        {ROLES.map(role => {
          const line = lineOf(seen.byRole[role], seen.now)
          const found = github.byRole[role]
          return (
            <Box key={role}>
              <Text>{line.mark} </Text>
              <Text bold>{role.padEnd(4)}</Text>
              <Text>{line.text}</Text>
              <Text dimColor>{line.context}  </Text>
              {found && <Link href={found.url}>{found.item}</Link>}
              {found && <Text dimColor> {found.step}</Text>}
            </Box>
          )
        })}
        {github.error !== null && <Text dimColor>GitHub not read: {github.error}</Text>}
      </Box>
    )
  })
}
