// The squad board's contract (agent-squad #205): what each squad session publishes in the store,
// and what the CTO's session keeps to draw the board.

// A role of the squad, as its session's name says it (SQUAD.md §1).
export type BoardRole = 'CTO' | 'DEV' | 'QA'

// What a session is doing: a turn running, waiting on the CEO for a permission or a question, or
// at its prompt.
export type BoardState = 'working' | 'permission' | 'question' | 'idle'

// One session's key in the store, `<project>/<role>`, written by that session alone.
export type BoardAgent = {
  project: string
  role: BoardRole
  name: string
  sessionId: string
  state: BoardState
  // The tool a permission is asked for; null otherwise.
  tool: string | null
  // When the state began, and when the key was last written, in milliseconds.
  since: number
  at: number
  // The context in use, in percent, as `$.session.usage()` gives it; null before the first turn.
  context: number | null
  // The CTO's session only: the waits it has already shown a toast for.
  toasted?: string[]
}

// A role's current item on GitHub, from `squad-stalls.sh --current`.
export type BoardItem = { item: string; url: string; step: string }

// The items, and when GitHub was last read; `error` says why the last read failed.
export type BoardItems = { byRole: Partial<Record<BoardRole, BoardItem>>; readAt: number | null; error: string | null }

// The agents' keys as the CTO's session last read them, and the time it read them.
export type BoardAgents = { byRole: Partial<Record<BoardRole, BoardAgent>>; now: number }

declare module 'claude-code' {
  interface PluginState {
    'squad-board': { agents: BoardAgents; items: BoardItems }
  }
}
