This file has been intentionally emptied — the plan is complete and the wiki has been generated.

4. **openwiki/tools-and-protocol.md** — The 17 MCP tools, protocol layers (frame → handshake → RPC → tool dispatch), lock file discovery protocol, auth, known CLI host gaps.

## Source evidence per page

### quickstart.md
- /README.md: full feature list, requirements, install, config, keymaps
- /lua/clide/config.lua: setup defaults
- /lua/clide/commands.lua: user commands
- /lua/clide/init.lua: startup lifecycle
- /doc/clide.txt: vimdoc
- /CONFIG.md: every setup() key
- /STATE.md: v0.3.2 status, test counts

### architecture.md
- /plugin/clide.lua: entry point (guard, commands)
- /lua/clide/init.lua: setup(), start(), stop(), state management
- /lua/clide/server/ws.lua: TCP server, connection lifecycle
- /lua/clide/server/frame.lua: RFC 6455 frame codec
- /lua/clide/server/handshake.lua: WS upgrade, auth token validation
- /lua/clide/server/rpc.lua: JSON-RPC 2.0 dispatcher (initialize, tools/list, tools/call)
- /lua/clide/tools/init.lua: tool registry, DEFER sentinel
- /lua/clide/lockfile.lua: lock file discovery protocol
- /lua/clide/config.lua: config model
- /lua/clide/review/engine.lua: hunk computation, open, resolve
- /lua/clide/review/queue.lua: review queue, navigation
- /lua/clide/review/render.lua: extmark rendering, keymaps
- /lua/clide/terminal/init.lua: provider dispatch
- /lua/clide/selection.lua: selection sync (WS selection_changed)
- /lua/clide/follow.lua: follow mode
- /lua/clide/status.lua: statusline, hook integration
- /lua/clide/util/log.lua, fs.lua, sha1.lua, eol.lua: utility modules
- /lua/clide/health.lua: checkhealth
- /PROTOCOL.md: protocol reverse-engineering doc
- /STATE.md: transport table, tool counts

### development.md
- /docs/WORKFLOW.md: dev cycle, branch discipline, provider roles, token budget, pre-release checklist
- /CLAUDE.md: hard constraints, workflow, test patterns, agent skills
- /CLAUDE.local.md: headroom-learned patterns
- /Makefile: test, lint targets
- /stylua.toml: formatting config
- /docs/SCOPE.md: done definition, roadmap, v1.0 checklist
- /CHANGELOG.md: version history

### tools-and-protocol.md
- /lua/clide/tools/init.lua: registry, list(), call()
- /lua/clide/tools/open_file.lua, open_diff.lua, vim_edit.lua, etc.: individual tools
- /lua/clide/server/frame.lua: RFC 6455 codec
- /lua/clide/server/handshake.lua: auth handshake
- /lua/clide/server/rpc.lua: JSON-RPC dispatch
- /lua/clide/lockfile.lua: lock file format
- /PROTOCOL.md: full protocol spec
- /docs/human_test_plan_v1.md: CLI host tool gap analysis
- /docs/test-results-v1.md: test results confirming tool gap

## Questions remaining
- No git history available (will note this)
- CI: only GitHub Actions workflow is visible (no Docker, no deployment scripts)
- No LuaRocks publish yet (listed as pre-v1.0)
