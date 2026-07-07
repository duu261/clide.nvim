# clide.nvim Architecture

## Overview

clide.nvim is organized as a set of independent Lua modules under `lua/clide/`. There is no separate Neovim plugin state beyond the `require("clide").state` table, which holds the server handle, connected clients, and connectivity flag.

## Module Map

```
plugin/clide.lua          ──►  guards (vim.g.loaded_clide), loads commands
                                  │
lua/clide/init.lua        ──►  setup(), start(), stop(), toggle()
                                  │
                    ┌─────────────┼─────────────────┐
                    │             │                   │
              config.lua    commands.lua        selection.lua
              lockfile.lua  follow.lua          status.lua
              health.lua
                    │
          ┌─────────┼─────────┐
          │         │         │
      server/    tools/    review/
      ws.lua     init.lua  engine.lua
      frame.lua  open_*    queue.lua
      handshake  vim_edit  render.lua
      .lua       execute_
      rpc.lua    code.lua
                 ...
                    │
          ┌─────────┴─────────┐
          │                   │
      terminal/           util/
      init.lua            log.lua
      native.lua          fs.lua
      tmux.lua            sha1.lua
      toggleterm.lua      eol.lua
      snacks.lua
      none.lua
```

## Lifecycle: `:ClideStart` → Claude connected

1. **Guard check** — `init.lua:M.start()` checks `M.state.server`; if already running, notifies and returns.
2. **Tool setup** — `require("clide.tools").setup()` loads all 17 tool modules; each self-registers via `tools.register()` at require time. Source: `/lua/clide/tools/init.lua` lines 61-80.
3. **Stale lock cleanup** — `lockfile.clean_stale()` scans `~/.claude/ide/*.lock` and deletes entries whose PID is no longer alive. Source: `/lua/clide/lockfile.lua` lines 47-61.
4. **Auth token** — `lockfile.generate_token()` calls `vim.uv.random(16)` and hex-encodes to 32 chars. Source: `/lua/clide/lockfile.lua` lines 16-21. **Never use `math.random`** for this (`CLAUDE.md` hard constraint).
5. **WebSocket server start** — `ws.start()` binds `127.0.0.1:0` (OS-assigned ephemeral port). `on_connect` creates a new RPC dispatcher per client. Source: `/lua/clide/server/ws.lua` lines 17-68.
6. **Lock file write** — Lock file written to `~/.claude/ide/<port>.lock` with JSON: `{ pid, workspaceFolders, ideName: "Neovim", transport: "ws", authToken }`. Mode `0600`. Source: `/lua/clide/lockfile.lua` lines 27-39.
7. **Terminal launch** — `terminal.open()` resolves provider (auto→tmux>snacks>native), launches `claude` with `CLAUDE_CODE_SSE_PORT=<port>` and `ENABLE_IDE_INTEGRATION=true`. Source: `/lua/clide/terminal/init.lua`.
8. **Claude connects** — Claude discovers lock file, sends WS upgrade with `x-claude-code-ide-authorization` header. Handshake validates header against token, returns 101 or 401. Source: `/lua/clide/server/handshake.lua`.
9. **RPC dispatch** — Each connected client gets a dedicated `rpc.new(send_fn)` dispatcher. Handles `initialize`, `tools/list`, `tools/call`, and pending notifications. Source: `/lua/clide/server/rpc.lua`.

## WebSocket Server (`lua/clide/server/`)

### ws.lua

- Creates a `vim.uv.new_tcp()` handle bound to `127.0.0.1:0` (ephemeral port, avoids collision retries).
- Listens with backlog 16. Each accept creates a `{ sock, buf, ready, rejected }` client state.
- `read_start` accumulates data into `client.buf`, calls `M.process()` wrapped in `pcall`.
- `M.process()` delegates to handshake until `client.ready`, then calls `frame.decode()` to parse RFC 6455 frames.
- Control frames (PING → PONG, CLOSE → disconnect) and text frames (dispatch to `on_message`).
- `ws.send(client, text)` encodes a FIN+text frame with `frame.encode()`.
- Source: `/lua/clide/server/ws.lua`

### frame.lua (RFC 6455 codec)

