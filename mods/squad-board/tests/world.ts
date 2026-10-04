import type { On } from 'claude-code'
import { mock } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'

// The engine beneath the squad board in a test: it answers every call the board makes and every
// event a test raises, and it records what the board asked of it.

// The time a test starts at, in milliseconds.
export const START = 1_000_000

export type World = {
  clock: MockClock
  // The mod's store: what a test reads, and what it may change between steps.
  store: Map<string, unknown>
  // What the board asked: toasts shown, panes opened, commands registered, host commands run.
  toasts: string[]
  opened: string[]
  commands: string[]
  runs: (readonly string[])[]
  // What the engine answers: the session's id, its context use, and squad-stalls.sh --current.
  sessionId: string
  percent: number | null
  current: string
  currentExit: number
}

// Sets the world up on the test's `on`, with the store holding `store` at the start.
export function world(on: On, store: Record<string, unknown> = {}): World {
  const w: World = {
    clock: mock.clock(on, { now: START }),
    store: new Map(Object.entries(store)),
    toasts: [],
    opened: [],
    commands: [],
    runs: [],
    sessionId: 'sid-1',
    percent: 42,
    current: '',
    currentExit: 0,
  }
  on('store.get', ($, e) => ({ value: w.store.get(e.key) }))
  on('store.set', ($, e) => {
    w.store.set(e.key, e.value)
    return { value: undefined }
  })
  on('store.delete', ($, e) => {
    w.store.delete(e.key)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...w.store.keys()] }))
  on('session.id', () => ({ value: w.sessionId }))
  on('session.root', () => ({ value: '/work/proj' }))
  on('session.usage', () => ({
    value: { startedAt: 0, context: { tokens: 42_000, window: 100_000, percent: w.percent }, rateLimits: [] },
  }))
  on('command.register', ($, e) => {
    w.commands.push(e.name)
    return { value: { command: e.name } }
  })
  on('ui.open', ($, e) => {
    w.opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.toast', ($, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('process.run', ($, e) => {
    w.runs.push(e.argv)
    const isGit = e.argv[0] === 'git'
    const exitCode = isGit ? 0 : w.currentExit
    const stdout = isGit ? '/work/proj/.git\n' : exitCode === 0 ? w.current : ''
    const stderr = exitCode === 0 ? '' : 'squad-stalls: cannot read the open pull requests; nothing was checked\n'
    return { value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  // The engine's own answers to the events a test raises.
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', ($, e) => ({ text: e.answer }))
  on('tool.check', () => ({ decision: 'ask' as const }))
  on('tool.call', () => ({ result: { stdout: 'ran', stderr: '', interrupted: false } } as any))
  on('classic.SessionStart', () => ({}))
  on('classic.UserPromptSubmit', () => ({}))
  on('classic.PermissionRequest', () => ({}))
  on('classic.PostToolUse', () => ({}))
  // What the engine draws beneath the plugins: a line of its own.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return h(Text, {}, 'drawn by the engine')
  })
  return w
}

// A session starts under a name, as Claude Code starts one: its SessionStart hook, then the
// session.
export async function start($: Engine, name: string) {
  await $.classic.SessionStart({ source: 'startup', session_title: name } as any)
  await $.session.start({ cwd: '/work/proj', surface: 'terminal', isInteractive: true })
}

// A turn of the main loop starts, or ends; `agentId` makes it a subagent's.
export async function turnStart($: Engine) {
  await $.turn.start({ text: 'go', turnId: 't1' })
}
export async function turnEnd($: Engine, agentId?: string) {
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer', agentId } as any)
}

// Claude Code asks the person for a permission, or AskUserQuestion asks a question.
export async function asks($: Engine, tool: string) {
  await $.classic.PermissionRequest({ tool_name: tool, tool_input: {} } as any)
}

