<!-- openwiki:auto-generated — run `openwiki --update` to refresh. Do not edit manually. -->
# clide.nvim Quickstart

> **Repository**: [duu261/clide.nvim](https://github.com/duu261/clide.nvim)
> **Status**: Pre-1.0 active development (current: v0.3.2)
> **Language**: Pure Lua — no Node.js or Rust dependencies.
> **License**: MIT (see /LICENSE)

## What is clide.nvim?

clide.nvim is a **Neovim plugin** that implements the **Claude Code IDE protocol** (WebSocket MCP) entirely in Lua with no external language runtimes. It lets Claude Code control Neovim — opening files, editing buffers, showing diffs, running searches — all through Neovim's own buffers with inline per-hunk review.

Think of it as the Zed/Cursor inline edit review experience, but for Neovim + Claude Code.

Key differentiators from the broader ecosystem:
- **Pure Lua** — No Node.js process, no Rust binary. Just Neovim >= 0.10 + `claude` CLI.
- **Inline per-hunk review** — Edits appear as hunks inside your real buffers with accept/reject per hunk.
- **Multi-session** — Multiple `claude` CLI clients can connect to the same Neovim instance concurrently.
- **5 terminal providers** — tmux, toggleterm.nvim, snacks.nvim, native `:terminal`, or none.

## Requirements

- **Neovim >= 0.10** — requires `vim.uv`, `vim.base64`, `vim.fs`, `vim.getregion`
- **claude CLI** — `npm install -g @anthropic-ai/claude-code`
- **plenary.nvim** — `nvim-lua/plenary.nvim`

## Quick Install

### lazy.nvim

```lua
{
  "duu261/clide.nvim",
  opts = {},
  cmd = { "ClideStart", "ClideToggle" },
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

### Any plugin manager

Add to runtimepath and call `require("clide").setup({})`.

## Quick Start (5 seconds)

```vim
:ClideStart    " Start server + launch Claude in a terminal
" Ask Claude to edit a file — hunks appear inline in your buffer
<Leader>ma     " Accept hunk under cursor
<Leader>mr     " Reject hunk under cursor
]h / [h        " Next / previous pending hunk (cross-file)
<Leader>mt     " Toggle Claude terminal
<Leader>ms     " Start clide (keyboard-friendly)
```

First run? `:checkhealth clide` verifies everything.

## Core User Flow

1. **Start**: `:ClideStart` launches a WebSocket server on a random port, writes a lock file to `~/.claude/ide/<port>.lock`, and spawns `claude` CLI in a terminal with the protocol environment variables.
2. **Connect**: The `claude` CLI discovers the lock file, authenticates via a CSPRNG-generated 32-char hex token, and connects over WebSocket.
3. **Work**: Claude uses the 17 MCP tools (`openFile`, `vim_edit`, `openDiff`, `executeCode`, etc.) to interact with Neovim.
4. **Review**: When Claude edits files via `openDiff`, changes appear as inline hunks. Accept/reject each hunk individually, or use `<Leader>mA`/`<Leader>mR` for bulk actions.
5. **Stop**: `:ClideStop` closes the server, removes the lock file, and cleans up the terminal.

## Commands

| Command | Description |
|---------|-------------|
| `:ClideStart` | Start server + launch Claude |
| `:ClideStop` | Stop server + close terminal |
| `:ClideRestart` | Stop then start |
| `:ClideToggle` | Toggle Claude terminal |
| `:{range}ClideSend` | At-mention range in Claude's context |
| `:ClideReviewTab` | Reopen inline review as side-by-side diff tab |
| `:ClideReviewList` | List pending review hunks in quickfix |
| `:ClideLog` | Show log ring buffer |
| `:ClideInstallHooks` | Install status hooks into `.claude/settings.local.json` |

## Configuration

All keys optional. `setup()` works without arguments — defaults apply.

```lua
require("clide").setup({
  autostart = false,         -- Start automatically on Neovim load?
  execute_code = true,       -- Set false to disable executeCode tool
  diagnostics_push = "error",-- Min severity for live diagnostics push ("error"|"warn"|"info"|"hint"|false)
  follow = "off",            -- "off" | "jump" | "notify" | "both"
  log_level = "info",        -- "debug" | "info" | "warn" | "error"
  terminal = {
    provider = "auto",       -- auto | native | snacks | tmux | none
    cmd = "claude",
    split_side = "right",
    split_width = 0.35,
  },
  review = {
    inline = true,           -- false = side-by-side diff tab
    hint_line = true,        -- Show keymap hint at top of buffer
    keymaps = {
      accept = "<Leader>ma",
      reject = "<Leader>mr",        -- accept_all = "<Leader>mA",
      reject_all = "<Leader>mR",    -- next_hunk = "]h",
      prev_hunk = "[h",
    },
  },
  cmd_keymaps = {
    toggle = "<Leader>mt",
    start = "<Leader>ms",
    stop = "<Leader>mq",
    log = "<Leader>ml",
    send = "<Leader>me",           -- visual: send selection
    send_toggle = "<Leader>mz",    -- visual: send + toggle terminal
  },
})
```

See [architecture.md](architecture.md) for the full module map and lifecycle, and `:help clide` (from `/doc/clide.txt`) for the vimdoc reference.

## Documentation Map

| Page | What it covers |
|------|----------------|
| [architecture.md](architecture.md) | Module map, WS server lifecycle, RPC dispatch, tool registry, review pipeline, terminal providers, config model |
| [development.md](development.md) | Branch/workflow discipline, dev cycle, testing, linting, release checklist, provider roles |
| [tools-and-protocol.md](tools-and-protocol.md) | 17 MCP tools in detail, protocol layers (frame → handshake → RPC), lock file discovery, auth, CLI host gaps |

## Source Overview

```
lua/clide/
├── init.lua           # Plugin entry: setup(), start(), stop(), state
├── config.lua         # Setup options with defaults
├── commands.lua       # :Clide* user commands
├── lockfile.lua       # ~/.claude/ide/<port>.lock management
├── selection.lua      # Selection sync (WS selection_changed)
├── follow.lua         # Post-edit follow mode (jump/notify/both)
├── status.lua         # Statusline component + hook integration
├── health.lua         # :checkhealth clide
├── server/
│   ├── ws.lua         # TCP server, lifecycle, connection mgmt
│   ├── frame.lua      # RFC 6455 frame codec
│   ├── handshake.lua  # WS upgrade + auth token validation
│   └── rpc.lua        # JSON-RPC 2.0 dispatcher
├── tools/
│   ├── init.lua       # Tool registry (17 tools)
│   ├── open_file.lua  # openFile tool
│   ├── open_diff.lua  # openDiff tool (side-by-side diff)
│   ├── vim_edit.lua   # Insert/replace/delete lines
│   ├── execute_code.lua # eval Lua in Neovim
│   ├── ... (12 more)  # see tools-and-protocol.md
├── review/
│   ├── engine.lua     # Hunk computation, open, resolve
│   ├── queue.lua      # Review queue, cross-file navigation
│   └── render.lua     # Extmark rendering, per-hunk keymaps
├── terminal/
│   └── init.lua       # Terminal provider dispatch
│   (native, tmux, toggleterm, snacks, none)
└── util/
    ├── log.lua        # Ring-buffer logger
    ├── fs.lua         # Pure-uv file I/O
    ├── sha1.lua       # Pure-Lua SHA-1 (for WS handshake)
    └── eol.lua        # Line-ending handling
```
