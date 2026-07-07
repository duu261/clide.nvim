# clide.nvim: Tools & Protocol

## Protocol Stack

clide.nvim implements the **Claude Code IDE protocol** — a WebSocket-based variant of the Model Context Protocol (MCP) that only the Claude Code CLI uses.

```
┌──────────────────────────────────┐
│        MCP Tool Layer            │  tools/list, tools/call, initialize
├──────────────────────────────────┤
│       JSON-RPC 2.0 Layer         │  { jsonrpc: "2.0", method, params, id }
├──────────────────────────────────┤
│     WebSocket (RFC 6455)         │  frame encode/decode, mask/unmask
├──────────────────────────────────┤
│     HTTP Upgrade Handshake       │  GET / → 101, auth via x-claude-code-ide-authorization
├──────────────────────────────────┤
│     TCP (libuv via vim.uv)       │  127.0.0.1:<ephemeral_port>
└──────────────────────────────────┘
```

### Source map

| Layer | File | Key types |
|-------|------|-----------|
| TCP | `/lua/clide/server/ws.lua` | `vim.uv.new_tcp()`, `listen()`, `read_start()` |
| Handshake | `/lua/clide/server/handshake.lua` | `parse_request()`, `response()`, SHA-1 key |
| Frame | `/lua/clide/server/frame.lua` | `decode()`, `encode()`, `MAX_PAYLOAD = 16MB` |
| RPC | `/lua/clide/server/rpc.lua` | `Dispatcher:handle()`, `:respond()`, `:notify()` |
| Tools | `/lua/clide/tools/init.lua` | `register()`, `list()`, `call()`, `DEFER` |

## Lock File Discovery Protocol

The IDE discovery protocol uses lock files in `~/.claude/ide/`:

**Lock file** (`<port>.lock`):
```json
{
  "pid": <nvim_process_id>,
  "workspaceFolders": ["/path/to/project"],
  "ideName": "Neovim",
  "transport": "ws",
  "authToken": "<32-char lowercase hex>"
}
```

**Protocol values are exact** (`CLAUDE.md` hard constraint):
- `protocolVersion = "2025-03-26"`
- `ideName = "Neovim"`
- `transport = "ws"`

**Auth token**: generated via `vim.uv.random(16)` → hex-encoded to 32 chars. Transmitted in the HTTP upgrade header `x-claude-code-ide-authorization`. Lock file mode `0600`.

## The 17 MCP Tools

All tools are registered in `/lua/clide/tools/init.lua` and each tool module self-registers via `tools.register()` at require time.

### Editor Tools

#### `openFile`

Open a file and optionally select text between anchors.

- **Required**: `filePath`
- **Optional**: `startText`, `endText`, `selectToEndOfLine`, `makeFrontmost`, `preview`
- **Behavior**: Opens file in a normal-file window (preferring existing normal buffers), searches for `startText` using `\V` (very nomagic) search, optionally extends selection to `endText`. If `makeFrontmost = false`, returns metadata without focusing.
- **Returns**: Text result or JSON `{ success, filePath, languageId, lineCount }`
- Source: `/lua/clide/tools/open_file.lua`

#### `openDiff` (blocking/DEFER)

Present a side-by-side diff and wait for accept/reject.

- **Required**: `tab_name`, `new_file_path`, `new_file_contents`
- **Behavior**: Creates a diff tab with scratch buffer showing new content. Registers `BufWriteCmd` (accept) and `BufWipeout` (reject) autocmds. Keymaps: `ga` accept, `gr` reject. **Returns `DEFER`** — the handler does not respond until the user resolves all hunks or closes the tab.
- **Returns**: `FILE_SAVED` + content, or `DIFF_REJECTED`.
- Source: `/lua/clide/tools/open_diff.lua`

#### `vim_edit`

Insert, replace, or delete lines in a file. Applies immediately and saves.

- **Required**: `filePath`, `action` (insert|replace|delete), `line` (1-based)
- **Optional**: `endLine`, `text`
- **Behavior**: Uses `vim.fn.bufadd()` + `vim.fn.bufload()` to handle unopened files. Applies edit via `nvim_buf_set_lines()`, then `vim.cmd("write")`. Triggers `follow.queue()` for follow mode.
- **Returns**: JSON `{ success, lineCount }`
- Source: `/lua/clide/tools/vim_edit.lua`

#### `saveDocument`

Save dirty buffer. Source: `/lua/clide/tools/documents.lua`.

#### `checkDocumentDirty`

Check if a buffer has unsaved changes. Source: `/lua/clide/tools/documents.lua`.

### Info Tools

