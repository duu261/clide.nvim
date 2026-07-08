# Claude Code IDE Protocol (reverse-engineered)

Source: `.cc-leak/src/` from leaked Claude Code CLI source (commit `0d0221f`).

## Lockfile protocol

Claude discovers IDE via lockfiles at `~/.claude/ide/<port>.lock`.

### Lockfile filename

Format: `<port>.lock` — port is in the **filename**, not the body content.

Example: `~/.claude/ide/54321.lock` → port 54321.

### Lockfile JSON content

File: `src/utils/ide.ts:73-80`

```typescript
type LockfileJsonContent = {
  workspaceFolders?: string[]   // project directories
  pid?: number                   // IDE process ID
  ideName?: string               // display name ("Neovim")
  transport?: 'ws' | 'sse'      // clide uses 'ws'
  runningInWindows?: boolean     // WSL mode
  authToken?: string             // auth token
}
```

### Lockfile reading

File: `src/utils/ide.ts:346-393`

```typescript
async function readIdeLockfile(path: string): Promise<IdeLockfileInfo | null> {
  const content = readFile(path)
  const parsed = JSON.parse(content) as LockfileJsonContent
  const port = filename.replace('.lock', '')  // port from filename!
  return {
    workspaceFolders,
    port: parseInt(port),
    pid,
    ideName,
    useWebSocket: parsed.transport === 'ws',
    runningInWindows: parsed.runningInWindows ?? false,
    authToken: parsed.authToken,
  }
}
```

## Transport types

Claude's MCP client supports multiple transport types (file: `src/services/mcp/client.ts`):

| `serverRef.type` | Transport | Used for |
|---|---|---|
| `sse` | SSE (EventSource) | Regular MCP servers |
| `sse-ide` | SSE (EventSource) | VS Code/JetBrains IDE (legacy) |
| `ws-ide` | WebSocket + `mcp` subprotocol | **clide.nvim** |
| `ws` | WebSocket | Regular WS MCP servers |

## WebSocket IDE connection (`ws-ide`)

File: `src/services/mcp/client.ts:708-734`

```typescript
} else if (serverRef.type === 'ws-ide') {
  transport = new WebSocketTransport(wsClient)
  // Headers:
  //   User-Agent: <MCP user agent>
  //   X-Claude-Code-Ide-Authorization: <authToken>
  // WebSocket protocol: 'mcp'
}
```

Client connects with:
1. WebSocket URL from lockfile: `ws://127.0.0.1:<port>`
2. Subprotocol: `mcp`
3. Header: `X-Claude-Code-Ide-Authorization: <authToken>` (from lockfile)

## IDE Types Claude detects

File: `src/utils/ide.ts:102-120`

```
cursor | windsurf | vscode | pycharm | intellij | webstorm |
phpstorm | rubymine | clion | goland | rider | datagrip |
appcode | dataspell | aqua | gateway | fleet | androidstudio
```

**Neovim not in the list** — clide is detected as generic IDE via lockfile. The `ideName` field in lockfile JSON is what Claude displays in HUD ("in Neovim"). `runningInWindows` should be set to `false` (explicit false is safer than absent — triggers WSL path conversion when true).

## IDE connection states

File: `src/hooks/useIdeConnectionStatus.ts`

| `ideStatus` | Meaning |
|---|---|
| `null` | No IDE configured |
| `'disconnected'` | Lockfile exists but port closed |
| `'pending'` | Connecting |
| `'connected'` | WebSocket connected, tools listed |

## Tool exposure

Claude runs `tools/list` on IDE MCP connection. Tools discovered become available as `mcp__ide__*` prefixed tools.

### Model-visible tools (2 of 17)

File: `src/services/mcp/client.ts:567-572`

```typescript
const ALLOWED_IDE_TOOLS = ['mcp__ide__executeCode', 'mcp__ide__getDiagnostics']
function isIncludedMcpTool(tool: Tool): boolean {
  return (
    !tool.name.startsWith('mcp__ide__') || ALLOWED_IDE_TOOLS.includes(tool.name)
  )
}
```

Comment at line 2727: *"IDE tools are not going to the model directly"*

Only `executeCode` and `getDiagnostics` are presented to the AI model. The other 15+
clide tools are infrastructure called internally by Claude's hooks — never visible
in the model's tool list.

### Internal RPC (bypasses model)

Claude's hooks call IDE tools directly via `callIdeRpc()` in `client.ts:2116`:

| Hook/caller | Tool called | Purpose |
|---|---|---|
| `useDiffInIDE` | `openDiff` | Open diff tab for review |
| `useDiffInIDE` (cleanup) | `close_tab` | Close diff tab |
| `diagnosticTracking.beforeFileEdited` | `openFile` | Ensure file loaded for LSP |
| `diagnosticTracking.beforeFileEdited` | `getDiagnostics` | Baseline per-file diagnostics |
| `diagnosticTracking.getNewDiagnostics` | `getDiagnostics` | All diagnostics |
| `closeOpenDiffs` (on prompt submit) | `closeAllDiffTabs` | Close all diff tabs |

