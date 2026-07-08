# VS Code Extension Gap Analysis

Official extension: `Anthropic.claude-code` on open-vsx (v2.1.204, 30M+ downloads). NOT the dead `anthropic-labs/vscode-mcp` link referenced in early protocol docs.

Extension architecture: thin UI shell (webview chat panel + editor toolbar buttons) over the Claude Code CLI binary. Process management, auth, API calls, and agent orchestration live in the CLI; the extension registers IDE tools via `@modelcontextprotocol/sdk` and renders results. clide.nvim replaces the webview with nvim-native UI (buffers, floating windows, statusline).

## Protocol parity: 12/12 tools verified

All 12 IDE tools in clide.nvim match official extension tool descriptions exactly. Verified 2026-07-08 by extracting string literals from minified extension.js. Blind-built, zero tool-schema errors.

| # | Tool | clide.nvim | VS Code |
|---|------|-----------|---------|
| 1 | `openFile` | Open file, optionally select range | Same |
| 2 | `openDiff` | Open git diff for file | Same |
| 3 | `getCurrentSelection` | Current selection in active editor | Same |
| 4 | `getLatestSelection` | Most recent selection (any editor) | Same |
| 5 | `getOpenEditors` | Currently open editors | Same |
| 6 | `getWorkspaceFolders` | Workspace folders | Same |
| 7 | `getDiagnostics` | Language diagnostics | Same |
| 8 | `checkDocumentDirty` | Unsaved changes check | Same |
| 9 | `saveDocument` | Save dirty document | Same |
| 10 | `close_tab` | Close editor tab | Same |
| 11 | `closeAllDiffTabs` | Close all diff tabs | Same |
| 12 | `executeCode` | Lua (full nvim process) | Python/Jupyter only |

## Features to close (VS Code has, clide.nvim lacks)

### High priority

1. **@-mention insertion.** `Alt+K` in editor inserts current file/selection into Claude chat input. Core UX flow — sends context to Claude without leaving the editor. clide.nvim equivalent: a keymap that yanks the file path or selection and feeds it to the Claude tmux pane or a dedicated nvim command.

2. **Diff accept/reject toolbar.** Editor toolbar buttons with `claude-vscode.viewingProposedDiff` context key. One-click accept/reject above the diff view. clide.nvim has per-hunk accept/reject inline (better granularity) but no floating toolbar — the nvim equivalent would be a which-key menu or a floating window with accept/reject/all bindings.

### Medium priority

3. **Session list sidebar.** Dedicated sidebar showing past Claude conversations, clickable to reopen. clide.nvim equivalent: a Telescope/fzf-lua picker over session files, or a `:ClideSessions` command that populates a quickfix list.

4. **Session reopen.** `Cmd+Shift+T` reopens the last closed Claude session. Simple state — store last session ID and expose `:ClideReopen`.

5. **Create worktree.** `Claude Code: Create Worktree` command. git-worktree management from Claude. nvim has `:Git worktree` via fugitive or gitsigns — could be a thin command wrapper.

### Low priority

6. **Walkthrough onboarding.** 4-step getting-started guide in VS Code walkthrough UI. nvim equivalent: `:help clide` (already exists via vimdoc) or a `:ClideSetup` wizard.

7. **Settings JSON schema validation.** Validates `.claude/settings.json` against bundled 125KB JSON schema. nvim: leverage `jsonls` (lspconfig) with the schema — no custom code needed, just document the schema path.

8. **Autosave before read/write.** Saves dirty files before Claude accesses them. clide.nvim: expose a config option `autosave = true` that calls `:wa` before tool dispatch.

9. **Python env auto-activation.** Auto-activates workspace Python environment for `executeCode`. N/A for clide.nvim — executeCode runs Lua in the nvim process, no Python needed.

## Features clide.nvim leads on (keep, promote)

| Feature | clide.nvim | VS Code |
|---------|-----------|---------|
| **Inline per-hunk review** | Accept/reject individual hunks in buffer | All-or-nothing diff view |
| **executeCode power** | Full nvim Lua eval — any editor operation | Python/Jupyter only, no editor access |
| **Terminal providers** | tmux, toggleterm, snacks, native | Terminal only |
| **Follow mode** | Auto-jump nvim to Claude-edited files | No equivalent |
| **Buffer-centric send** | Send any buffer, not just saved files | Files-on-disk only |
| **Selection auto-push** | Auto-pushes selection to Claude with dedup | Manual @-mention only |
| **Tool timing in log** | Per-call duration in `:ClideLog` | No timing |
| **executeCode audit trail** | Every eval logged | No audit trail |

## Extension settings reference

Key settings from VS Code extension `package.json` (for comparison when designing clide.nvim config):

- `environmentVariables`: array of `{name, value}` passed to Claude process
- `useTerminal`: bool, run Claude in integrated terminal
- `allowDangerouslySkipPermissions`: bool
- `respectGitIgnore`: bool, default true
- `initialPermissionMode`: `default` / `manual` / `acceptEdits` / `plan` / `bypassPermissions`
- `autosave`: bool, default true
- `useCtrlEnterToSend`: bool
- `preferredLocation`: `sidebar` / `panel`
- `enableNewConversationShortcut`: bool, default true
- `enableReopenClosedSessionShortcut`: bool, default true
- `hideOnboarding`: bool
- `usePythonEnvironment`: bool, default true (N/A for nvim)

## Key bindings (VS Code)

| Binding | Action |
|---------|--------|
| `Alt+K` | Insert @-mention (editor) |
| `Cmd+Escape` / `Ctrl+Escape` | Focus/blur Claude (toggle) |
| `Cmd+Shift+Escape` | Open Claude in editor tab |
| `Cmd+N` | New conversation (when Claude focused, optional) |
| `Cmd+Shift+T` | Reopen closed session (optional) |

## Commands (VS Code extension IDs)

`claude-vscode.editor.open`, `claude-vscode.editor.openLast`, `claude-vscode.primaryEditor.open`, `claude-vscode.window.open`, `claude-vscode.createWorktree`, `claude-vscode.sidebar.open`, `claude-vscode.newConversation`, `claude-vscode.reopenClosedSession`, `claude-vscode.update`, `claude-vscode.focus`, `claude-vscode.blur`, `claude-vscode.logout`, `claude-vscode.terminal.open`, `claude-vscode.acceptProposedDiff`, `claude-vscode.rejectProposedDiff`, `claude-vscode.insertAtMention`, `claude-vscode.installPlugin`, `claude-vscode.showLogs`, `claude-vscode.openWalkthrough`.

## Scoring

| Dimension | clide.nvim | VS Code | Edge |
|-----------|-----------|---------|------|
| Protocol compliance | 12/12 tools | 12/12 | Tie |
| Diff review UX | Per-hunk inline | All-or-nothing | clide |
| executeCode capability | Full nvim | Python-only | clide |
| Onboarding | vimdoc only | Walkthrough + sidebar | VS Code |
| Session management | None | Sidebar + reopen | VS Code |
| @-mention workflow | None | `Alt+K` insert | VS Code |
| Terminal flexibility | 5 providers | 1 | clide |
| Audit/logging | Timing + eval trail | None | clide |
| Follow mode | Auto-jump to edits | None | clide |
