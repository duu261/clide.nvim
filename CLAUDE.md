# clide.nvim

Pure-Lua Neovim plugin implementing the Claude Code IDE protocol (WebSocket + SSE
MCP) with inline per-hunk review. Protocol reference: PROTOCOL.md.

**Session start: read STATE.md** — current version, tool list, test coverage, known gaps.

## Hard constraints

- Pure Lua only. No Node, no Rust. Runtime deps: Neovim >= 0.10, the `claude` CLI, and
  `nvim-lua/plenary.nvim` (amended 2026-07-03; use plenary where it makes code shorter —
  never wrap event-driven server callbacks in `plenary.async`).
- Both WS and SSE servers bind `127.0.0.1` only — never `0.0.0.0`.
- Auth token: `vim.uv.random(16)` hex — never `math.random`. Never log the token.
- Protocol values are exact: `protocolVersion = "2025-03-26"`, `ideName = "Neovim"`,
  `transport = "ws"`, openDiff responses `FILE_SAVED` / `DIFF_REJECTED`.
- All uv/socket callbacks wrapped in `pcall`; never crash Neovim on malformed input.
- SSE failure is non-fatal: WS continues, user gets one `vim.notify`.
- MCP config writes to `.mcp.json`; auto-approve in `.claude/settings.local.json`.
  Both files gitignored (dynamic ports).

## Workflow

- New features: run the nvim-plugin-maker skill flow first — brainstorm, then
  scope in `docs/SCOPE.md`, then TDD for anything risky (evented/async/IO/
  config/command). Keep `docs/SCOPE.md` current as items land; it's the
  source of truth for what's done vs. gap, not STATE.md prose.
- Tests: cover the risky surface — protocol (frame/handshake/rpc/ws/sse), auth, and
  review hunk-diff. Test-first there when it earns its cost; skip tests for trivial
  wrappers. No strict red-green ceremony. Always run `make test` before a commit
  (quiet: one `TOTAL:` line on green, full log on failure).
- Conventional commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
- Format with stylua, lint with luacheck (configs in repo root).
- Do NOT commit `docs/superpowers/` — gitignored, stays local.

## Commands

```bash
make test      # plenary busted suite, headless nvim
stylua lua/ tests/
luacheck lua/ tests/
```

## Layout

- `lua/clide/server/` — WS + SSE transports (frame, handshake, ws, sse, rpc)
- `lua/clide/tools/` — the 17 MCP protocol tools (registry in init.lua)
- `lua/clide/review/` — inline hunk review (engine, render, queue)
- `lua/clide/terminal/` — providers: native, tmux, snacks, none
- `tests/` — plenary specs, `tests/minimal_init.lua` bootstraps
- Implementation plan: `docs/superpowers/plans/2026-07-02-clide-nvim/` (local only)

## Agent skills

### Issue tracker

GitHub Issues via `gh` CLI. External PRs not triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels matching triage roles by name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout. See `docs/agents/domain.md`.

