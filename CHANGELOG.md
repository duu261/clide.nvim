
All notable changes to clide.nvim.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `diagnostics_push` config key — min severity for live `diagnostics_changed`
  pushes (default `"error"`; `false` disables). Cuts token cost of style-lint
  noise entering Claude's context.

### Fixed
- Visual selection now reaches Claude on tmux pane switch without Esc —
  200ms visual-mode poll replaces unreliable ModeChanged/FocusLost delivery.
- "Claude disconnected" notify on `:ClideStop` — on_disconnect ran after the
  state wipe and silently no-op'd; now synchronous in `ws.stop()`.
- Dropped notifications now warn in `:ClideLog` instead of failing silently.

## [0.3.2] — 2026-07-07

### Added
- Follow mode: opt-in jump/notify after Claude writes files
- SessionStart hook primes Claude sessions with clide context
- Tmux panes labeled with project name

### Changed
- SSE/MCP transport path dropped (WS-only going forward)
- Extracted `util/fs` module from init
- Luacheck config and code style updated

### Fixed
- Unsaved buffer selection silently dropped by filePath guard
- Spinner teardown closes wrong handle (spurious "already closing" error)
- PostToolUse hook reads stdin JSON instead of env vars
- Single-line visual selection sync
- Review hint clipping at first/last line
- Terminal closed on `:ClideStop` to prevent orphaned tmux panes
- Follow queue snapshot mode/modified validation

## [0.3.1] — 2026-07-04

### Changed
- Default keymaps moved to `<Leader>m` prefix to avoid clashes
- Keymap configuration split into `review.keymaps` and `cmd_keymaps`

## [0.3.0] — 2026-07-04

### Added
- **Multi-session support** — multiple Claude CLI clients connect to one WS
  server, each with independent RPC dispatch
- **Persistent MCP server** — headless Neovim child process survives Claude
  restarts; `.mcp.json` stays valid
- Fixed SSE port (`42069` default) for stable `.mcp.json` across sessions
- `:ClideRestart` command
- `:checkhealth clide` integration
- Per-hunk accept/reject notifications
- Review keymap hints and toggleterm provider support

### Changed
- Lockfile enforces `0600` permissions
- Probe timeout on lockfile stale detection
- Enhanced README and vimdoc with full feature detail

### Fixed
- Terminal provider test isolation (5 providers, 24 tests)

## [0.2.1] — 2026-07-03

### Added
- Hunk accept/reject and review-complete notifications
- `:ClideSend` confirmation notification
- Startup progress notifications
- Critical SSE errors promoted to user-visible notifications
- Connect/disconnect and critical WS errors promoted to notifications
- `vim_search`, `vim_grep`, `diagnose` MCP tools (17 total)
- `vim_edit` and `luaEval` MCP tools; `executeCode` made live
- Expanded terminal provider test coverage (24 tests, all 5 providers)
- `STATE.md` for cross-session context

### Changed
- Test target made quiet — `TOTAL:` line on success, full log on failure

### Fixed
- Removed dead status cache and stale luacheck ignores
- Hardened deepseek-era servers and tools

## [0.2.0] — 2026-07-03

### Added
- **SSE MCP server** — second transport alongside WebSocket
- `.mcp.json` auto-config with `:ClideInstallMCP`
- Streamable HTTP `POST /sse` (initial implementation)
- SSE server wired into `:ClideStart` startup flow

### Fixed
- SSE `read_start` wrapped in `pcall`
- `vim.schedule` in SSE response path
- Non-GET requests on `/sse` rejected to force HTTP+SSE transport
- LuaJIT compilation error from combined local declaration + assignment

## [0.1.0] — 2026-07-02

### Added
- **WebSocket server** with CSPRNG auth token and lock file discovery
- **RFC 6455 frame codec** with pure-Lua SHA-1 handshake
- **JSON-RPC 2.0 dispatcher** with MCP tool registry
- **12 core MCP tools**: `openFile`, `openDiff`, `saveDocument`,
  `checkDocumentDirty`, `getOpenEditors`, `getCurrentSelection`,
  `getLatestSelection`, `getWorkspaceFolders`, `getDiagnostics`,
  `executeCode`, `close_tab`, `closeAllDiffTabs`
- **Inline per-hunk review** — extmark-anchored hunks with accept/reject
- **Cross-file review queue** with `]h` / `[h` navigation
- **Inline vs. classic diff routing** — `openDiff` routes to inline
  review by default; `:ClideReviewTab` falls back to side-by-side
- **5 terminal providers** — tmux, toggleterm.nvim, snacks.nvim,
  native `:terminal`, none
- **Selection tracking** — debounced `textDocument/didChangeSelection`
  notifications; `@`-mention via `:ClideSend`
- **Statusline integration** — hooks-driven lualine component
  (working/waiting/idle states)
- **`:ClideStart` / `:ClideStop` / `:ClideToggle`** commands
- **`:checkhealth clide`** diagnostics
- **Headless test suite** — plenary/busted, real TCP clients
- **CI** — stable + nightly Neovim matrix, stylua + luacheck gate
- README, vimdoc, MIT license