clide coverage: all 6 internal RPC tools implemented. ✓

## Key hooks for IDE integration

| Hook | File | Purpose |
|---|---|---|
| `useIdeConnectionStatus` | `src/hooks/useIdeConnectionStatus.ts` | Tracks `{ status, ideName }` |
| `useIdeSelection` | `src/hooks/useIdeSelection.ts` | Registers `selection_changed` handler |
| `useIDEStatusIndicator` | `src/hooks/notifs/useIDEStatusIndicator.tsx` | Shows IDE disconnect/selection notifications |
| `useDiffInIDE` | `src/hooks/useDiffInIDE.ts` | Opens diffs via `openDiff` tool |

## Notification flow

Claude subscribes to 3 IDE notifications:

### 1. `selection_changed` — `useIdeSelection` hook

```
clide sends WebSocket notification
  → { method: "selection_changed", params: { text, filePath, selection } }
  → Claude's useIdeSelection hook parses → IDESelection { lineCount, lineStart, text, filePath }
  → IdeStatusIndicator renders "⧉ N lines selected"
  → On prompt submit: getSelectedLinesFromIDE() creates selected_lines_in_ide attachment
```

IDESelection computation:
```typescript
lineCount = end.line - start.line + 1
if (end.character === 0) lineCount--  // last line not actually selected
lineStart = start.line
```

### 2. `at_mentioned` — `useIdeAtMentioned` hook

Params: `{ filePath, lineStart?, lineEnd? }` (0-based, Claude converts to 1-based).

clide intentionally does NOT send this. `selection_changed` with live buffer text
works with unsaved edits; `at_mentioned` would re-read from disk losing edits.

### 3. `log_event` — `useIdeLogging` hook

Params: `{ eventName, eventData }`. Analytics only (prefixed `tengu_ide_`).

## IDE attachment types (how selection becomes prompt context)

File: `src/utils/attachments.ts`

When user submits prompt in Claude, IDE selection becomes prompt attachments
(main thread only, not subagents):

| Attachment type | When | Content |
|---|---|---|
| `selected_lines_in_ide` | `ideSelection.text` present | `{ ideName, lineStart, lineEnd, filename, content, displayPath }` |
| `opened_file_in_ide` | `ideSelection.filePath` present, no text | `{ filename }` + nested memory files |
| `diagnostics` | New diagnostics from `diagnosticTracker` | `{ files: DiagnosticFile[], isNew: true }` |
| `lsp_diagnostics` | Passive LSP server diagnostics | `{ files: DiagnosticFile[], isNew: true }` |

Diagnostics attachments gated on Bash tool presence (need Bash to fix issues).

## Diff open flow

```
Claude calls callIdeRpc('openDiff', ...) (internal RPC, not model call)
  → clide receives, opens diff in nvim
  → Claude's ShowInIDEPrompt renders "Opened changes in Neovim ⧉"
  → Claude waits for response (blocks until one of):
    - [{text: "FILE_SAVED"}, {text: <new_content>}] → accept, apply new edits
    - [{text: "TAB_CLOSED"}, ...] → tab closed, keep proposed edits
    - [{text: "DIFF_REJECTED"}, ...] → reject, revert to old content
  → On cleanup: callIdeRpc('close_tab', { tab_name })
```

On prompt submit (`closeOpenDiffs` in `ide.ts:1274`): `callIdeRpc('closeAllDiffTabs', {})`
— closes all lingering diff tabs from previous turn.

## StatusLine hook

The bottom bar (`[model] │ cwd git │ timer`) is defined by `settings.statusLine.command`. Claude sends JSON input via stdin, reads ANSI output from stdout. Runs on every tool use (debounced 300ms).

## Architecture notes

- Claude CLI runs on **Bun** runtime
- Terminal UI is **React + Ink**
- MCP SDK from `@modelcontextprotocol/sdk` 
- ~1900 files, 512k+ lines TypeScript

## SessionStart hook flow (how IDE banner appears)

File: `src/utils/sessionStart.ts`

```
main.tsx kicks processSessionStartHooks('startup')
  → loadPluginHooks() — memoized
  → executeSessionStartHooks(source, sessionId, agentType, model)
    → Each hook returns: { message, additionalContexts, initialUserMessage, watchPaths }
    → additionalContexts → createAttachmentMessage({ type: 'hook_additional_context', ... })
    → initialUserMessage → stored, consumed by takeInitialUserMessage() (print mode)
  → Returns HookResultMessage[] injected as system context
```

clide's `status.lua:ClideInstallHooks` writes SessionStart hooks to `.claude/settings.local.json`.
The hook command emits `additionalContext` containing the IDE tools banner text
("IDE tools are available under the mcp__ide__ prefix..."). This is how the model
learns about IDE tools at session start.
