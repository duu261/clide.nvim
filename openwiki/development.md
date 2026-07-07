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


## Development Cycle

```
edit → stylua → luacheck → make test → commit
```


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

## Verification Gates

```bash
make test > /tmp/test.log 2>&1; echo "exit=$?"
# On green:
make lint
git commit
```

Don't `&&`-chain test→lint→commit. Red test gate still commits if chained.

## Pre-Release Checklist

Before tagging a new version:

1. `make test` green, `make lint` clean.
2. `:checkhealth clide` accurate.
3. CHANGELOG.md updated (unreleased → version + date).
4. README config block matches `lua/clide/config.lua` defaults.
5. `doc/clide.txt` in sync with README (modeline `noet`, all sections present).
6. `doc/tags` not committed (gitignored — plugin managers regenerate).
7. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`.


## Provider Roles (when using AI to build)

| Provider | Use for |
|----------|---------|
| Claude (Opus/Sonnet) | Architecture, security review, complex changes |
| Claude (Haiku) | File search, rename, formatting, trivial edits |
| DeepSeek / cheap | Boilerplate, research, mechanical refactors |

**Rule**: Opus main thread = orchestrator. Delegate implementation to Sonnet/Haiku subagents.


## Token Budget (AI-assisted development)

- `make test` headless ≈ 3000 tokens per run. Run once, cache output.
- Don't re-read hot files (`ws.lua`, `tools/init.lua`). Read once, batch edit.
- Use codegraph/codebase-memory before grep/Read for code understanding.
- Append to progress files with `printf '...' >>`, not repeated Edit calls.

## Bootstrap / Dry-Run / Doctor

```bash
# Is clide running?
ss -tlnp | grep nvim

# Auth token (never log this)
cat ~/.claude/ide/*.lock | jq .authToken
```

## Neovim Plugin Lifecycle

clide.nvim must feel like a Neovim plugin, not a server strapped to Neovim:

1. **Lazy-load**: `plugin/clide.lua` defers `require("clide")` until `:ClideStart`.
2. **Setup idempotent**: calling `setup()` twice = no-op.
3. **Teardown clean**: `:ClideStop` closes WS, timers, lock files.
4. **Health check**: `:checkhealth clide` verifies `claude` CLI, plenary, tmux (if used), port availability.
5. **Config get() pattern**: always read through `config.get()`, never access module state directly.

## Hard Constraints

See [CLAUDE.md](../CLAUDE.md#hard-constraints) for the canonical list. Applies to all contributors, not just AI.

## Scope Boundaries

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

Source: `/docs/ROADMAP.md`.

## CI

GitHub Actions at `/.github/workflows/ci.yml`:

- **test** job: ubuntu-latest, matrix on `[stable, nightly]` Neovim. Uses `rhysd/action-setup-vim`, caches plenary in `.deps/`, runs `make test`.
- **lint** job: stylua `--check lua/ tests/`, luacheck `lua/ tests/`.
- Triggers: push to `main`/`master` + pull requests.

## Debugging lessons (2026-07-08 selection fix)

Distilled from the handoff confusion diary of the session behind `dbea330`:

- Notification "doesn't arrive": trace the full sender-to-receiver path
  (see architecture.md "Notification data flow") before editing sender
  logic. 80% of that session was spent on the wrong half.
- Test the EVENT before coding the handler. `FocusLost` does NOT fire on
  tmux pane switches — only `ModeChanged`/`CursorMoved` do.
- "State X is nil" means never-set OR set-then-cleared. Check `M.stop()`
  and the `M.state = {}` wipe before concluding "no client connected".
- Check `git log` for removed features before chasing dead config
  (`b511f6c` removed the SSE transport; env var name still says SSE).
- Lua closures capture locals by reference (upvalues):
  `local x = f({ ...closures using x... })` works even though `x` is nil at
  closure creation. luacheck's "accessing undefined variable" there is a
  false positive.

## Live debugging via clide itself

When connected to the running nvim (mcp__ide__ tools), debug the plugin
in-process instead of reasoning from source:

- `executeCode` can inspect live state (`require("clide").state`,
  `require("clide.selection")._last_sent`) and install probe autocmds.
- Hot-patch: inject the candidate fix as a timer/autocmd via `executeCode`,
  have the user reproduce, verify, THEN write it into the module. Avoids a
  restart cycle per iteration (restart also drops the Claude connection).
- Never trust that an autocmd event fires on this machine — probe it first.
  Verified 2026-07-08: ModeChanged and FocusLost do NOT reach autocmds in
  the user's tmux/terminal setup; CursorMoved does. Hence the 200ms visual
  poll in selection.lua.
