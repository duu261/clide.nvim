# clide.nvim

Claude Code in Neovim — pure Lua, inline per-hunk review.

clide.nvim implements the Claude Code IDE protocol (WebSocket-MCP) directly
in Lua on `vim.uv`, plus an SSE MCP server for tool discovery via `.mcp.json`.
When Claude proposes edits, they appear as hunks **inside your real buffers**
— accept or reject each one, Zed/Cursor style.

## ✨ Features

- **Pure Lua** — No Node, no Rust. Neovim >= 0.10 + `claude` CLI only.
- **Full protocol parity** — lock-file discovery, CSPRNG auth, all 17 MCP
  tools, selection tracking, `@`-mentions.
- **Dual transport** — WebSocket (IDE protocol) + SSE (MCP via `.mcp.json`).
- **Multi-session** — Multiple Claude CLI clients connect to one WS server,
  each with independent RPC dispatch.
- **Inline review** — Per-hunk accept/reject in your real buffers, cross-file
  review queue with `]h` / `[h`.
- **5 terminal providers** — tmux, toggleterm.nvim, snacks.nvim, native
  `:terminal`, or none (run claude yourself).
- **Statusline integration** — lualine component with working/waiting/idle
  states driven by Claude Code hooks.

## ⚡ Requirements

- Neovim >= 0.10
- `claude` CLI in PATH
- `nvim-lua/plenary.nvim`
- (optional) tmux, toggleterm.nvim, or snacks.nvim for terminal provider

## 📦 Install

