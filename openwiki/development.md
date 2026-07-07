# clide.nvim: Development

## Branch Discipline

```bash
git switch -c feat/<name>   # feature
git switch -c fix/<name>    # bugfix
git switch -c chore/<name>  # lint, docs, CI
```

- Never commit directly to `main`.
- Branch, test, commit, merge.
- For parallel work: `git worktree add ../clide-<feature> feat/<name>`
- Commits must be conventional: `feat:`, `fix:`, `test:`, `docs:`, `chore:`

Source: `/docs/WORKFLOW.md` lines 4-16.

## Development Cycle

```
edit → stylua → luacheck → make test → commit
```

Source: `/docs/WORKFLOW.md` lines 19-20.

### Make targets

```bash
make test      # plenary busted suite, headless nvim
make lint      # stylua --check lua/ tests/ + luacheck lua/ tests/
```

Source: `/Makefile` and `/CLAUDE.md` lines 38-41.

### Test discipline

- Never pipe `make test` through `head`/`tail`/`grep` repeatedly. Run once and capture:
  ```bash
  make test > /tmp/test.log 2>&1; echo "exit=$?"
  ```
- Quiet by design: one `TOTAL:` line on green, full log on failure.
- Single-spec rerun:
  ```bash
  nvim --headless -u tests/minimal_init.lua \
    -c "PlenaryBustedDirectory tests/<name>_spec.lua {minimal_init='tests/minimal_init.lua'}"
  ```
- Pass/fail signal:
  ```bash
  make test >/dev/null 2>&1 && echo PASS || echo FAIL
  ```
- Source: `/CLAUDE.local.md` "Running Tests" section.

### Lint discipline

- `make lint` mirrors CI: `stylua --check lua/ tests/` + `luacheck lua/ tests/`.
- Stylua config: spaces, indent_width=2, column_width=100. Source: `/stylua.toml`.
- Luacheck: custom config (source: `/.luacheckrc` — unsupported in read), known ignore on `frame.lua:143` (documented shim).
- Lua LSP config in `/.luarc.json`: `diagnostics.globals: ["vim"]`, test files also get `describe`, `it`, `assert`, etc.

## Pre-Release Checklist

Before tagging a new version:

1. `make test` green, `make lint` clean.
2. `:checkhealth clide` accurate.
3. CHANGELOG.md updated (unreleased → version + date).
4. README config block matches `lua/clide/config.lua` defaults.
5. `doc/clide.txt` in sync with README (modeline `noet`, all sections present).
6. `doc/tags` not committed (gitignored — plugin managers regenerate).
7. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`.

Source: `/docs/WORKFLOW.md` lines 29-38.

## Provider Roles (when using AI to build)

| Provider | Use for |
|----------|---------|
| Claude (Opus/Sonnet) | Architecture, security review, complex changes |
| Claude (Haiku) | File search, rename, formatting, trivial edits |
| DeepSeek / cheap | Boilerplate, research, mechanical refactors |

**Rule**: Opus main thread = orchestrator. Delegate implementation to Sonnet/Haiku subagents.

Source: `/docs/WORKFLOW.md` lines 41-49.

## Token Budget (AI-assisted development)

- `make test` headless ≈ 3000 tokens per run. Run once, cache output.
- Don't re-read hot files (`ws.lua`, `tools/init.lua`). Read once, batch edit.
- Use codegraph/codebase-memory before grep/Read for code understanding.
- Append to progress files with `printf '...' >>`, not repeated Edit calls.

Source: `/docs/WORKFLOW.md` lines 51-57.

## Hard Constraints

From `/CLAUDE.md` lines 11-21 (applies to all contributors, not just AI):

- **Pure Lua only.** No Node.js, no Rust. Runtime deps: Neovim >= 0.10, `claude` CLI, `plenary.nvim`.
- **Never wrap event-driven server callbacks in `plenary.async`** — use sync patterns only.
- **Both WS server binds `127.0.0.1` only** — never `0.0.0.0`.
- **Auth token**: `vim.uv.random(16)` hex — never `math.random`. Never log the token.
- **Protocol values are exact**: `protocolVersion = "2025-03-26"`, `ideName = "Neovim"`, `transport = "ws"`, openDiff responses `FILE_SAVED`/`DIFF_REJECTED`.
- **All uv/socket callbacks wrapped in `pcall`** — never crash Neovim on malformed input.
- **MCP config writes to `.mcp.json`**; auto-approve in `.claude/settings.local.json`. Both files gitignored (dynamic ports).

## Scope Boundaries

From `/docs/SCOPE.md`:

**In scope**: Claude Code IDE protocol, WebSocket MCP, inline review, multi-session, terminal providers, follow mode, health checks, vimdoc.

**Out of scope**:
- Generic agent platform / LLM abstraction
- Multi-provider routing inside plugin
- Chat UI inside Neovim
- Tool discovery beyond Claude Code IDE protocol `tools/list`
- Plugin manager (defer to lazy.nvim / packer / vim-plug)
- Node.js / Rust dependency

## Roadmap

| Version | Focus | Status |
|---------|-------|--------|
| v0.1 | WS server + 12 tools | Released 2026-07-02 |
| v0.2 | SSE MCP server + 17 tools | Released 2026-07-03 |
| v0.3 | Multi-session, follow mode, health | Released 2026-07-04→07 |
| v0.4 | Polish for public release | Done |
| v0.5 | API stability, CONFIG.md | Done |
| v1.0 | Tag, LuaRocks publish | Pre-release checklist complete, tag pending |

Source: `/docs/SCOPE.md` lines 45-82.

## CI

GitHub Actions at `/.github/workflows/ci.yml`:

- **test** job: ubuntu-latest, matrix on `[stable, nightly]` Neovim. Uses `rhysd/action-setup-vim`, caches plenary in `.deps/`, runs `make test`.
- **lint** job: stylua `--check lua/ tests/`, luacheck `lua/ tests/`.
- Triggers: push to `main`/`master` + pull requests.