| Tool | Purpose | Source |
|------|---------|--------|
| `getOpenEditors` | Open tabs + dirty state | `/lua/clide/tools/editors.lua` |
| `getCurrentSelection` | Active selection | `/lua/clide/tools/selection_tools.lua` |
| `getLatestSelection` | Last selection (even unfocused) | `/lua/clide/tools/selection_tools.lua` |
| `getWorkspaceFolders` | Project roots | `/lua/clide/tools/workspace.lua` |
| `getDiagnostics` | LSP diagnostics per-file or all | `/lua/clide/tools/diagnostics.lua` |

### Code Execution Tools

#### `executeCode`

Evaluate arbitrary Lua code in the Neovim process. **No sandbox, no guard, bypasses review** — edits land directly.

- **Required**: `code`
- **Behavior**: Attempts `load("return " .. code)` first, then `load(code)`. Executes via `pcall`. Returns JSON-encoded result, or `vim.inspect` fallback.
- **Security**: The only gate is Claude Code's own permission prompt (if not in auto mode). `executeCode` can do anything Neovim can do: `vim.fn.system()`, `os.remove()`, `debug.getregistry()`, etc.
- Source: `/lua/clide/tools/execute_code.lua`

#### `luaEval`

Alias for `executeCode`. Source: `/lua/clide/tools/lua_eval.lua`.

### Search Tools

| Tool | Description | Source |
|------|-------------|--------|
| `vim_search` | Search current buffer with Vim regex | `/lua/clide/tools/search.lua` |
| `vim_grep` | Project-wide grep via quickfix list | `/lua/clide/tools/grep.lua` |

### Navigation Tools

| Tool | Description | Source |
|------|-------------|--------|
| `close_tab` | Close tab by name | `/lua/clide/tools/tabs.lua` |
| `closeAllDiffTabs` | Close all diff tabs | `/lua/clide/tools/open_diff.lua` |

### Diagnostics Tool

| Tool | Description | Source |
|------|-------------|--------|
| `diagnose` | Check clide setup (Neovim, claude, plenary, lock dir) | `/lua/clide/tools/diagnose.lua` |

## JSON-RPC 2.0 Messages

### IDE → Claude (notifications)

#### `selection_changed`

Sent when the user's selection changes (via `ModeChanged` autocmd + cursor events).

```json
{
  "jsonrpc": "2.0",
  "method": "selection_changed",
  "params": {
    "text": "selected text content",
    "filePath": "/absolute/path/to/file",
    "fileUrl": "file:///absolute/path/to/file",
    "selection": {
      "start": { "line": 10, "character": 5 },
      "end": { "line": 15, "character": 20 },
      "isEmpty": false
    }
  }
}
```

Source: `/lua/clide/selection.lua`.

#### At-mention (`ClideSend`)

Explicit user-triggered context attachment via `:<line1,line2>ClideSend`. Sends file path + line range. Source: `/lua/clide/commands.lua` lines 14-20.

### Claude → IDE (RPC)

#### `initialize`

```json
{
  "jsonrpc": "2.0", "method": "initialize",
  "params": { "protocolVersion": "2025-03-26", ... },
  "id": "1"
}
```

Response: `{ protocolVersion: "2025-03-26", capabilities: { tools: { listChanged: true } }, serverInfo: { name: "clide.nvim", version: "0.1.0" } }`.

#### `tools/list`

Response: `{ tools: [{ name, description, inputSchema }, ...] }` — all 17 tools, sorted alphabetically.

#### `tools/call`

```json
{
  "jsonrpc": "2.0", "method": "tools/call",
  "params": { "name": "openFile", "arguments": { "filePath": "/path/to/file" } },
  "id": "2"
}
```

## Important: CLI Host Tool Gap

When Claude connects via the IDE protocol, the **Claude Code CLI host** only exposes 2 of the 17 tools as actual MCP tools (`mcp__ide__executeCode` and `mcp__ide__getDiagnostics`). The other 15 tools are registered in clide.nvim's WS protocol and respond correctly to `tools/call`, but the CLI host has no MCP schema for them — so Claude can't call them directly.

**Impact**: When Claude tries to use `openFile` or `openDiff`, it gets "No such tool available." It falls back to implementing the same operations via `executeCode` + Lua, which works but bypasses the inline review flow.

**This is a Claude Code CLI limitation, not a clide.nvim bug.** The VS Code extension has full access to all tools. If Anthropic adds the remaining tools to the CLI host, clide.nvim will support them immediately.

## Protocol Reference

The full protocol specification (reverse-engineered from the VS Code extension) is documented at:

- `docs/PROTOCOL.md` — Protocol details, discovery, auth, message types, remote IDE mode, headless mode, MCP stdio transport.
