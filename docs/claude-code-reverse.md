# Claude Code HUD & IDE Protocol (reverse-engineered from leaked source)

Source: `.cc-leak/` (gitignored, `git clone --depth 1 https://github.com/codeaashu/claude-code.git`)

## HUD components (footer bar)

| Component | File | What it renders |
|---|---|---|
| **StatusLine** | `src/components/StatusLine.tsx` | Configurable via `settings.statusLine.command`. Receives JSON input. |
| **PromptInputFooterLeftSide** | `src/components/PromptInput/PromptInputFooterLeftSide.tsx` | Mode pill, permissions, vim, loading, tasks/teams/tmux pills, history |
| **Notifications** | `src/components/PromptInput/Notifications.tsx` | IDE selection, MCP status, autoupdater, wrapped input |
| **IdeStatusIndicator** | `src/components/IdeStatusIndicator.tsx` | `⧉ N lines selected` / `⧉ In filename` |
| **ShowInIDEPrompt** | `src/components/ShowInIDEPrompt.tsx` | `Opened changes in {ideName} ⧉` |
| **BridgeStatusIndicator** | in `PromptInputFooter.tsx` | Bridge mode status pill |
| **CoordinatorTaskPanel** | `src/components/CoordinatorAgentStatus.tsx` | Agent coordinator info |

## All ⧉ indicators (exhaustive)

| File | Renders |
|---|---|
| `IdeOnboardingDialog.tsx:82` | `⧉ open files` (hint text) |
| `IdeOnboardingDialog.tsx:89` | `⧉ selected lines` (hint text) |
| `IdeStatusIndicator.tsx:29` | `⧉ {N} {lines} selected` |
| `IdeStatusIndicator.tsx:49` | `⧉ In {basename}` |
| `ShowInIDEPrompt.tsx:44` | `Opened changes in {ideName} ⧉` |
| `AttachmentMessage.tsx:160` | `⧉ Selected ...` (message history) |
| `useDiffInIDE.ts:63` | Diff tab title `⧉` |

## Selection flow (clide → Claude HUD)

```
clide sends selection_changed via WS
  → useIdeSelection hook parses { text, filePath, selection }
  → type IDESelection = { lineCount, lineStart?, text?, filePath? }
  → IdeStatusIndicator checks:
    1. text + lineCount > 0  → "⧉ N lines selected"
    2. filePath only         → "⧉ In {basename}"
```

## StatusLine input (JSON sent to hook command)

```typescript
interface StatusLineCommandInput {
  model: { id: string; display_name: string }
  workspace: {
    current_dir: string
    project_dir: string
    added_dirs: string[]
  }
  version: string
  output_style: { name: string }
  cost: {
    total_cost_usd: number
    total_duration_ms: number
    total_api_duration_ms: number
    total_lines_added: number
    total_lines_removed: number
  }
  context_window: {
    total_input_tokens: number
    total_output_tokens: number
    context_window_size: number
    current_usage: number
    used_percentage: number
    remaining_percentage: number
  }
  exceeds_200k_tokens: boolean
  rate_limits?: {
    five_hour?: { used_percentage: number; resets_at: number }
    seven_day?: { used_percentage: number; resets_at: number }
  }
  vim?: { mode: string }
  agent?: { name: string }
  remote?: { session_id: string }
  worktree?: { name, path, branch, original_cwd, original_branch }
  session_name?: string
}
```

## IDE status notifications

| State | Notification |
|---|---|
| connected + selection | `⧉ N lines selected` (pill in Notifications) |
| connected + no selection | `⧉ In {file}` if filePath present |
| connected | no selection pill |
| disconnected | `{ideName} disconnected` (error notification) |
| install error | `IDE extension install failed` |
| hint | `/ide for {ideName}` (low priority, 3s delay) |

## Key hooks

| Hook | File | Purpose |
|---|---|---|
| `useIdeConnectionStatus` | `src/hooks/useIdeConnectionStatus.ts` | Returns `{ status, ideName }` from MCP clients |
| `useIdeSelection` | `src/hooks/useIdeSelection.ts` | Registers selection_changed handler |
| `useIDEStatusIndicator` | `src/hooks/notifs/useIDEStatusIndicator.tsx` | Renders IDE notifications |

## Notable discoveries from leak

- Runtime: **Bun**
- Terminal UI: **React + Ink**
- ~1900 files, 512k+ lines TypeScript
- Features: Buddy (tamagotchi), KAIROS (always-on), ULTRAPLAN, "Dream" system, Undercover Mode
- ~40 tools, ~85 slash commands

## IDE tool filtering (CRITICAL for clide architecture)

File: `src/services/mcp/client.ts:567-572`

```typescript
// For the IDE MCP servers, we only include specific tools
const ALLOWED_IDE_TOOLS = ['mcp__ide__executeCode', 'mcp__ide__getDiagnostics']
function isIncludedMcpTool(tool: Tool): boolean {
  return (
    !tool.name.startsWith('mcp__ide__') || ALLOWED_IDE_TOOLS.includes(tool.name)
  )
}
```

Comment at line 2727: "IDE tools are not going to the model directly"

**Implication for clide**: Only `executeCode` and `getDiagnostics` reach the AI model.
All other 15 clide tools (`openDiff`, `openFile`, `close_tab`, etc.) are infrastructure
called internally by Claude's hooks via `callIdeRpc()` — never presented to the model
as callable tools. `executeCode` is THE power tool — everything model-actionable should
be accessible through it.

## Internal IDE RPC (bypasses model)

All IDE tools except `executeCode` + `getDiagnostics` are called via `callIdeRpc()`
(`src/services/mcp/client.ts:2116`). These calls originate in:

