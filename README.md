# clide.nvim

Claude Code in Neovim — pure Lua, zero dependencies, inline per-hunk review.

clide.nvim implements the Claude Code IDE protocol (the same WebSocket-MCP
channel the official VS Code extension uses) directly in Lua on `vim.uv`.
When Claude proposes edits, they appear as hunks **inside your real buffers**
— accept or reject each one, Zed/Cursor style — instead of a side-by-side
diff tab.

## Features

- **Minimal dependencies** — Neovim >= 0.10, the `claude` CLI, and plenary.nvim. No Node, no Rust.
- **Full protocol parity** — lock-file discovery, auth, all 12 MCP tools,
  selection tracking, `@`-mentions.
- **Inline review** — per-hunk accept/reject with extmark-anchored hunks that
  survive your own edits; cross-file review queue with `]h` / `[h`.
- **tmux built in** — claude runs in a real tmux pane that survives Neovim.
  Also: native `:terminal`, snacks.nvim, or none (run claude anywhere).
- **Statusline** — working / waiting / idle via Claude Code hooks, lualine component.

## Install

lazy.nvim:

```lua
{
  "duu261/clide.nvim",
  opts = {},
  cmd = { "ClideStart", "ClideToggle" },
  dependencies = { "nvim-lua/plenary.nvim" },
},
```

## Quick start

1. `:ClideStart` — starts the server and launches `claude` in your terminal provider.
2. Ask Claude to edit a file — hunks appear inline.
3. `ga` accept hunk · `gr` reject · `gA`/`gR` all · `]h`/`[h` navigate.
4. Visual select + `:'<,'>ClideSend` — at-mention the range in Claude's context.

## Configuration (defaults)

```lua
require("clide").setup({
  autostart = false,
  log_level = "info",
  terminal = {
    provider = "auto",      -- auto | native | snacks | tmux | none
    cmd = "claude",
    split_side = "right",   -- right | left
    split_width = 0.35,
  },
  review = {
    inline = true,          -- false = classic side-by-side diff tab
    keymaps = {
      accept = "ga", reject = "gr",
      accept_all = "gA", reject_all = "gR",
      next_hunk = "]h", prev_hunk = "[h",
    },
  },
})
```

## Statusline

```lua
-- lualine
sections = { lualine_x = { require("clide.status").lualine } }
```

Run `:ClideInstallHooks` once per project to enable working/waiting/idle states.

## Commands

| Command | Action |
|---|---|
| `:ClideStart` / `:ClideStop` | Start/stop server + claude |
| `:ClideToggle` | Toggle the claude terminal |
| `:'<,'>ClideSend` | At-mention the selected range |
| `:ClideReviewTab` | Reopen current review as a diff tab |
| `:ClideInstallHooks` | Install statusline hooks into `.claude/settings.local.json` |
| `:ClideLog` | Show the log ring buffer |
| `:checkhealth clide` | Diagnose setup |

## How it works

Neovim runs a WebSocket server on `127.0.0.1` (random port 10000-65535),
writes `~/.claude/ide/[port].lock` with a CSPRNG auth token, and launches
`claude` with `CLAUDE_CODE_SSE_PORT` + `ENABLE_IDE_INTEGRATION=true`. Claude
connects back and drives the editor over JSON-RPC 2.0 / MCP. See
[PROTOCOL.md](PROTOCOL.md) for the full reverse-engineered protocol reference.

WebSocket internals informed by MIT-licensed
[coder/claudecode.nvim](https://github.com/coder/claudecode.nvim).

## License

MIT