- Pure-Lua frame decoder/encoder using LuaJIT `bit` module (`band`, `bor`, `bxor`, `rshift`, `lshift`, `unpack`).
- Incoming frames from clients are **masked** (RFC 6455 §5.1); unmask in 4096-byte chunks to stay within `string.char` argument limits.
- Enforce `MAX_PAYLOAD = 16 * 1024 * 1024` to prevent unbounded buffer growth.
- Server frames are unmasked with FIN always set.
- Source: `/lua/clide/server/frame.lua`

### handshake.lua

- Parses HTTP upgrade request (`GET / HTTP/1.1\r\n...`).
- Validates: method must be `GET`, `Sec-WebSocket-Key` present, `Upgrade: websocket`.
- Auth: compares `x-claude-code-ide-authorization` header against `auth_token`. Returns `HTTP/1.1 401 Unauthorized` on mismatch.
- Computes `Sec-WebSocket-Accept` via SHA-1 of key + magic GUID `258EAFA5-E914-47DA-95CA-C5AB0DC85B11`.
- Source: `/lua/clide/server/handshake.lua`

### rpc.lua (JSON-RPC 2.0 dispatcher)

- `M.new(send)` creates a per-client dispatcher with a `send` closure.
- Three recognized methods:
  - `initialize` — responds with `protocolVersion: "2025-03-26"`, capabilities, `serverInfo: { name: "clide.nvim", version: "0.1.0" }`.
  - `tools/list` — responds with `{ tools: tools.list() }`.
  - `tools/call` — dispatches through `tools.call(name, args, respond)`, which calls the registered handler.
  - Unknown methods with `id` → error `-32601`. Notifications (no `id`) → silently ignored per JSON-RPC 2.0.
- Respond method encodes `{ jsonrpc: "2.0", id, result }` or `{ jsonrpc: "2.0", id, error }`.
- Notify method sends `{ jsonrpc: "2.0", method, params }` (no `id`).
- Source: `/lua/clide/server/rpc.lua`

## Tool Registry (`lua/clide/tools/`)

### Registration pattern

Each tool module calls `tools.register({ name, description, inputSchema, handler })` at module load time. Source: `/lua/clide/tools/init.lua` lines 14-17.

**Handler contract**: `handler(args, respond)` — two calling conventions:
- **Synchronous**: handler returns a result table directly (or via `tools.text_result`/`tools.json_result`).
- **Deferred**: handler returns `tools.DEFER`, then calls `respond()` later. Used by `openDiff` (blocks until user accepts/rejects all hunks).

**Sentinel**: `tools.DEFER` is a unique table with `__tostring` returning `"clide.tools.DEFER"`.

### The 17 MCP Tools

| Tool | File | Description |
|------|------|-------------|
| `openFile` | `open_file.lua` | Open file, select by string anchors |
| `openDiff` | `open_diff.lua` | Side-by-side diff tab (blocking: returns DEFER) |
| `vim_edit` | `vim_edit.lua` | Insert/replace/delete lines, writes immediately |
| `executeCode` | `execute_code.lua` | Evaluate Lua in Neovim (no sandbox) |
| `luaEval` | `lua_eval.lua` | Alias for executeCode |
| `saveDocument` | `documents.lua` | Save dirty buffer |
| `checkDocumentDirty` | `documents.lua` | Check unsaved changes |
| `getOpenEditors` | `editors.lua` | Open tabs + dirty state |
| `getCurrentSelection` | `selection_tools.lua` | Active selection |
| `getLatestSelection` | `selection_tools.lua` | Last selection (even unfocused) |
| `getWorkspaceFolders` | `workspace.lua` | Project roots |
| `getDiagnostics` | `diagnostics.lua` | LSP diagnostics |
| `vim_search` | `search.lua` | Search current buffer with Vim regex |
| `vim_grep` | `grep.lua` | Project-wide grep via quickfix |
| `diagnose` | `diagnose.lua` | Check clide setup |
| `close_tab` | `tabs.lua` | Close tab by name |
| `closeAllDiffTabs` | `tabs.lua` | Close all diff tabs |

### Important: CLI Host Tool Gap