```lua
-- lazy.nvim
{
  "duu261/clide.nvim",
  opts = {},
  cmd = { "ClideStart", "ClideToggle" },
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

Or any plugin manager — just add to your runtimepath and call
`require("clide").setup({})`.

## 🚀 Quick start

```vim
:ClideStart      " Start server + launch claude
" Ask Claude to edit a file — hunks appear inline
ga               " Accept hunk
gr               " Reject hunk
]h / [h          " Next / previous pending hunk (cross-files)
:'<,'>ClideSend  " At-mention selected range in Claude's context
```

First run? `:checkhealth clide` verifies everything.

## ⚙️ Configuration (defaults)

```lua
require("clide").setup({
  autostart = false,
  log_level = "info",
  terminal = {
    provider = "auto",      -- auto | native | tmux | toggleterm | snacks | none
    cmd = "claude",
    split_side = "right",
    split_width = 0.35,
  },
  review = {
    inline = true,          -- false = side-by-side diff tab
    keymaps = {
      accept = "ga", reject = "gr",
      accept_all = "gA", reject_all = "gR",
      next_hunk = "]h", prev_hunk = "[h",
    },
  },
})
```

### Terminal providers

| Provider | How | Pros | Cons |
|----------|-----|------|------|
| `tmux` | tmux pane | Survives Neovim restart, full scrollback | Requires `$TMUX` |
| `toggleterm` | toggleterm.nvim | Toggle-able, clean UI | Requires toggleterm.nvim |
| `snacks` | snacks.nvim | Toggle-able, clean UI | Requires snacks.nvim |
| `native` | `:terminal` | No deps | Scrollback lost with buffer |
| `none` | Print env vars | Full control | Manual setup |

`auto` resolves: tmux → toggleterm → snacks → native.

## Commands

| Command | Action |
|---------|--------|
| `:ClideStart` / `:ClideStop` | Start/stop server + claude |
| `:ClideRestart` | Stop then start |
| `:ClideToggle` | Toggle claude terminal |
| `:'<,'>ClideSend` | At-mention selected range |
| `:ClideReviewTab` | Reopen review as diff tab |
| `:ClideInstallHooks` | Install status hooks in `.claude/settings.local.json` |
| `:ClideInstallMCP` | Write `.mcp.json` + auto-approve |
| `:ClideLog` | Show log ring buffer |
| `:checkhealth clide` | Diagnose setup |

## 🧠 How it works

```
┌──────────────┐    WS (IDE protocol)     ┌──────────────┐
│  Claude CLI  │◄─────────────────────────►│  clide.nvim  │
│  (agent)     │                           │  (Neovim)    │
│              │    SSE (.mcp.json)        │              │
│              │◄──────────────────────────│  SSE server  │
└──────────────┘                           └──────────────┘
```

Neovim binds a WS server (IDE protocol) and an SSE MCP server on `127.0.0.1`,
writes `~/.claude/ide/[port].lock` with a CSPRNG auth token, and launches
`claude` with `CLAUDE_CODE_SSE_PORT` + `ENABLE_IDE_INTEGRATION=true`. The SSE
server auto-writes `.mcp.json` (default SSE port `42069`). Claude drives the
editor over JSON-RPC 2.0 / MCP. See [PROTOCOL.md](PROTOCOL.md) for the full
reverse-engineered protocol reference.

WS internals informed by MIT-licensed
[coder/claudecode.nvim](https://github.com/coder/claudecode.nvim).

### Transports

| Transport | Role | Port | Auth |
|-----------|------|------|------|
| WebSocket | IDE protocol (claude CLI) | Dynamic (lock file) | CSPRNG hex token |
| SSE | MCP via `.mcp.json` | Configurable (default 42069) | Session ID |

Both bound to `127.0.0.1` only.

### Tools (17)

Every tool over both transports.

**Editor** — `openFile`, `openDiff`, `saveDocument`, `checkDocumentDirty`,
`vim_edit`

**Info** — `getOpenEditors`, `getCurrentSelection`, `getLatestSelection`,
`getWorkspaceFolders`, `getDiagnostics`

**Code** — `executeCode`, `luaEval`

**Search** — `vim_search` (buffer), `vim_grep` (project quickfix)

**Diagnostics** — `diagnose` (Neovim, claude CLI, plenary check)

**Navigation** — `close_tab`, `closeAllDiffTabs`

### Multi-session

One WS server, multiple Claude CLI clients, each with independent dispatch:

```
Client A ──→ WS ──→ session A RPC ──→ tool handlers
Client B ──────────→ session B RPC ──→ tool handlers
```

Selection notifications broadcast to all sessions. Disconnecting one client
never affects others. `:ClideStop` closes all sessions cleanly.

## 🔬 Quality

```
53 Lua files · 0 luacheck warnings · 0 luacheck errors
```

**Tests** — Run `make test` for live total (~120+ tests):

| Area | Tests |
|------|-------|
| Core protocol (WS, SSE, RPC, frame, handshake) | 20 |
| Inline review (engine, queue, render) | 14 |
| Terminal providers | 24 |
| Tools (workspace, editors, diag, tabs, eval, search) | 27 |
| MCP config | 4 |
| Other (selection, sha1, config, lockfile, status, init) | 31 |

**Dogfooded** — Every README update, diagnostic check, and buffer save in
this session went through WS → JSON-RPC → tool handler. End-to-end.

**CI** — stable+nightly Neovim matrix, stylua + luacheck on push.

## 🔌 Comparison

Other Neovim plugins implementing the Claude Code IDE protocol:

| Plugin | Lang | Inline review | Multi-session | Terminal provider | Tools |
|--------|------|--------------|--------------|------------------|-------|
| **clide.nvim** | Lua | ✅ inline hunks | ✅ per-client RPC | 5 (tmux/native/toggleterm/snacks/none) | 17 |
| [pi-ide.nvim](https://github.com/ldelossa/pi-ide.nvim) | Go | ❌ side-by-side diff | ❌ singleton | N/A (external) | ~12 |
| [vibing.nvim](https://github.com/shabaraba/vibing.nvim) | Lua | ✅ inline preview | ✅ concurrent | N/A (CLI adapter) | MCP |
| [agentic.nvim](https://neovimcraft.com/plugin/carlos-algms/agentic.nvim) | Lua | ❌ side-by-side diff | ✅ multi-agent | N/A (ACP protocol) | ACP |
| [mcp-nvim](https://github.com/cousine/neovim-mcp) | Lua | N/A (MCP only) | N/A | N/A | 48 |

**clide.nvim differentiators:**
- Only Lua plugin with both WS (IDE protocol) **and** SSE (MCP) transports
- Inline hunks anchored via extmarks — survive your own edits
- 5 terminal provider options — tmux, toggleterm, snacks, native, or none
- No external binaries — pure Lua on `vim.uv`
- Forks from `coder/claudecode.nvim` but completely rewritten (dual transport, multi-session, inline review)

## ❓ FAQ

**Claude doesn't connect?** Run `:checkhealth clide` first. Ensure `claude`
CLI is in PATH and `:ClideStart` ran without errors.

**"E444: Cannot close last window"?** Means the claude terminal is the only
window. Open a file or `:ClideToggle` to show the editor.

**Can I run multiple Claude instances?** Yes. Each connects as its own
session — good for side-by-side agents on different files.

**Hunks not showing up?** Make sure `review.inline = true` (default). Use
`:ClideReviewTab` as fallback to side-by-side diff.

**How to stop everything?** `:ClideStop` — kills server, removes lockfile,
closes all sessions.

**Port 42069 already in use?** Set `sse_port` in setup to a different value.

## 📄 License

MIT
