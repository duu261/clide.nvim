# clide.nvim — Workflow

How to work on clide.nvim: branches, providers, token budget, safe dev cycle.

## Branch discipline

```
git switch -c feat/<name>   # feature
git switch -c fix/<name>    # bugfix
git switch -c chore/<name>  # lint, docs, CI
```

- Never commit directly to `main`.
- Branch, test, commit, merge.
- For parallel work: `git worktree add ../clide-<feature> feat/<name>`

## Development cycle

```
edit → stylua → luacheck → make test → commit
```

- `make test` once, redirect to file, grep that file. Never re-run just to see
  different sections.
- `make lint` mirrors CI (stylua + luacheck).
- Commits: conventional (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).

## Pre-release

Before tagging:

1. `make test` green, `make lint` clean
2. `:checkhealth clide` accurate
3. CHANGELOG.md updated (unreleased → version + date)
4. README config block matches `lua/clide/config.lua` defaults
5. `doc/clide.txt` in sync with README (modeline `noet`, all sections present)
6. `doc/tags` not committed (gitignored)
7. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`

## Provider roles

| Provider | Use for |
|----------|---------|
| Claude (Opus/Sonnet) | Architecture, security review, complex changes |
| Claude (Haiku) | File search, rename, formatting, trivial edits |
| DeepSeek / cheap | Boilerplate, research, mechanical refactors |

**Rule**: Opus main thread = orchestrator. Delegate implementation to Sonnet/Haiku
subagents. Never hand-count or do large impl inline.

## Token budget

- `make test` headless = ~3000 tokens per run. Run once, cache output.
- Don't re-read hot files (ws.lua, tools/init.lua). Read once, edit
  batch.
- Use codegraph/codebase-memory before grep/Read for code understanding.
- Append to progress files with `printf '...' >>`, not repeated Edit calls.

## Bootstrap / dry-run / doctor

```bash
# Is clide running?
ss -tlnp | grep nvim

# Auth token (never log this)
cat ~/.claude/ide/*.lock | jq .authToken
```

## Neovim plugin lifecycle alignment

clide.nvim must feel like a Neovim plugin, not a server strapped to Neovim:

1. **Lazy-load**: `plugin/clide.lua` defers `require("clide")` until `:ClideStart`.
2. **Setup idempotent**: calling `setup()` twice = no-op.
3. **Teardown clean**: `:ClideStop` closes WS, timers, lock files.
4. **Health check**: `:checkhealth clide` verifies `claude` CLI, plenary, tmux (if used), port availability.
5. **Config get() pattern**: always read through `config.get()`, never access module state directly.

## Verification gates

```bash
make test > /tmp/test.log 2>&1; echo "exit=$?"
# On green:
make lint
git commit
```

Don't `&&`-chain test→lint→commit. Red test gate still commits if chained.
