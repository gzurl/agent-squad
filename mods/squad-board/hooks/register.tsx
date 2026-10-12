import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { BoardAgent, BoardAgents, BoardItem, BoardRole, BoardState } from '../types'

// The squad board (agent-squad #205, #212, #217, #222, #235, #240, #244, #289). Every session of a
// squad publishes its own state in this mod's store, under `<project>/<role>`, and only that key:
// what it is doing, whether the CEO paused it or has it on autopilot, and the issue or PR its agent
// is focused on, which its own gh calls declare (focusAfter, below). The CTO's session reads its
// project's keys and draws them on one line above its prompt, with the wordmark and the board's
// release on the right, and shows a toast when an agent waits for the CEO. The band shows each
// session's own state, not GitHub's: nothing is read from GitHub, and no command is run; a newer
// release is known from a file another script writes. A session whose name is not a squad role's
// does nothing. Every key records the release its session's board loaded, and the band marks a
// session older than the installed release, which still needs a /restart (agent-squad #362). The
// signals are the ones agent-squad #199 measured.

const ROLES: readonly BoardRole[] = ['CTO', 'DEV', 'QA']
// How often a session rewrites its key, and how old a key may grow before its part reads unknown.
const HEARTBEAT_MS = 60_000
const STALE_MS = 180_000
// How often the CTO's session reads the keys.
const TICK_MS = 3_000
// The state marks of SQUAD.md §6, written as escapes since emojis stay out of code: hourglass
// (working), eyes (QA working, since it reviews), gear (its turn ended with a background shell still
// running, agent-squad #264), pause (paused by the CEO), raised hand (waits for the CEO), zzz
// (idle), question mark (no recent state). The gear and the pause are text characters made emojis
// by their selector.
const MARK = {
  working: '\u23F3', reviewing: '\u{1F440}', background: '\u2699\uFE0F', paused: '\u23F8\uFE0F',
  waits: '\u270B', idle: '\u{1F4A4}', unknown: '\u2753',
}
// The members' signatures of SQUAD.md §6, as escapes: each a person, a skin tone, a joiner and what
// they do (and for the CTO a presentation selector), which a terminal draws as one emoji.
const SIGNATURE: Record<BoardRole, string> = {
  CTO: '\u{1F477}\u{1F3FC}\u200D\u2642\uFE0F',
  DEV: '\u{1F468}\u{1F3FC}\u200D\u{1F4BB}',
  QA: '\u{1F469}\u{1F3FC}\u200D\u{1F52C}',
}
// The squad's part, on the right of the band (agent-squad #244): fast-forward first while the CEO
// has the squad on autopilot, then the wordmark, then the notice of a newer release; at least GAP
// cells between it and the agents, and no separator.
const AUTOPILOT = '\u23E9'
const GAP = 3
// The mark of a session whose board is older than the installed release, before the two releases
// (agent-squad #362): a clockwise arrow, a text character of one cell.
const RESTART = '\u27F3'
// Every emoji the band draws takes two cells of a terminal, however many code points it has, as
// Claude Code measures it; every other character one. The longest are matched first. A terminal
// that draws the pause in one cell leaves the line one cell shorter, which the cut allows for, and
// the squad's part one cell short of the edge.
const WIDE = [...new Set([...Object.values(SIGNATURE), ...Object.values(MARK), AUTOPILOT])].sort((a, b) => b.length - a.length)
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
// its work has started, what it is doing, whether the CEO paused it, and its repository's web
// address; its focus is kept below, with the rules that move it. A reload starts all of it over
// (recover, below).
let title: string | null = null
let me: { project: string; role: BoardRole; name: string } | null = null
let isStarted = false
let isActive = false
let state: BoardState = 'idle'
let tool: string | null = null
let since = 0
let isPaused = false
// Whether the session's last turn ended with a background shell still running, as its Stop said.
let hasShell = false
// Whether the CEO has the squad on autopilot, from /squad-autopilot until /squad-resume or
// /squad-pause; the CTO's session shows it on the band (agent-squad #244).
let isAutopilot = false
let repository: string | null = null
// The session's repository on this machine, its main checkout for a squad's session; null outside
// a git checkout.
let checkout: string | null = null
// The release this session's board belongs to, as `v42`, read once when the board starts: the
// CTO's wordmark shows it, and every session's key records it (agent-squad #362).
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

