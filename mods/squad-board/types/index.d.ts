// The squad board's contract (agent-squad #205, #222): what each squad session publishes in the
// store, and what the CTO's session keeps to draw the board.

// A role of the squad, as its session's name says it (SQUAD.md §1).
export type BoardRole = 'CTO' | 'DEV' | 'QA'

// What a session is doing: a turn running, waiting on the CEO for a permission or a question, or
// at its prompt.
export type BoardState = 'working' | 'permission' | 'question' | 'idle'

// The issue or PR a session last acted on with gh: its label (`Issue #12`, `PR #34`) and its web
// address, null when the session's repository is not on GitHub.
export type BoardItem = { item: string; url: string | null }

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
  // Whether the CEO paused the session (/squad-pause), until a resume or autopilot.
  paused?: boolean
  // The issue or PR the session last acted on with gh; null before its first.
  item?: BoardItem | null
  // The CTO's session only: the waits it has already shown a toast for.
  toasted?: string[]
}

// The agents' keys as the CTO's session last read them, and the time it read them.
export type BoardAgents = { byRole: Partial<Record<BoardRole, BoardAgent>>; now: number }

declare module 'claude-code' {
  interface PluginState {
    'squad-board': { agents: BoardAgents }
  }
}
