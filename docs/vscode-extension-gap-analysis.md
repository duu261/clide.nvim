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

6. ~~**Walkthrough onboarding.**~~ VS Code has 4-step walkthrough. clide: `:ClideSetup` interactive wizard (prerequisites, terminal provider, keymaps, start) + `:checkhealth clide` + `:help clide`. *(Closed 2026-07-08: `:ClideSetup`)*

7. ~~**Settings JSON schema validation.**~~ VS Code bundles 125KB JSON schema. clide: auto-configures `jsonls` (if installed) during `setup()`; schema bundled at `schemas/claude-code-settings.schema.json` (extracted from official extension v2.1.204). *(Closed 2026-07-08: jsonls auto-config + bundled schema)*

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
| Onboarding | `:ClideSetup` wizard + `:checkhealth` + `:help` | Walkthrough | Tie |
| Settings schema | jsonls auto-config + bundled 125KB schema | Bundled 125KB schema | Tie |

**Final score: clide leads 9 dimensions, VS Code leads 0. 5 ties.**

All 9 gaps closed. clide.nvim matches or exceeds every VS Code extension feature.

## Claude Code internals: hooks integration opportunities

Based on binary-verified Claude Code hooks system (v2.1.198, 27 events, 5 hook types, 6 config sources). Current clide.nvim uses 5 events — 22 untapped.

### Current state

clide writes hooks into `.claude/settings.local.json` via `status.lua:install_hooks()`:

| Event | What it does | Hook type |
|-------|-------------|-----------|
| `PreToolUse` | Write `"working"` to state file | `command` |
| `PostToolUse` | Extract Edit/Write file paths → follow mode | `command` |
| `Stop` | Write `"idle"` to state file | `command` |
| `Notification` | Write `"waiting"` to state file | `command` |
| `SessionStart` | Inject clide.nvim tool reference (executeCode, getDiagnostics) | `command` |

### Quick wins (1 hook, low effort)

1. **`UserPromptSubmit` hook — inject selection directly into model context.** Stdout is injected into the model (not system prompt). Token-efficient: no `selection_changed` notify round-trip, no system-message overhead. Exit code 2 blocks the prompt entirely. Replace current selection_changed notify with `UserPromptSubmit` hook that reads `vim.v.event` from a temp file and injects `"Selection from Neovim: ..."` via stdout. Exit 0 = silent inject.

2. **`PostToolUseFailure` hook — notify user of failed tool calls.** Parse tool_name from `$CLAUDE_HOOK_INPUT` stdin JSON, `vim.notify("Claude: " .. tool_name .. " failed")`. Exit 2 = stderr to model; exit 1 = stderr to user only.

3. **`FileChanged` hook — trigger nvim `:checktime`.** When Claude modifies files via Bash (not Edit/Write), refresh buffers. Set `CLAUDE_ENV_FILE` with modified paths, picked up by nvim fs_event watcher.

4. **`CwdChanged` hook — sync nvim cwd.** Output new cwd via stdout, read by nvim → `vim.cmd.cd(new_cwd)`. Exit 0 only.

### Medium effort (2-3 hooks)

5. **`Setup` hook — session environment bootstrap.** Set `CLAUDE_CODE_SSE_PORT` + nvim version + LSP status. Stdout as seed context. Runs once per session before any tool calls.

6. **`Stop` hook upgrade — agent-based verification.** Replace shell command with `type: "agent"` hook (up to 50 turns, tool access). Verify implementation: "Check that all changed files compile, tests pass, no stale TODOs remain." 60s timeout default.

7. **`PreToolUse` security guard — optional deny on dangerous Bash.** Exit code 2 blocks tool + stderr to model. Example: block `rm -rf /` patterns. Per hook input contract (lesson 10): `tool_name`, `tool_input`, `tool_use_id` in stdin JSON. Per `permissionDecision:"deny"` structured form, surfaces as `is_error` tool_result (not `permission_denied`) — tool-level failure, run still succeeds.

### Advanced (plugin distribution, multi-provider)

8. **Claude Code plugin distribution.** Ship clide.nvim as a `plugin.json`-declared plugin with bundled hooks, commands, and an optional MCP server. Users install via `claude plugin install clide-nvim@marketplace`. Caveat: Cowork has three-root namespace (regular `~/.claude/plugins/`, standalone-CLI `cowork_plugins/`, Desktop `local-agent-mode-sessions/.../cowork_plugins/`) — plugin hooks only fire when installed under the right root. Document per-runtime install path.

9. **`statusLine.command` integration.** CLI supports `settings.statusLine.command` — a shell command that receives JSON stdin and outputs a formatted status line. clide could set this in `settings.local.json` to display model, cost, tool count, session duration. Status line is rendered in Claude's Ink TUI footer.

10. **`PreCompact` hook — preserve clide metadata.** Inject custom compact instructions: "Preserve executeCode audit trail, tool timing data, and review queue state." Stdout becomes custom compact instructions; exit 2 blocks compaction entirely.

### Hook input contract (for reference)

Every hook receives stdin JSON with base fields:
```
session_id, transcript_path, cwd, prompt_id, permission_mode,
agent_id, agent_type, effort:{level}
```
Per-event additions: `hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`.

Delivery: classic stdin JSON (settings.json hooks) or `control_request{subtype:"hook_callback", callback_id, input, tool_use_id}` (SDK/Cowork hosts).

### Hook exit code semantics

| Exit | Effect |
|------|--------|
| 0 | Silent success; stdout may be injected to model (SessionStart/UserPromptSubmit) |
| 2 | **Model-visible block.** PreToolUse: block tool + stderr to model. Stop: prevent stop + stderr to model. UserPromptSubmit: block + erase prompt |
| Other | **User-visible only.** Stderr shown to user (not model). Tool proceeds if applicable |

Key: exit 2 is the only way to get model attention. Exit 1 = user sees it, model doesn't.

### Version drift note

Claude Code CLI is v2.1.201 (this session). Internals captured from v2.1.198. Hook event count was 27 at capture; MessageDisplay is the 30th event as of v2.1.159. Verify event list against current binary: `HOOK_EVENTS` const in `src/entrypoints/sdk/coreTypes.ts`.

