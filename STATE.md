# clide.nvim — v0.3.0

Pure-Lua Neovim plugin implementing the Claude Code IDE protocol (WS + SSE
MCP) with inline per-hunk review.

## Transports

| Transport | Type | Port | Auth |
|-----------|------|------|------|
| WebSocket | IDE protocol (claude CLI) | Lock file | CSPRNG hex token |
| SSE | MCP server (.mcp.json) | Dynamic | Session ID |

## Tools (17)

All available over both WS and SSE transports.

### Editor
- `openFile` — Open file, select by string anchor
- `openDiff` — Side-by-side diff view
- `saveDocument` — Save dirty buffer
- `checkDocumentDirty` — Check unsaved changes
- `vim_edit` — Insert/replace/delete lines, writes immediately

### Info
- `getOpenEditors` — Open tabs + dirty state
- `getCurrentSelection` — Active selection
- `getLatestSelection` — Last selection (even unfocused)
- `getWorkspaceFolders` — Project roots
- `getDiagnostics` — LSP diagnostics (one file or all)

### Code execution
- `executeCode` — Evaluate Lua in Neovim
- `luaEval` — Alias for executeCode

### Search
- `vim_search` — Search current buffer with Vim regex
- `vim_grep` — Project-wide grep via quickfix list

### Diagnostics
- `diagnose` — Check clide setup (Neovim, claude, plenary)

### Navigation
- `close_tab` — Close tab by name
- `closeAllDiffTabs` — Close all diff tabs

## Tests — 101 passing, 0 failing

| Area | Tests | File |
|------|-------|------|
| Core protocol (WS, SSE, RPC, frame, handshake) | 20 | ws_spec, sse_spec, rpc_spec, frame_spec, handshake_spec |
| Inline review (engine, queue, render) | 14 | review_engine_spec, review_queue_spec |
| Terminal providers (none, native, tmux, snacks, dispatch) | 24 | terminal_spec |
| Simple tools (workspace, editors, diag, docs, tabs, eval) | 8 | tools_simple_spec |
| MCP config (install, merge, idempotent) | 4 | sse_spec (MCP config block) |
| Other (selection, sha1, config, lockfile, status, init) | 31 | selection_spec, sha1_spec, config_spec, lockfile_spec, status_spec, init_spec |
| openFile, openDiff tools | ~18 | tools_openfile_spec, tools_opendiff_spec |

### Coverage gaps
- No test for `ClideReviewTab` command (uses untested `open_classic` fallback)
- tmux provider tests skip actual pane creation (side effects)
- snacks provider tests minimal (installed dep assumed)

## Quality
- Luacheck: 0 warnings, 0 errors (55 files)
- Stylua: formatted
- CI: stable + nightly neovim, stylua check, luacheck
- Dogfooded: session completed entirely through clide.nvim's own protocol

## Known gaps for next release
- `ClideReviewTab` untested open_classic code path
- Terminal: skip tmux/snacks real-pane tests

## Build history
`.superpowers/sdd/progress.md` (gitignored, local only) — full task-level build log,
hand-test results (T1-T12), bug fix chronology, release checklists. Kept locally
because it references absolute paths and local-only tooling.
