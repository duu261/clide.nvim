# clide.nvim — v0.3.1

Pure-Lua Neovim plugin implementing the Claude Code IDE protocol (WebSocket
MCP) with inline per-hunk review. Multi-session: multiple `claude` clients can
connect to the same Neovim instance concurrently.

## Transport

| Transport | Type | Port | Auth |
|-----------|------|------|------|
| WebSocket | IDE protocol (claude CLI), multi-client | Lock file | CSPRNG hex token |

SSE transport dropped at `b511f6c` (2026-07-06). WS-only going forward.

## Tools (17)

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

## Tests — 129 passed, 0 failed (`make test`)

| Area | Tests | File |
|------|-------|------|
| Core protocol (WS, RPC, frame, handshake) | 20 | ws_spec, rpc_spec, frame_spec, handshake_spec |
| Inline review (engine, queue, render) | 14 | review_engine_spec, review_queue_spec |
| Terminal providers (none, native, tmux, snacks, dispatch) | 24 | terminal_spec |
| Simple tools (workspace, editors, diag, docs, tabs, eval) | 8 | tools_simple_spec |
| Other (selection, config, lockfile, status, init) | 44 | selection_spec, config_spec, lockfile_spec, status_spec, init_spec |
| openFile, openDiff tools | 19 | tools_openfile_spec, tools_opendiff_spec |

### Coverage gaps
- tmux provider tests skip actual pane creation (side effects)
- snacks provider tests minimal (installed dep assumed)
- SSE transport tests removed with transport (`b511f6c`)

## Quality
- Luacheck: 0 warnings, 0 errors (only frame.lua's documented 143 shim ignore remains)
- Stylua: clean (`stylua --check lua/ tests/`)
- CI: stable+nightly matrix, runs stylua + luacheck on push.
- `make lint` mirrors CI (stylua + luacheck)
- Dogfooded: session completed entirely through clide.nvim's own protocol

## Docs
- `docs/SCOPE.md` — project purpose, core flows, done definition, roadmap
- `docs/WORKFLOW.md` — branch/worktree, providers, token budget, dev cycle

## Build history
`.superpowers/sdd/progress.md` (gitignored, local only) — full task-level build log,
hand-test results (T1-T12), bug fix chronology, release checklists. Kept locally
because it references absolute paths and local-only tooling.