Claude Code CLI host exposes only **2 of these 17** as actual MCP tools (`executeCode`, `getDiagnostics`). The other 15 are registered in clide.nvim's WS protocol and respond to `tools/call`, but the CLI host has no MCP schema for them — Claude cannot call them directly. Claude falls back to using `executeCode` + Lua to simulate `openFile`, etc.

This is a **Claude Code CLI limitation**, not a clide.nvim bug. The VS Code extension has full access to all 12+ tools. See [tools-and-protocol.md](tools-and-protocol.md) for details.

## Review Pipeline (`lua/clide/review/`)

The review system implements **inline per-hunk accept/reject**, triggered by the `openDiff` tool.

### Flow

1. `openDiff` handler receives `{ tab_name, new_file_path, new_file_contents }`.
2. `engine.open()` loads the buffer, computes diff hunks via `vim.diff()` with `result_type = "indices"`.
3. If zero hunks (content identical), responds immediately with `FILE_SAVED`.
4. If hunks exist, creates a `review` record attached to the buffer.
5. `render.attach()` places extmarks on each hunk:
   - Added lines appear as virtual text (green, `ClideAdded` highlight, `+ ` prefix).
   - Deleted lines are marked with `hl_group = "ClideDeleted"` and `hl_eol = true`.
   - A hint extmark at the top of the buffer shows keymap bindings.
6. Per-buffer keymaps registered: accept/reject/accept_all/reject_all.
7. `render.detach()` clears extmarks and keymaps when done.

### Resolution

- `engine.resolve_hunk(review, hunk, verdict)` — marks hunk as accepted/rejected, applies edits immediately on accept (inserts new lines, deletes old), updates cursor position via extmarks.
- When all hunks resolved, `engine.finish()` calls the deferred `respond()` callback with `FILE_SAVED` and final content.
- The review queue (`queue.lua`) tracks all active reviews across buffers and provides cross-file navigation (`]h`, `[h`).

### Key source files

- `/lua/clide/review/engine.lua` — `compute_hunks()`, `open()`, `resolve_hunk()`, `resolve_all()`, `resolve_at_cursor()`
- `/lua/clide/review/queue.lua` — `add()`, `remove()`, `find()`, `current()`, `counts()`, `statusline()`, `jump()`
- `/lua/clide/review/render.lua` — `attach()`, `detach()`, `set_hint()`, `set_keymaps()`, `hunk_row()`

## Lock File Discovery Protocol

clide.nvim follows the Claude Code IDE discovery protocol:

1. Server binds to `127.0.0.1:<ephemeral_port>`.
2. Writes `~/.claude/ide/<port>.lock`:
   ```json
   {
     "pid": <nvim PID>,
     "workspaceFolders": ["/path/to/project"],
     "ideName": "Neovim",
     "transport": "ws",
     "authToken": "<32-char hex from CSPRNG>"
   }
   ```
3. Launches `claude` with `CLAUDE_CODE_SSE_PORT=<port>` and `ENABLE_IDE_INTEGRATION=true`.
4. Claude reads lock files, authenticates via `x-claude-code-ide-authorization` header.
5. On `:ClideStop`, lock file is deleted.

Key constraints:
- **Bind `127.0.0.1` only** — never `0.0.0.0` (hard constraint from `CLAUDE.md`).
- **CSPRNG token** — `vim.uv.random(16)`, never `math.random`. Never log the token.
- **Lock file mode `0600`** — owner-read/write only.
- **Stale cleanup** — `clean_stale()` removes locks for dead PIDs on start.

## Config Model (`lua/clide/config.lua`)

- Defaults table is deep-copied at module load.
- `setup(opts)` validates `follow` mode, then `vim.tbl_deep_extend("force", defaults, opts)`.
- `get()` returns the current config (always read through `config.get()`, never access module state directly).
- No schema validation beyond the `follow` mode enum check.
- Source: `/lua/clide/config.lua`

## Selection Sync (`lua/clide/selection.lua`)

Two pipelines for getting selection context to Claude:

1. **WS `selection_changed` notification** — clide.nvim sends selection objects to Claude over the WS connection. Built from current visual selection or cursor position.
2. **At-mention (`:ClideSend`)** — sends `filePath` + line range via `send_at_mention()` for explicit context attachment.