// A command as the shell splits it (agent-squad #225, #289): its simple commands, in order, each a
// list of words. A quoted string is part of a word, its quotes gone, so that a label keeps its text
// and a body is one word that is never read as a command; each heredoc's body is left out, from the
// line after its `<<WORD` or `<<-WORD`, the word quoted or not, up to the line that holds the word
// alone. A `<<` inside quotes opens no heredoc, nor does a here-string (`<<<`). A single quote ends
// at the next one; a double quote ends at the next one that no backslash escapes, and may span
// lines. A `#` that starts a word outside quotes, or follows a `<` or `>`, starts a comment, which
// runs to the end of its line and opens nothing (#227). A newline, `;`, `&`, `|`, `(` and `)` end a
// command, outside quotes, where a backslash at the end of a line joins the next one to it.
function commandsOf(command: string): string[][] {
  const commands: string[][] = []
  let words: string[] = []
  let word: string | null = null
  let quote: string | null = null
  let continued = false
  const ends: string[] = []
  const endWord = () => {
    if (word !== null) words.push(word)
    word = null
  }
  const endCommand = () => {
    endWord()
    if (words.length > 0) commands.push(words)
    words = []
  }
  for (const line of command.split('\n')) {
    // A heredoc's body: skipped whole, up to the line that ends it.
    if (quote === null && !continued && ends.length > 0) {
      if (line.trim() === ends[0]) ends.shift()
      continue
    }
    continued = false
    let i = 0
    while (i < line.length) {
      const c = line[i]
      if (quote !== null) {
        if (quote === '"' && c === '\\') {
          if (i + 1 < line.length) word += line[i + 1]
          i += 2
        } else {
          if (c === quote) quote = null
          else word += c
          i += 1
        }
        continue
      }
      if (c === '#' && (word === null || /[<>]$/.test(word))) break
      const heredoc = line[i - 1] === '<' ? null : /^<<-?\s*(['"]?)([A-Za-z_]\w*)\1/.exec(line.slice(i))
      if (heredoc) {
        ends.push(heredoc[2])
        endWord()
        i += heredoc[0].length
      } else if (c === '\\') {
        if (i + 1 < line.length) word = (word ?? '') + line[i + 1]
        else continued = true
        i += 2
      } else if (c === '"' || c === "'") {
        quote = c
        word = word ?? ''
        i += 1
      } else if (/[;&|()]/.test(c)) {
        endCommand()
        i += 1
      } else if (/\s/.test(c)) {
        endWord()
        i += 1
      } else {
        word = (word ?? '') + c
        i += 1
      }
    }
    if (continued) continue
    if (quote === null) endCommand()
    else word += '\n'
  }
  endCommand()
  return commands
}

// The session's focus (agent-squad #289): the issues and PRs its agent works on, the latest last,
// up to FOCUS_LIMIT. The band shows the latest. A PR the session created is tied to the issue in
// focus when it was created, so that ending the PR ends its issue too.
type Focus = BoardItem & { tied?: BoardItem | null }
const FOCUS_LIMIT = 5
let focus: Focus[] = []
// The item the band shows: the latest focus, without its tie; null with none.
function itemNow(): BoardItem | null {
  const latest = focus.at(-1)
  return latest ? { item: latest.item, url: latest.url } : null
}

// The issue or PR a gh call names: its first number or GitHub address, flags before it or not;
// `--repo owner/name` names another repository than the session's. Null when it names none.
function targetOf(noun: string, args: string[], home: string | null): BoardItem | null {
  const target = args.find(arg => /^(\d+|https:\/\/\S+)$/.test(arg))
  if (!target) return null
  if (target.startsWith('https://')) return itemAt(target)
  const repo = args.findIndex(arg => arg === '-R' || arg === '--repo')
  const other = repo >= 0 ? args[repo + 1] : args.find(arg => arg.startsWith('--repo='))?.slice('--repo='.length)
  const base = other && /^[^\s/]+\/[^\s/]+$/.test(other) ? `https://github.com/${other}` : home
  return { item: `${noun === 'pr' ? 'PR ' : ''}#${target}`, url: base ? `${base}/${noun === 'pr' ? 'pull' : 'issues'}/${target}` : null }
}

// The labels a gh call names with one of the flags: `<flag> <labels>`, or `--<flag>=<labels>`, the
// labels separated by commas.
function labelsOf(args: string[], flags: string[]): string[] {
  return args
    .flatMap((arg, i) => {
      if (flags.includes(arg)) return [args[i + 1] ?? '']
      const long = flags.find(flag => flag.startsWith('--') && arg.startsWith(flag + '='))
      return long ? [arg.slice(long.length + 1)] : []
    })
    .flatMap(value => value.split(',').map(label => label.trim()))
}

// Whether a gh call adds the in-progress label: gh issue edit with --add-label, and gh issue create
// with --label or -l (agent-squad #354).
function addsInProgress(args: string[], flags = ['--add-label']): boolean {
  return labelsOf(args, flags).some(label => label.endsWith('status:in-progress'))
}

// Whether a gh issue edit ends the work on its issue (agent-squad #354): it removes the in-progress
// or the in-review label, and adds no status label, as the author does once the issue's PR is
// merged (SQUAD.md §4.9).
function endsWork(args: string[]): boolean {
  return labelsOf(args, ['--remove-label']).some(label => /status:in-(progress|review)$/.test(label))
    && !labelsOf(args, ['--add-label']).some(label => label.includes('status:'))
}

// The issues a PR's body closes, by GitHub's keywords: "Closes #12", "fixes #12", "Resolves: #12".
function closedBy(body: string): number[] {
  return [...body.matchAll(/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+#(\d+)\b/gi)].map(found => Number(found[1]))
}

// The body a gh pr create gives its PR, as far as the board can tell: the text of --body or -b, or
// the file that --body-file or -F names, as `bodies` holds it, read once the call has ended. Null
// otherwise, as for --fill or a body from stdin.
function bodyOf(args: string[], bodies: Record<string, string>): string | null {
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--body' || arg === '-b') return args[i + 1] ?? null
    if (arg.startsWith('--body=')) return arg.slice('--body='.length)
    if (arg === '--body-file' || arg === '-F') return bodies[args[i + 1] ?? ''] ?? null
    if (arg.startsWith('--body-file=')) return bodies[arg.slice('--body-file='.length)] ?? null
  }
  return null
}

// The files a command's gh pr create calls take their body from, that the board can read: an
// absolute path, written out, with no variable or command in it (agent-squad #354).
function bodyFiles(command: string): string[] {
  return commandsOf(command).map(unwrapped)
    .filter(call => call[0] === 'gh' && call[1] === 'pr' && call[2] === 'create')
    .flatMap(call => call.flatMap((arg, i) =>
      arg === '--body-file' || arg === '-F' ? [call[i + 1] ?? ''] : arg.startsWith('--body-file=') ? [arg.slice('--body-file='.length)] : []))
    .filter(path => path.startsWith('/') && !/[$`]/.test(path))
}

function sameItem(a: BoardItem, b: BoardItem): boolean {
  return a.item === b.item && a.url === b.url
}

// The PR gh pr create made, or the issue gh issue create made (`kind` issues), from the command
// line's output: the first line that is such an address alone, as both print it, and not one
// another call of the line names. Other calls print addresses too: gh issue edit the issue's, gh pr
// comment or gh issue comment the comment's, which goes on past the number (QA's finding on PR
// #294), and gh pr edit its PR's, alone (agent-squad #299). An item the line names by number is
// never the one it creates, whose number nobody knew when the line was written.
function createdIn(output: string, named: BoardItem[], kind: 'pull' | 'issues' = 'pull'): BoardItem | null {
  for (const line of output.split('\n')) {
    if (!new RegExp(`^https://github\\.com/[^/\\s]+/[^/\\s]+/${kind}/\\d+$`).test(line.trim())) continue
    const found = itemAt(line)
    if (found && !named.some(other => other.item === found.item && (other.url === null || other.url === found.url))) return found
  }
  return null
}

// The words of a call without the rtk prefix that rewrites it: `rtk <command>` or
// `rtk proxy <command>`.
function unwrapped(words: string[]): string[] {
  if (words[0] !== 'rtk') return words
  return words[1] === 'proxy' ? words.slice(2) : words.slice(1)
}

// The PR a git fetch brings in by its pull request ref, as QA checks a PR out (agent-squad #334):
// `git [-C <dir>] fetch [<options>] <remote> pull/<n>/head[:<ref>]`, with `refs/` or `+` before it
// or not. It is the remote's PR when the remote is a GitHub address, and the session's repository's
// otherwise. Null for any other call.
function fetchedPR(call: string[], home: string | null): BoardItem | null {
  let at = 1
  while (at < call.length && call[at].startsWith('-')) at += ['-C', '-c', '--git-dir', '--work-tree'].includes(call[at]) ? 2 : 1
  if (call[0] !== 'git' || call[at] !== 'fetch') return null
  const args = call.slice(at + 1).filter(arg => !arg.startsWith('-'))
  const n = args.map(arg => /^\+?(?:refs\/)?pull\/(\d+)\/head(?::\S*)?$/.exec(arg)?.[1]).find(Boolean)
  if (!n) return null
  const repo = /github\.com[:/]([^/\s]+\/[^/\s]+?)(?:\.git)?\/?$/.exec(args[0] ?? '')
  const base = repo ? `https://github.com/${repo[1]}` : home
  return { item: `PR #${n}`, url: base ? `${base}/pull/${n}` : null }
}

// The PR a gh api call posts a review on, as QA reviews, to bind the review to a commit (agent-squad
// #334): `gh api [<flags>] repos/<owner>/<repo>/pulls/<n>/reviews` with a body, from --input or a
// field, or with -X POST; {owner} and {repo} name the session's repository, as gh fills them in. A
// call with neither, or with -X GET, only reads, and posts nothing. Null for any other call.
function reviewedPR(call: string[], home: string | null): BoardItem | null {
  if (call[0] !== 'gh' || call[1] !== 'api') return null
  let endpoint: string | null = null
  let method: string | null = null
  let body = false
  for (let i = 2; i < call.length; i++) {
    const arg = call[i]
    const eq = arg.startsWith('--') ? arg.indexOf('=') : -1
    const flag = eq > 0 ? arg.slice(0, eq) : arg
    const value = () => (eq > 0 ? arg.slice(eq + 1) : call[++i] ?? '')
    if (flag === '-X' || flag === '--method') {
      method = value().toUpperCase()
    } else if (/^-X\w/.test(arg)) {
      method = arg.slice(2).toUpperCase()
    } else if (['-f', '-F', '--field', '--raw-field', '--input'].includes(flag)) {
      value()
      body = true
    } else if (['-H', '--header', '--hostname', '-q', '--jq', '-t', '--template', '--cache', '-p', '--preview'].includes(flag)) {
      value()
    } else if (!arg.startsWith('-')) {
      endpoint ??= arg
    }
  }
  const found = /^\/?repos\/([^/\s]+)\/([^/\s]+)\/pulls\/(\d+)\/reviews\/?(?:\?\S*)?$/.exec(endpoint ?? '')
  if (!found || !(method === null ? body : method === 'POST')) return null
  const filled = /^(\{owner\}|:owner)$/.test(found[1]) || /^(\{repo\}|:repo)$/.test(found[2])
  const base = filled ? home : `https://github.com/${found[1]}/${found[2]}`
  return { item: `PR #${found[3]}`, url: base ? `${base}/pull/${found[3]}` : null }
}

// What a command that worked does to the focus, each call in order (agent-squad #289), with or
// without rtk before it:
// - gh issue edit <n> adding the in-progress label: the issue becomes the focus;
// - gh issue create adding the in-progress label: the issue it made becomes the focus (#354);
// - gh pr create: the PR it made becomes the focus, tied to the issue its body closes, when the
//   board can read that body, and to none otherwise (#354);
// - gh pr checkout <n> or gh pr review <n>, or QA's way of doing each, a git fetch of the PR's
//   pull/<n>/head and a gh api call that posts a review on it (agent-squad #334): the PR becomes the
//   focus, and a PR already in it keeps its tie;
// - gh pr merge <n>, gh pr close <n> or gh issue close <n>: that item leaves the focus, and with a
//   PR the issue it is tied to;
// - gh issue edit <n> removing the in-progress or in-review label and adding no status label, the
//   author's step once the issue's PR is merged: the issue leaves the focus (#354);
// - any other call, such as view, comment, another label edit or a gh api call that only reads,
//   changes nothing.
// It gives back the new focus.
function focusAfter(before: Focus[], command: string, output: string, home: string | null,
  bodies: Record<string, string> = {}): Focus[] {
  let after = before
  const enter = (next: Focus) => {
    after = [...after.filter(entry => !sameItem(entry, next)), next].slice(-FOCUS_LIMIT)
  }
  const calls = commandsOf(command).map(unwrapped)
  const named = calls.flatMap(call => {
    const ghCall = call[0] === 'gh' && (call[1] === 'pr' || call[1] === 'issue') && call[2] !== 'create'
    const found = ghCall ? targetOf(call[1], call.slice(3), home) : fetchedPR(call, home) ?? reviewedPR(call, home)
    return found ? [found] : []
  })
  for (const call of calls) {
    const opened = fetchedPR(call, home) ?? reviewedPR(call, home)
    if (opened) {
      enter({ ...opened, tied: after.find(entry => sameItem(entry, opened))?.tied ?? null })
      continue
    }
    if (call[0] !== 'gh' || (call[1] !== 'issue' && call[1] !== 'pr')) continue
    const [, noun, verb] = call
    const args = call.slice(3)
    if (noun === 'pr' && verb === 'create') {
      const created = createdIn(output, named)
      const closes = closedBy(bodyOf(args, bodies) ?? '')[0]
      const tied = closes === undefined ? null
        : { item: `#${closes}`, url: created?.url ? created.url.replace(/\/pull\/\d+$/, `/issues/${closes}`) : null }
      if (created) enter({ ...created, tied })
      continue
    }
    if (noun === 'issue' && verb === 'create') {
      const created = addsInProgress(args, ['--label', '-l']) ? createdIn(output, named, 'issues') : null
      if (created) enter({ ...created, tied: null })
      continue
    }
    const target = targetOf(noun, args, home)
    if (!target) continue
    if ((noun === 'issue' && verb === 'edit' && addsInProgress(args)) || (noun === 'pr' && (verb === 'checkout' || verb === 'review'))) {
      enter({ ...target, tied: after.find(entry => sameItem(entry, target))?.tied ?? null })
    } else if ((noun === 'pr' && (verb === 'merge' || verb === 'close')) || (noun === 'issue' && verb === 'close')) {
      const tied = after.find(entry => sameItem(entry, target))?.tied
      after = after.filter(entry => !sameItem(entry, target) && !(tied && sameItem(entry, tied)))
    } else if (noun === 'issue' && verb === 'edit' && endsWork(args)) {
      after = after.filter(entry => !sameItem(entry, target))
    }
  }
  return after
}

// The step-away commands of SQUAD.md §6 a prompt carries, typed (the prompt starts with the
// command) or relayed (the relay names it in parentheses, then a colon and its instruction, as
// `(`/squad-pause`): follow`): a pause sets the session's pause, and autopilot its autopilot, each
// clearing the other; a resume clears both. A message that only quotes the form, with no colon
// after it, is no relay. Each command's own file names only itself that way, so an expanded command
// reads the same. Null for any other prompt.
function stepAwayOf(text: string): 'pause' | 'resume' | 'autopilot' | null {
  const found = /^\s*\/squad-(pause|resume|autopilot)(?:-all)?\b/.exec(text) ?? /\(`\/squad-(pause|resume|autopilot)(?:-all)?`\):/.exec(text)
  return found ? found[1] as 'pause' | 'resume' | 'autopilot' : null
}

// One part of the band (agent-squad #235): an agent's role, its state mark, the CTO's context when
// it shows, the mark of a session to restart when it is older than the installed release
// (agent-squad #362), and its item when it has one.
type Part = { key: BoardRole; mark: string; context: string; restart: string; item: BoardItem | null }

// An item as the band names it: `#123` for an issue, `PR #124` for a pull request. A key written by
// a session still on an older board says `Issue #123`, and reads the same.
function labelOf(item: BoardItem): string {
  return item.item.replace(/^Issue #/, '#')
}

// A part's text as the band draws it: the mark, the signature and the role, the context, the mark of
// a session to restart, then a colon and the item when there is one.
function textOf(part: Part): string {
  const head = `${part.mark} ${SIGNATURE[part.key]}${part.key}${part.context}${part.restart}`
  return part.item ? `${head}: ${labelOf(part.item)}` : head
}

// An agent's mark: working (eyes for QA, who reviews), waiting for the CEO, a background shell still
// running after its turn, paused while it is idle and the CEO has paused it, idle. The shell goes
// before the pause: something of the agent's still runs.
function markOf(role: BoardRole, agent: BoardAgent): string {
  if (agent.state === 'working') return role === 'QA' ? MARK.reviewing : MARK.working
  if (isWaiting(agent.state)) return MARK.waits
  if (agent.background === true) return MARK.background
  return agent.paused === true ? MARK.paused : MARK.idle
}

// The number of a release, `v42` as 42; null for anything else.
function releaseNumber(text: unknown): number | null {
  return typeof text === 'string' && /^v\d+$/.test(text) ? Number(text.slice(1)) : null
}

// The mark of a session whose board is older than the installed release (agent-squad #362), as
// ` ⟳ v50→v53`, compared as numbers; none when it is not, or when the installed release is not
// known. A key with no release was written by a board from before boards recorded it, so older
// than any that does: ` ⟳ →v54`. A key whose release its board could not read gets none.
function restartOf(agent: BoardAgent, installed: string | null): string {
  const target = releaseNumber(installed)
  if (target === null) return ''
  if (agent.release === undefined) return ` ${RESTART} \u2192${installed}`
  const loaded = releaseNumber(agent.release)
  return loaded !== null && loaded < target ? ` ${RESTART} ${agent.release}\u2192${installed}` : ''
}

// An agent's part: its mark, the CTO's context once it reaches CONTEXT_FROM, the mark of a session
// to restart, and the item its session works on while the agent has something in hand (agent-squad
// #247): an idle agent shows its role alone, and its key keeps the item for when it works again.
// With no key, or one gone stale, the unknown mark, with the item of the work whose session went
// silent, and no mark of a restart, since the key may not be a session's any more.
function partOf(role: BoardRole, agent: BoardAgent | undefined, now: number, installed: string | null = null): Part {
  if (!agent || now - agent.at > STALE_MS) {
    return { key: role, mark: MARK.unknown, context: '', restart: '', item: agent?.item ?? null }
  }
  const isFull = role === 'CTO' && agent.context !== null && agent.context >= CONTEXT_FROM
  const mark = markOf(role, agent)
  return {
    key: role, mark, context: isFull ? ` (ctx: ${agent.context}%)` : '', restart: restartOf(agent, installed),
    item: mark === MARK.idle ? null : agent.item ?? null,
  }
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

// The wordmark (agent-squad #240): `agent-squad`, then the board's release when it is known.
function wordmarkOf(known: string | null): string {
  return known ? `agent-squad (${known})` : 'agent-squad'
}

// The squad's part as a narrow terminal shortens it, longest first (agent-squad #244): with a newer
// release, its notice whole, then its version alone, then none; then the fast-forward goes too.
type SquadPart = { autopilot: boolean; notice: string }
function squadPartsOf(known: string | null, latest: string | null, onAutopilot: boolean): SquadPart[] {
  const isNewer = known !== null && latest !== null && Number(latest.slice(1)) > Number(known.slice(1))
  const notices = isNewer ? [` \u2192 ${latest} available: /squad-upgrade`, ` \u2192 ${latest}`, ''] : ['']
  const parts = notices.map(notice => ({ autopilot: onAutopilot, notice }))
  return onAutopilot ? [...parts, { autopilot: false, notice: '' }] : parts
}
function squadWidthOf(part: SquadPart, known: string | null): number {
  return (part.autopilot ? widthOf(`${AUTOPILOT} `) : 0) + widthOf(wordmarkOf(known)) + widthOf(part.notice)
}

// How many of the agents' parts, given their widths, fit in `columns`, a bar between each two, and
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

// The band's line in `columns` cells (agent-squad #244, #304): the agents on the left, and the
// squad's part on the right, after at least GAP cells. While every agent fits whole, the squad's
// part takes the longest form that fits; only then are the agents cut, as fit() cuts them, beside
// its shortest form. When not even the CTO's part and the ellipsis of the cut fit beside that, the
// squad's part goes, and the line is the CTO's part and the ellipsis, with no refitting: a narrower
// band never shows more than a wider one, and a cut always shows its ellipsis where it fits. It
// gives which of the squad's forms shows (null: none), how many agents, whether the ellipsis does,
// and the cells of space before the squad's part.
function layoutOf(agentWidths: number[], squadWidths: number[], columns: number) {
  const used = (count: number, hasEllipsis: boolean) => agentWidths.slice(0, count).reduce((sum, width) => sum + width, 0)
    + widthOf(SEPARATOR) * Math.max(0, count - 1) + (hasEllipsis ? widthOf(ELLIPSIS) : 0)
  const all = used(agentWidths.length, false)
  const whole = squadWidths.findIndex(width => all + GAP + width <= columns)
  if (whole >= 0) return { squad: whole, count: agentWidths.length, hasEllipsis: false, space: columns - all - squadWidths[whole] }
  const last = squadWidths.length - 1
  const room = columns - GAP - squadWidths[last]
  const cutMark = agentWidths.length > 1 ? widthOf(ELLIPSIS) : 0
  if (agentWidths[0] + cutMark > room) {
    return { squad: null, count: 1, hasEllipsis: cutMark > 0 && agentWidths[0] + cutMark <= columns, space: 0 }
  }
  const cut = fit(agentWidths, room)
  return { squad: last, ...cut, space: columns - used(cut.count, cut.hasEllipsis) - squadWidths[last] }
}

// The latest release as squad-latest.sh last found it (agent-squad #244, #302): the `tag` of
// .agent-squad/latest-release, read with no host command; null when the file is missing,
// unreadable, or holds no `vN` tag.
async function latestOf($: any): Promise<string | null> {
  if (checkout === null) return null
  try {
    const known = JSON.parse(await $.fs.read(`${checkout}/.agent-squad/latest-release`))
    return typeof known?.tag === 'string' && /^v\d+$/.test(known.tag) ? known.tag : null
  } catch {
    return null
  }
}

// The release a board's plugin.json belongs to, as `v42`: the major version, which check-version.sh
// keeps equal to the release. It is read with no host command; null when it cannot be read.
async function manifestRelease($: any, path: string): Promise<string | null> {
  try {
    const manifest = JSON.parse(await $.fs.read(path))
    const major = /^(\d+)\./.exec(String(manifest?.version ?? ''))
    return major ? `v${major[1]}` : null
  } catch {
    return null
  }
}

// The release this session's board belongs to: its own plugin.json, read once, when the board
// starts, so a session not restarted since an upgrade shows the release of the code it loaded.
function releaseOf($: any): Promise<string | null> {
  return manifestRelease($, `${$.plugin.root}/.claude-plugin/plugin.json`)
}

// The installed release (agent-squad #362): the plugin.json of the board in the playbook under the
// main checkout, read at each tick, so that an upgrade shows at once, with no network call.
function installedOf($: any): Promise<string | null> {
  if (checkout === null) return Promise.resolve(null)
  return manifestRelease($, `${checkout}/.agent-squad/playbook/mods/squad-board/.claude-plugin/plugin.json`)
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
    autopilot: isAutopilot,
    background: hasShell,
    release,
    item: itemNow(),
    focus,
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
      isAutopilot = value.autopilot === true
      hasShell = value.background === true
      focus = Array.isArray(value.focus) ? value.focus : value.item ? [value.item] : []
      toasted = value.toasted ?? []
      return
    }
  }
}

// At the session's end its key goes, unless another session of its role has written it since;
// after a /clear the session goes on under a new id, idle, with no item and no shell.
async function leave($: any, sessionId: string) {
  if (!me) return
  const key = keyOf(me.project, me.role)
  const value = await $.store.get(key)
  if (isAgent(value) && value.sessionId === sessionId) await $.store.delete(key)
  state = 'idle'
  tool = null
  hasShell = false
  focus = []
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
  const latest = await latestOf($)
  const installed = await installedOf($)
  await update($, agents, () => ({ byRole, now, latest, installed }))
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
  const repo = await $.session.repo().catch(() => null)
  repository = webOf(repo?.remote ?? null)
  checkout = repo?.root ?? null
  if (since === 0) since = await $.clock.now()
  release = await releaseOf($)
  await publish($)
  $.clock.every(HEARTBEAT_MS, () => void publish($))
  if (me.role !== 'CTO') return
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
  // A prompt, typed or delivered by another session: a pause or autopilot set or cleared by the CEO.
  on('prompt.submit', async ($, e, next) => {
    const step = stepAwayOf(e.text)
    if (me && step !== null && (isPaused !== (step === 'pause') || isAutopilot !== (step === 'autopilot'))) {
      isPaused = step === 'pause'
      isAutopilot = step === 'autopilot'
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
  // A turn of the main loop ends: whether a background shell still runs (agent-squad #264). Stop
  // comes just before turn.complete; a shell's end opens a turn of its own, whose Stop lists none.
  on('classic.Stop', async ($, e, next) => {
    const running = (e.background_tasks ?? []).some(task => task.type === 'shell')
    if (me && running !== hasShell) {
      hasShell = running
      await publish($)
    }
    return next(e)
  })
  on('classic.PermissionRequest', async ($, e, next) => {
    const isQuestion = e.tool_name === 'AskUserQuestion'
    await become($, isQuestion ? 'question' : 'permission', isQuestion ? null : e.tool_name)
    return next(e)
  })
  // A tool call ends a wait; a command that worked moves the session's focus, as its gh calls say.
  on('tool.call', async ($, e, next) => {
    const ran: any = await next(e)
    await resume($)
    if (me && e.tool === 'Bash' && !ran?.isError && !ran?.deny) {
      const input = e as any
      const command = String(input.command ?? '')
      // The body files its gh pr create calls name, read now that the call has ended.
      const bodies: Record<string, string> = {}
      for (const path of bodyFiles(command)) {
        try {
          bodies[path] = String(await $.fs.read(path))
        } catch {
          // A file the board cannot read ties the PR to nothing.
        }
      }
      const moved = focusAfter(focus, command, String(ran?.result?.stdout ?? ''), repository, bodies)
      if (JSON.stringify(moved) !== JSON.stringify(focus)) {
        focus = moved
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

  // The board, in the CTO's session: one line above the prompt between two blue rules. The agents
  // come first, each after a blue bar but the first, its state first, as the CTO's reports on the
  // agents read, then the role's name in its colour; then, on the right, the squad's part:
  // fast-forward on autopilot, the wordmark and the board's release, `-squad` and the release in
  // blue, and the notice of a newer release in the CTO's yellow (agent-squad #244). A narrow
  // terminal shortens the squad's part first, then cuts the agents at their end, the CTO's part
  // whole first (layoutOf). A survey that holds the band goes first.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (me?.role !== 'CTO' || e.props.hasSurvey) return next(e)
    const { Box, Text, Link } = $.ui.resolve(e)
    const seen = await read($, agents)
    const parts = ROLES.map(role => partOf(role, seen.byRole[role], seen.now, seen.installed ?? null))
    const squadParts = squadPartsOf(release, seen.latest ?? null, isAutopilot)
    const { squad: chosen, count, hasEllipsis, space } = layoutOf(parts.map(part => widthOf(textOf(part))),
      squadParts.map(part => squadWidthOf(part, release)), e.props.bodyColumns)
    const squad = chosen === null ? null : squadParts[chosen]
    const shown = parts.slice(0, count)
    const rule = RULE.repeat(Math.max(1, e.props.bodyColumns))
    return (
      <Box flexDirection="column">
        <Box key="rule">
          <Text color={RULE_COLOR} wrap="truncate-end">{rule}</Text>
        </Box>
        <Box key="line" flexDirection="row" overflow="hidden">
          {shown.map((part, index) => (
            <Box key={part.key}>
              {index > 0 && <Text color={RULE_COLOR} wrap="truncate-end">{SEPARATOR}</Text>}
              <Text wrap="truncate-end">{`${part.mark} ${SIGNATURE[part.key]}`}</Text>
              <Text color={ROLE_COLOR[part.key].plain} wrap="truncate-end">
                <Text color={ROLE_COLOR[part.key].key}>{part.key}</Text>
              </Text>
              {part.context !== '' && <Text wrap="truncate-end">{part.context}</Text>}
              {part.restart !== '' && (
                <Text color={ROLE_COLOR.CTO.plain} wrap="truncate-end">
                  <Text color={ROLE_COLOR.CTO.key}>{part.restart}</Text>
                </Text>
              )}
              {part.item && <Text>: </Text>}
              {part.item && (part.item.url?.startsWith('https://')
                ? <Link href={part.item.url}>{labelOf(part.item)}</Link>
                : <Text>{labelOf(part.item)}</Text>)}
            </Box>
          ))}
          {hasEllipsis && <Text dimColor>{ELLIPSIS}</Text>}
          {squad && <Text key="space">{' '.repeat(space)}</Text>}
          {squad && (
            <Box key="squad">
              {squad.autopilot && <Text wrap="truncate-end">{`${AUTOPILOT} `}</Text>}
              <Text wrap="truncate-end">agent</Text>
              <Text color={RULE_COLOR} wrap="truncate-end">-squad</Text>
              {release !== null && <Text color={RULE_COLOR} wrap="truncate-end">{` (${release})`}</Text>}
              {squad.notice !== '' && (
                <Text color={ROLE_COLOR.CTO.plain} wrap="truncate-end">
                  <Text color={ROLE_COLOR.CTO.key}>{squad.notice}</Text>
                </Text>
              )}
            </Box>
          )}
        </Box>
        <Box key="rule-below">
          <Text color={RULE_COLOR} wrap="truncate-end">{rule}</Text>
        </Box>
      </Box>
    )
  })
}
