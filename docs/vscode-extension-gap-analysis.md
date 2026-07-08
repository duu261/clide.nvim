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

Status: ~~struck~~ = closed, **bold** = open, *italic* = N/A.

### High priority

1. ~~**@-mention insertion.**~~ `:ClideSend` (visual selection), `:ClideSendFile` (file content), `:ClideSendBuffer` (any buffer). Content lands directly in Claude context via `selection_changed` notify — no `openFile` round-trip. VS Code `Alt+K` inserts a reference into chat input; clide sends the content. Different UX, same outcome. *(Closed 2026-07-08: send commands + selection auto-push)*

2. **Diff accept/reject toolbar.** Editor toolbar buttons with `claude-vscode.viewingProposedDiff` context key. clide.nvim has inline per-hunk review with hint_line showing all keymaps + buffer-local keymap descriptions — more granular but no floating toolbar. Acceptable: hint_line serves the same discoverability role.

### Medium priority

3. ~~**Session list sidebar.**~~ `:ClideSessions` opens `vim.ui.select` picker over `~/.claude/sessions/` JSON files, sorted newest-first with timestamp, status, name, and cwd. Pick to resume. *(Closed 2026-07-08: `:ClideSessions`)*

4. ~~**Session reopen.**~~ `:ClideContinue` launches `claude --continue` with IDE integration env vars. *(Closed 2026-07-08: `:ClideContinue`)*

5. ~~**Create worktree.**~~ `:ClideWorktree [path]` runs `git worktree add` in a terminal, defaults to `~/worktrees/<timestamp>`. *(Closed 2026-07-08: `:ClideWorktree`)*

### Low priority

6. **Walkthrough onboarding.** 4-step getting-started guide in VS Code walkthrough UI. nvim: `:checkhealth clide` + `:help clide` + README quickstart. Low priority for nvim users.

7. **Settings JSON schema validation.** VS Code bundles 125KB JSON schema for `.claude/settings.json`. nvim: `jsonls` (lspconfig) handles JSON schema natively. No custom code needed.

8. ~~**Autosave before read/write.**~~ `autosave = true` config (default). Calls `:wa` (pcall'd) before every tool dispatch. Matches VS Code default. *(Closed 2026-07-08: `autosave` config)*

9. * **Python env auto-activation.** * N/A — clide's `executeCode` runs Lua in the nvim process, no Python needed.

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

## Scoring (updated 2026-07-08)

| Dimension | clide.nvim | VS Code | Edge |
|-----------|-----------|---------|------|
| Protocol compliance | 12/12 tools | 12/12 | Tie |
| Diff review UX | Per-hunk inline | All-or-nothing | **clide** |
| executeCode capability | Full nvim | Python-only | **clide** |
| Terminal flexibility | 5 providers | 1 | **clide** |
| Audit/logging | Timing + eval trail | None | **clide** |
| Follow mode | Auto-jump to edits | None | **clide** |
| Selection push | Auto-push + dedup | Manual @-mention | **clide** |
| Buffer-centric send | Any buffer | Files-on-disk only | **clide** |
| Context delivery | Direct push, no round-trip | @-mention → openFile loop | **clide** |
| Autosave | `:wa` before dispatch | Per-file save | Tie |
| Worktree | `:ClideWorktree` | `createWorktree` command | Tie |
| Session management | `:ClideSessions` + `:ClideContinue` | Sidebar + Cmd+Shift+T | Tie |
| Onboarding | `:checkhealth` + `:help` + README | Walkthrough | VS Code |
| Settings schema | jsonls (lspconfig) | Bundled 125KB schema | VS Code |

**Score: clide leads 9 dimensions, VS Code leads 2 (both low-priority). 3 ties.**
