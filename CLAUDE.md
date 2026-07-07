# clide.nvim

Pure-Lua Neovim plugin prio on Claude and tmux, implementing the Claude Code IDE protocol (WebSocket
MCP) with inline per-hunk review. Protocol reference: PROTOCOL.md.

**Session start: read openwiki/quickstart.md** — project overview, then follow
links to architecture/development notes. Roadmap lives in `docs/ROADMAP.md`.

## Hard constraints

- Pure Lua only. No Node, no Rust. Runtime deps: Neovim >= 0.10, the `claude` CLI, and
  `nvim-lua/plenary.nvim` (amended 2026-07-03; use plenary where it makes code shorter —
  never wrap event-driven server callbacks in `plenary.async`).
- Both WS server binds `127.0.0.1` only — never `0.0.0.0`.
- Auth token: `vim.uv.random(16)` hex — never `math.random`. Never log the token.
- Protocol values are exact: `protocolVersion = "2025-03-26"`, `ideName = "Neovim"`,
  `transport = "ws"`, openDiff responses `FILE_SAVED` / `DIFF_REJECTED`.
- All uv/socket callbacks wrapped in `pcall`; never crash Neovim on malformed input.
- Primary workflow is Claude in a tmux pane beside nvim. Never trust autocmd
  events for tmux-facing features: ModeChanged/FocusLost delivery is
  terminal-dependent (proven dead on the dev machine) — probe the event live
  first, or poll (see selection.lua). Pushed context costs Claude tokens:
  anything auto-pushed (selections, diagnostics) must dedup and filter.
- No `.mcp.json` — SSE/MCP transport removed in `b511f6c`. Claude discovers the
  server via lockfile + `CLAUDE_CODE_SSE_PORT` env var (name is CLI-mandated;
  transport is WS). Statusline hooks write `.claude/settings.local.json`
  (gitignored). Notification data flow: openwiki/architecture.md.

## Workflow

- New features: run the nvim-plugin-maker skill flow first — brainstorm, then
  scope in `docs/ROADMAP.md`, then TDD for anything risky (evented/async/IO/
  config/command). Keep `docs/ROADMAP.md` current as items land.
- Tests: cover the risky surface — protocol (frame/handshake/rpc/ws), auth, and
  review hunk-diff. Test-first there when it earns its cost; skip tests for trivial
  wrappers. No strict red-green ceremony. Always run `make test` before a commit
  (quiet: one `TOTAL:` line on green, full log on failure).
- Conventional commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
- Format with stylua, lint with luacheck (configs in repo root).
- Do NOT commit `docs/superpowers/` — gitignored, stays local.

## Commands

```bash
make test      # plenary busted suite, headless nvim
make lint      # stylua --check lua/ tests/ + luacheck lua/ tests/
```

## Layout

- `lua/clide/server/` — WS transport (frame, handshake, ws, rpc)
- `lua/clide/tools/` — the 17 MCP protocol tools (registry in init.lua)
- `lua/clide/review/` — inline hunk review (engine, render, queue)
- `lua/clide/terminal/` — providers: native, tmux, toggleterm, snacks, none
- `lua/clide/util/` — log, fs helpers
- `tests/` — plenary specs, `tests/minimal_init.lua` bootstraps
- `openwiki/` — overview, architecture, development
- `docs/ROADMAP.md` — bugs, gaps, v2 ideas
- `docs/WORKFLOW.md` — dev cycle, providers, token budget, pre-release
- `CHANGELOG.md` — Keep a Changelog, semver
- `CONFIG.md` — every `setup()` key documented
- `doc/clide.txt` — vimdoc (`:help clide`), modeline `noet`
- Implementation plan: `docs/superpowers/plans/2026-07-02-clide-nvim/` (local only)

## Release

- Pre-release checklist in `docs/WORKFLOW.md`.
- Artifacts: README (marketing), CHANGELOG.md (Keep a Changelog), CONFIG.md
  (every `setup()` key documented), `doc/clide.txt` (vimdoc, self-contained
  for `:help clide` — modeline `noet`, all sections, no "see README" gaps).
- `doc/tags` is gitignored — plugin managers regenerate on install.
- CI: stable+nightly matrix, stylua + luacheck gate (`.github/workflows/ci.yml`).
- Version: semver tags, conventional commits for changelog generation.
- `make test` green + `make lint` clean before tagging.

## Agent skills

### Issue tracker

GitHub Issues via `gh` CLI. External PRs not triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels matching triage roles by name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout. See `docs/agents/domain.md`.

## OpenWiki

This repository has documentation located in the /openwiki directory.

Start here:

- [OpenWiki quickstart](openwiki/quickstart.md)

OpenWiki includes repository overview, architecture notes, workflows, domain concepts, operations, integrations, testing guidance, and source maps.

When working in this repository, read the OpenWiki quickstart first, then follow its links to the relevant architecture, workflow, domain, operation, and testing notes.