Key detail: the filePath guard for unsaved buffers was removed in commit `ed40693` — now passes through regardless of save state. Source: `/lua/clide/selection.lua`.

## Follow Mode (`lua/clide/follow.lua`)

After Claude writes files:
- **off** — no action
- **jump** — open last Claude-written file
- **notify** — notify with file path
- **both** — both jump and notify

Writes coalesce by burst (10ms defer timer). Same-buffer dirty check prevents useless splits (`bfa384e`). `pcall` around `vim.cmd.edit` prevents crash on stale/deleted paths (`b459b8f`). Source: `/lua/clide/follow.lua`.

## Statusline (`lua/clide/status.lua`)

- File-system event watcher on `~/.local/state/clide/status`.
- Spinner animation (200ms timer) for "working" state.
- `M.lualine()` returns formatted string: empty when stopped, `" idle"` / `" working"` / `" waiting"` / `" disconnected"`, with review progress.
- Hook integration: writes `.claude/settings.local.json` hooks that update the state file on `PostToolUse` events.
- Source: `/lua/clide/status.lua`

## Terminal Providers (`lua/clide/terminal/`)

| Provider | File | When used |
|----------|------|-----------|
| auto | `init.lua` | Resolves: tmux > snacks > toggleterm > native |
| tmux | `tmux.lua` | Inside `$TMUX` |
| snacks | `snacks.lua` | If snacks.nvim installed |
| toggleterm | `toggleterm.lua` | If toggleterm.nvim installed |
| native | `native.lua` | Built-in `:terminal` split |
| none | `none.lua` | Prints env vars, user runs Claude manually |

Provider selection happens once at `terminal.open()` time via the `auto` provider. Source: `/lua/clide/terminal/init.lua`.

## Utilities (`lua/clide/util/`)

- **log.lua** — Ring-buffer logger (200 lines). `warn`/`error` levels also trigger `vim.notify`. `:ClideLog` opens buffer.
- **fs.lua** — Pure-uv file I/O: `write_file()`, `read_file()`, `mkdir_p()`, `list_locks()`. No plenary dependency.
- **sha1.lua** — Pure-Lua SHA-1 implementation using LuaJIT `bit` module. Required for WebSocket handshake `Sec-WebSocket-Accept`.
- **eol.lua** — EOL handling: `join()` preserves trailing newline based on `bo.eol`.

## Notification data flow and state lifecycle

`selection_changed` / `diagnostics_changed` path:

```
selection.lua autocmds → notify_fn closure (init.lua M.start)
  → server.sessions[*].rpc:notify → ws.send
```

Ownership rules (learned the hard way, `dbea330`):

- Client sessions live on `server.sessions` (the WS server object), NOT on
  `M.state`. `M.stop()` does `M.state = {}` — anything stored on `M.state`
  and expected to survive stop will break.
- `M.state.server = server` must stay set: `M.stop()` needs it to call
  `ws.stop()` and remove the lockfile. It was once missing — server kept
  running invisibly, and the notify guard silently dropped every
  notification.
- Guards that drop notifications must log (`log.log("warn", ...)`). A
  silent drop cost a full debugging session; see development.md lessons.

Two independent paths deliver editor context to Claude:

1. WS `selection_changed` JSON-RPC notification (this plugin's code).
2. Claude CLI's built-in IDE auto-push (`at_mentioned`). Works even when
   path 1 is broken — seeing selections in a Claude conversation does NOT
   prove path 1 works.

Naming trap: the `CLAUDE_CODE_SSE_PORT` env var name is mandated by the
Claude CLI; the transport is WS. The old SSE/MCP transport was removed in
`b511f6c` — do not hunt for SSE code or `.mcp.json` writers.

CLI quirk: Claude CLI caches the last NON-empty selection and re-injects it
into every prompt; it ignores the empty (`isEmpty = true`) cursor updates the
plugin sends after leaving visual mode. A "ghost" selection in Claude's
context is CLI-side caching, not a plugin re-send — verify via
`require("clide.selection")._last` before debugging the plugin.
