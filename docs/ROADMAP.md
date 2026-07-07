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
- **No "Claude disconnected" notify** on `:ClideStop` (T16 quirk).
- **README security note** — executeCode = full nvim eval, no sandbox in
  clide; Claude Code permission prompt is the only gate, and executeCode
  bypasses the review flow. One honest paragraph.

## v2 ideas (from tester notes)

- **At-mention bundles diagnostics** for selected range:
  `vim.diagnostic.get(bufnr, {lnum=start, end_lnum=end})` — text + file +
  inline errors in one push.
- **Statusline promotion** — `require("clide.status").lualine()` works
  (spinner/waiting/idle, review X/Y); document and market it.
- **Buffer-centric interaction** — selection sync works for unsaved/scratch
  buffers now; broader design direction: treat active buffer, not file path,
  as the unit Claude interacts with.
- **Lean into executeCode** — tester verdict: 10 of 12 protocol tools never
  surface on CLI host; either make executeCode safer (optional sandbox) or
  push upstream for full tool parity. Consider filing issue on
  anthropics/claude-code for the mcp__ide__* CLI gap.

## Known non-issues

- CLI host exposes only executeCode + getDiagnostics of the 17 registered
  tools — Claude Code CLI limitation, not clide. SessionStart hook fixed to
  advertise only those two (`c6e215e`).
- Diagnostics push once per reconnect, query-only otherwise — by design.
- SSE transport dropped at `b511f6c`; WS-only.