| Call site | Tool | Params | Used for |
|---|---|---|---|
| `useDiffInIDE.ts:284` | `openDiff` | `{ old_file_path, new_file_path, new_file_contents, tab_name }` | Open diff in IDE |
| `useDiffInIDE.ts:339` | `close_tab` | `{ tab_name }` | Close diff tab after accept/reject |
| `diagnosticTracking.ts:114` | `openFile` | `{ filePath, preview, startText, endText, selectToEndOfLine, makeFrontmost }` | Ensure file loaded for LSP |
| `diagnosticTracking.ts:147` | `getDiagnostics` | `{ uri }` | Baseline diagnostics before edit |
| `diagnosticTracking.ts:200` | `getDiagnostics` | `{}` | All diagnostics for new issues |
| `ide.ts:1274` | `closeAllDiffTabs` | `{}` | On prompt submit (new conversation turn) |

clide coverage: all 6 tools implemented. ✓

## Notification subscriptions (Claude subscribes to 3 from IDE)

### 1. `selection_changed` — `src/hooks/useIdeSelection.ts`

Zod schema:
```typescript
z.object({
  method: z.literal('selection_changed'),
  params: z.object({
    selection: z.object({
      start: z.object({ line: z.number(), character: z.number() }),
      end: z.object({ line: z.number(), character: z.number() }),
    }).nullable().optional(),
    text: z.string().optional(),
    filePath: z.string().optional(),
  }),
})
```

Computes `IDESelection`:
```typescript
type IDESelection = {
  lineCount: number        // end.line - start.line + 1
  lineStart?: number       // start.line
  text?: string
  filePath?: string
}
// lineCount-- when end.character === 0 (last line not actually selected)
```

clide: `send_at_mention()` sends this. Word-only selection with `vim.fn.getregion()`
produces real column positions, so `end.character` is accurate. ✓

### 2. `at_mentioned` — `src/hooks/useIdeAtMentioned.ts`

Zod schema:
```typescript
z.object({
  method: z.literal('at_mentioned'),
  params: z.object({
    filePath: z.string(),
    lineStart: z.number().optional(),  // 0-based, Claude converts to 1-based
    lineEnd: z.number().optional(),    // 0-based, Claude converts to 1-based
  }),
})
```

**clide NOT sending this.** Intentional: `selection_changed` sends live buffer text
(works with unsaved edits), while `at_mentioned` just passes `filePath+range` (Claude
re-reads from disk, losing unsaved edits). Low priority to add as secondary notification.

### 3. `log_event` — `src/hooks/useIdeLogging.ts`

Zod schema:
```typescript
z.object({
  method: z.literal('log_event'),
  params: z.object({
    eventName: z.string(),              // prefixed "tengu_ide_" by Claude
    eventData: z.object({}).passthrough(),
  }),
})
```

Analytics only. clide: not implemented, low priority.

## Prompt attachment pipeline

File: `src/utils/attachments.ts`

When user submits prompt, `getAttachments()` runs async. IDE selection is processed
as TWO attachments (main thread only, not subagents):

### `ide_selection` — `getSelectedLinesFromIDE()` (line 1615)

When user has text selected (`ideSelection.text` present):
```typescript
{
  type: 'selected_lines_in_ide',
  ideName: string,
  lineStart: number,  // 0-based
  lineEnd: number,    // 0-based (lineStart + lineCount - 1)
  filename: string,
  content: string,    // the selected text
  displayPath: string, // relative to cwd
}
```

Gated on: connected IDE, `lineStart !== undefined`, `text` present, `filePath` present,
file not denied by permissions.

### `ide_opened_file` — `getOpenedFileFromIDE()` (line 1864)

When file is opened but nothing selected (`ideSelection.filePath` present, `text` absent):
```typescript
{
  type: 'opened_file_in_ide',
  filename: string,
}
```

Plus nested memory files (CLAUDE.md, rules) for that file's directory tree.

### Other main-thread IDE attachments:
- `diagnostics` — `getDiagnosticAttachments()`: new diagnostics from `diagnosticTracker`
- `lsp_diagnostics` — `getLSPDiagnosticAttachments()`: from passive LSP servers

Both gated on Bash tool presence (you need Bash to fix issues).

## SessionStart hook flow

File: `src/utils/sessionStart.ts`

```
main.tsx kicks processSessionStartHooks('startup')
  → loadPluginHooks() — memoized, noop if already loaded
  → executeSessionStartHooks(source, sessionId, agentType, model, ...)
    → iterates hook results:
      - message: HookResultMessage → pushes to hookMessages[]
      - additionalContexts: string[] → collects
      - initialUserMessage: string → stored via takeInitialUserMessage()
      - watchPaths: string[] → updateWatchPaths()
  → additionalContexts → createAttachmentMessage({ type: 'hook_additional_context', ... })
  → returns HookResultMessage[]
```

clide's `status.lua:ClideInstallHooks` writes SessionStart hooks to
`.claude/settings.local.json` that inject the IDE tools banner via `additionalContext`.
This is how `"IDE tools are available under the mcp__ide__ prefix"` appears.

## openDiff response protocol (confirmed)

Three response types from `openDiff` tool:

| Response | Meaning | Claude action |
|---|---|---|
| `[{text: "FILE_SAVED"}, {text: <new_content>}]` | Accepted with possible edits | Applies new edits |
| `[{text: "TAB_CLOSED"}, ...]` | Tab closed, keep proposed | Uses original edits |
| `[{text: "DIFF_REJECTED"}, ...]` | Rejected | Reverts to old content |

`close_tab` returns `[{text: "TAB_CLOSED"}]`.
All errors are caught silently by Claude (does not crash the turn).

clide: all response values match protocol. ✓
