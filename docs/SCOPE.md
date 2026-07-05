# clide.nvim — Scope & Roadmap

## What is it

Neovim plugin that lets Claude Code control Neovim. Claude opens files, edits
buffers, shows diffs, runs searches — through Neovim. Neovim is the IDE, Claude
is the driver. Not a generic multi-agent platform. Not a Claude wrapper that
happens to open Neovim.

## Core user flows

1. **Claude Code IDE session** — user launches `claude` CLI with
   `CLAUDE_CODE_SSE_PORT` set. Claude connects to clide.nvim via WebSocket, Auth
   token from lock file. Claude calls tools (`openFile`, `vim_edit`, `openDiff`).
   User reviews hunks inline in Neovim.

2. **MCP headless session** — any MCP client reads `.mcp.json`, connects to
   clide.nvim via SSE + Streamable HTTP (`POST /sse`). Same tools, same Neovim
   instance.

## Transport story (why two)

| Transport | When | Why |
|-----------|------|-----|
| WebSocket | Interactive `claude` CLI sessions | Claude Code IDE protocol — lock file discovery, auth token, bidirectional RPC |
| SSE + Streamable HTTP | MCP clients (`.mcp.json`) | Standard MCP transport — any MCP client can discover tools, headless or long-running |

Two transports because two different protocols discovered clide.nvim. WS is the
original Claude Code IDE path. SSE is the MCP standard path. Both call the same
tool implementations.

## What counts as done (v1.0)

- [x] WebSocket server + lock file discovery
- [x] JSON-RPC 2.0 request/response + notifications
- [x] All 12 protocol tools implemented (openFile → executeCode)
- [x] SSE server + Streamable HTTP POST /sse
- [x] Inline per-hunk review (openDiff blocking flow)
- [x] Multi-client: multiple `claude` processes connect to one Neovim
- [x] Terminal providers: tmux, native, snacks
- [x] Headless test suite (plenary/busted), luacheck clean, stylua clean
- [x] Dogfooded: session completed through own protocol
- [x] vimdoc (`doc/clide.txt`)
- [x] README with install/usage/lazy.nvim spec
- [x] CI: stable + nightly Neovim matrix, stylua + luacheck gate
- [x] Lazy-loading: `plugin/clide.lua` defers requires
- [x] `:checkhealth clide`
- [ ] LuaRocks package or GitHub release tag
- [x] CONFIG.md — all valid `setup()` options documented
- [ ] Multiple MCP sessions over Streamable HTTP (current: single-session)

## Out of scope

- Generic agent platform / LLM abstraction
- Multi-provider routing inside the plugin
- Chat UI inside Neovim
- Tool discovery beyond MCP standard tools/list
- Plugin manager (defer to lazy.nvim / packer / vim-plug)
- Node.js / Rust dependency — pure Lua only

## Plugin surface (what Neovim users see)

| Surface | Status |
|---------|--------|
| `require("clide").setup(opts)` | Done |
| `:ClideStart` / `:ClideStop` / `:ClideRestart` / `:ClideToggle` | Done |
| `:ClideStatus` | Done |
| `:checkhealth clide` | Done |
| lazy.nvim `opts` auto-setup | Done (setup() is idempotent) |
| vimdoc (`doc/clide.txt`) | Done |
| CHANGELOG.md | Done |
| CONFIG.md | Done |
| CI (stable + nightly) | Done |

## Roadmap

### v0.4 — polish for public release
- [x] health check
- [x] vimdoc
- [x] README rewrite (install, lazy.nvim spec, keybinds, config)
- [x] CI matrix (stable + nightly)

### v0.5 — API stability
- [x] `setup()` docs for every option (CONFIG.md)
- [x] CONFIG.md
- [ ] Multi-session SSE
- [ ] Rename snake_case tools to camelCase for MCP spec compliance?

### v1.0 — release
- [ ] Tag `v1.0.0`
- [ ] LuaRocks publish
- [ ] Link from claude-code.nvim comparison in README
