# Roadmap

Post v0.3.2, after T1-T16 manual run (`docs/test-results-v1.md`,
plan + tester notes in `docs/human_test_plan_v1.md`).

## Bugs / gaps (next up)

- **Single-line visual selection lost** — select 1 line, Esc, selection not
  sent; needs cursor wiggle. `ModeChanged` autocmd misses the case (no
  `CursorMoved` during visual→normal); `build_from_marks` fallback at
  `selection.lua:79-81` races. Needs headless spec first (evented surface).
- **T9 `:ClideReviewTab`** — never manually tested. Verify escape hatch:
  inline review → classic diff tab, `ga`/`gr`/`:w`, partial-resolve guard.
- **T16 disconnect notify** — root-caused and fixed in `ca73a71`: ws.stop's
  vim.schedule'd on_disconnect raced `M.stop()`'s `M.state = {}` wipe; now
  called synchronously. Verify manually after next nvim restart.
- **Stop/start lifecycle untested** — headless spec: `:ClideStop` + `:ClideStart` must recreate `server.sessions` and keep `selection_changed`/`diagnostics_changed` flowing (regression class behind `dbea330`; sessions now on `server.sessions`, `M.stop()` wipes `M.state`).
- **README security note** — executeCode = full nvim eval, no sandbox in
  clide; Claude Code permission prompt is the only gate, and executeCode
  bypasses the review flow. One honest paragraph.

## v2 ideas (from tester notes + 2026-07-08 expansion)

### Context you push to Claude (the "buffer-centric" direction)
- **At-mention bundles diagnostics** for selected range:
  `vim.diagnostic.get(bufnr, {lnum=start, end_lnum=end})` — text + file +
  inline errors in one push.
- **Buffer as the unit, not file path** — selection sync already works for
  unsaved/scratch buffers; extend: at-mention any buffer (`:ClideSendBuffer`),
  send terminal buffer output, send fugitive/oil/help buffers. Nvim users
  always have a live buffer; file-path thinking is the VS Code inheritance.
- **Quickfix/loclist bridge, both directions** — `:ClideSendQf` pushes the
  qf list as context ("fix all these"); Claude results (grep hits, edit
  targets, diagnostics) land back in qf so nvim-native navigation works.
- **Picker integration** — Telescope/fzf-lua/snacks picker to multi-select
  files/buffers to at-mention in one shot, instead of one `<Leader>me` per
  spot.
- **Ask-about-hunk** — during review, keymap on a hunk sends hunk + "why
  this change?" back to Claude. Review becomes a conversation, not just
  accept/reject.

### Review flow
- **Edit-then-accept** — allow modifying a hunk in place before accepting;
  today it's binary accept/reject.
- **Review history** — ring of resolved reviews with `:ClideReviewLog`;
  answer "what did I accept 10 minutes ago" without git archaeology.
- **Follow + review fusion** — after follow jumps to an edited file, flash
  or highlight the changed region (extmark, clears on cursor move).

### Observability (neovim nerds love this stuff — tester quote)
- **Statusline promotion** — `require("clide.status").lualine()` works
  (spinner/waiting/idle, review X/Y); document it in README, add client
  count and last-tool segments, ship mini.statusline/heirline recipes.
- **executeCode audit trail** — log every executed snippet (first line +
  byte count) in :ClideLog. Transparency for the "only gate is the prompt"
  reality; nearly free given new logging layer.
- **Tool timing** — per-call duration in the log; makes token/latency
  debugging concrete.

### Protocol / platform
- **Diagnostics push on change** — today diagnostics push once per
  reconnect; wire `DiagnosticChanged` autocmd → push (debounced). Claude
  sees breakage as it edits, no polling.
- **Multi-client attribution** — T14 proved 2 clients connect; tag notify +
  log lines with client id so "which Claude did that" is answerable.
- **Upstream issue** — file one issue on anthropics/claude-code for the
  mcp__ide__* CLI gap (10 of 12 tools unreachable); link test-results-v1.
  Then stop waiting on it.
- **executeCode opt-out flag** — `setup({ execute_code = false })` for
  read-only integrations; documented escape hatch already exists (remove
  from registry), make it a config key. Off by default, no sandbox project.

### Distribution
- **Health check as marketing** — `:checkhealth clide` is already thorough;
  screenshot it in README.
- **Reddit/VN post** — draft exists in `docs/posts/` (local); statusline gif
  + Claude-ception demo are the hooks.

## Known non-issues

- CLI host exposes only executeCode + getDiagnostics of the 17 registered
  tools — Claude Code CLI limitation, not clide. SessionStart hook fixed to
  advertise only those two (`c6e215e`).
- Diagnostics push once per reconnect, query-only otherwise — by design.
- SSE transport dropped at `b511f6c`; WS-only.
