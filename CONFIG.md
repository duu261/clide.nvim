
Every `setup()` option with type, default, and description.

```lua
require("clide").setup({
  -- ... your overrides here
})
```

All keys optional. `setup()` never required — defaults apply without it.

## Top-level

### `autostart`

```lua
autostart = false  -- bool
```

Start server + launch Claude when Neovim loads. Off by default — most users
prefer `:ClideStart` on demand.

### `sse_port`

```lua
sse_port = 42069  -- number
```

Port for the SSE MCP server. Written to `.mcp.json` so MCP clients discover
it. Change if `42069` conflicts with another service.

### `follow`

```lua
follow = false  -- bool
```

Auto-scroll the Claude terminal as output arrives.

### `auto_install_mcp`

```lua
auto_install_mcp = true  -- bool
```

Run `:ClideInstallMCP` automatically on `:ClideStart`. Writes `.mcp.json`
and `.claude/settings.local.json` (auto-approve). Set `false` if you manage
MCP config manually.

### `log_level`

```lua
log_level = "info"  -- "debug" | "info" | "warn" | "error"
```

Minimum severity for the ring-buffer log (`:ClideLog`). Debug includes
protocol-level messages (frame send/recv, RPC dispatch).

## `terminal`

```lua
terminal = {
  provider = "auto",       -- "auto" | "native" | "tmux" | "toggleterm" | "snacks" | "none"
  cmd = "claude",          -- string — CLI command to launch
  split_side = "right",    -- "right" | "left" | "top" | "bottom" (native/toggleterm only)
  split_width = 0.35,      -- number — fraction of editor width (native/toggleterm only)
}
```

### `terminal.provider`

How Claude's terminal is opened:

| Value | Behavior |
|-------|----------|
| `"auto"` | Resolves: tmux (inside `$TMUX`) → snacks (if installed) → native `:terminal` |
| `"tmux"` | New tmux pane in current window. Survives Neovim restart. Requires `$TMUX`. |
| `"toggleterm"` | toggleterm.nvim float/terminal. Requires toggleterm.nvim installed. |
| `"snacks"` | snacks.nvim terminal. Requires snacks.nvim installed. |
| `"native"` | Built-in `:terminal` split. No dependencies. |
| `"none"` | Prints `CLAUDE_CODE_SSE_PORT` and `ENABLE_IDE_INTEGRATION` env vars. Run Claude yourself. |

### `terminal.cmd`

Shell command to launch. Default `"claude"` — change to a full path or
wrapped script.

### `terminal.split_side`

Side for native and toggleterm splits. Tmux uses its own layout; snacks
uses its own config.

### `terminal.split_width`

Fraction (0.0–1.0) of editor width for the terminal split. 0.35 = 35%.

## `review`

```lua
review = {
  inline = true,           -- bool
  hint_line = true,        -- bool
  keymaps = {
    accept = "<Leader>ma",
    reject = "<Leader>mr",
    accept_all = "<Leader>mA",
    reject_all = "<Leader>mR",
    next_hunk = "]h",
    prev_hunk = "[h",
  },
}
```

### `review.inline`

`true` (default): hunks render as extmark-anchored virtual text in your
real buffer. `false`: classic side-by-side diff tab with `:ClideReviewTab`.

### `review.hint_line`

Show a hint line (`-- Accept (<Leader>ma) / Reject (<Leader>mr)`) above
each hunk. Buffer-local; set `false` to hide.

### `review.keymaps`

Buffer-local keymaps active while pending hunks exist:

| Key | Action |
|-----|--------|
| `accept` | Accept hunk under/near cursor |
| `reject` | Reject hunk under/near cursor |
| `accept_all` | Accept all hunks in buffer |
| `reject_all` | Reject all hunks in buffer |
| `next_hunk` | Jump to next pending hunk (crosses files) |
| `prev_hunk` | Jump to previous pending hunk |

## `cmd_keymaps`

```lua
cmd_keymaps = {
  toggle = "<Leader>mt",
  start = "<Leader>ms",
  stop = "<Leader>mq",
  log = "<Leader>ml",
  send = "<Leader>me",      -- visual mode: send selection to Claude
  send_toggle = "<Leader>mz", -- visual mode: send + toggle terminal
}
```

Global keymaps (normal mode unless noted):

| Key | Command |
|-----|---------|
| `toggle` | `:ClideToggle` |
| `start` | `:ClideStart` |
| `stop` | `:ClideStop` |
| `log` | `:ClideLog` |
| `send` | `:'<,'>ClideSend` (visual mode) |
| `send_toggle` | `:'<,'>ClideSend` + `:ClideToggle` (visual mode) |

Set any key to `false` to disable that mapping:

```lua
cmd_keymaps = {
  send_toggle = false,  -- disable visual send+toggle
}
```