# clide.nvim human test results — 2026-07-06 (updated 2026-07-07)

> **SSE transport dropped at `b511f6c` (2026-07-06).** H6/H10/H11 results
> below recorded under old SSE+headless-child architecture. Detached server gap
> (headless nvim running UI tools) no longer applies — all tools now run in
> interactive nvim via single WS transport. H6, H10, H11 need retest.

## Gating tests (H1–H14)

| Test | Status | Notes |
|------|--------|-------|
| H1 — Health check | PASS | `:checkhealth clide` OK |
| H2 — ClideStart lifecycle | PASS | WS server + terminal launch + Claude auto-connect all work |
| H3 — MCP child process | PASS | Headless nvim on 42069, `.mcp.json` written, `/mcp` lists tools. `pgrep -af 'nvim.*headless'` — "nothing show term stay wait" (pgrep output didn't appear in terminal pane, but `ss` confirmed child was listening) |
| H4 — Selection sync | MIXED | `selection_changed` arrives via WS system reminder (works). `getLatestSelection` MCP tool returns "No selection available" — timing/cache gap. "only work in ws not mcp". "is this expect correct? claude often try clide mcp to check?" — user notes Claude tries MCP tool first, missing the WS-pushed selection |
| H5 — ClideSend at-mention / is this even needed when i can select hover then switch to chat | PASS | Visual-select + `<Leader>me` sends at-mention to Claude. "idea lead mZ auto send" — `<Leader>mZ` should auto-send without separate confirm step |
| H6 — openFile | NEEDS RETEST | ~~"nope not work is this" — `openFile` runs in headless nvim (PID 1158812), not interactive nvim (PID 1158596). File opens in headless — invisible to user.~~ OBSOLETE: SSE/headless child dropped at `b511f6c`. `openFile` now runs in interactive nvim via WS. Retest with exact-match text anchor (health.lua has "claude binary found" not "claude binary check"). AI awareness gap remains — see H6 priming problem. |
| H7 — Inline review (mixed accept/reject) | MIXED | Core flow works: `]h`/`[h` jump, `<Leader>ma`/`mr` resolve. Bugs: (1) virtual text clipped at first/last line of file — top/bottom hunks don't render extmark. (2) Quickfix list stays open after review done — "one note here after done the qf list still there? i mean the windows well still can close myself but if auto maybe niche". Testing friction: Claude kept misreading line ranges — "why u not reading correct line i send?", "hmm buffer dif?", "no just read in". Buffer state question: "when test notice issues what we do with buffer state?" |
| H8 — Bulk keys (accept all / reject all) | PASS | `<Leader>mA`/`<Leader>mR` work |
| H9 — ClideReviewTab escape hatch | MIXED | Fallback to side-by-side diff tab works. "ugh cant acpt one hunk in tab?" — can't partially accept one hunk then send rest to tab. Guard works: warns "partially resolved" if any hunks already resolved |
| H10 — Dirty buffer + save flow | NEEDS RETEST | ~~Same detached-server gap as H6. `checkDocumentDirty`/`saveDocument` query headless nvim, not interactive.~~ OBSOLETE: SSE/headless dropped. Both tools now run in interactive nvim via WS. Retest. |
| H11 — Diagnostics | NEEDS RETEST | ~~LSP diagnostics pushed via Claude Code IDE hook, not clide/MCP. Only fires for recognized project files.~~ SSE dropped, diagnostics path may differ with WS-only transport. Retest. |
| H12 — Second client | MIXED | Second Claude session connects via env vars. "select visual mode then switch to claude can even send buffer text" — at-mention works across clients. Bug: single-line visual selection not picked up — need to move cursor up/down to trigger. `h6 fail alrdy` (H6 same gap with second client) |
| H13 — Restart + child reattach | PASS | `:ClideRestart`: new WS port, old lock removed, 1 headless child (no duplicate spawn), `ensure_running` reattached. SSE port 42069 stayed on same headless PID. MCP reconnects without config edit. All expectations met. |
| H14 — Clean shutdown | NOT TESTED | "only qa kill all not stop" — tested via `:qa` (VimLeavePre). `:ClideStop` path not verified. "is toggle auto start?" — user asks if toggle triggers autostart when server isn't running |

## Key issues

1. **Detached server gap** (H6, H10) — ~~headless nvim runs MCP tools. UI tools (`openFile`, `checkDocumentDirty`, `saveDocument`) operate on headless, not interactive nvim. Need proxy or direct-to-interactive path.~~ RESOLVED: SSE/headless child dropped at `b511f6c`. All tools now run in interactive nvim via single WS transport. H6/H10 need retest to confirm.
2. **getLatestSelection cache gap** (H4) — selection arrives via WS push, but MCP tool returns stale/null. Timing issue. Claude tries MCP tool before checking system reminder.
3. **Virtual text clip at boundaries** (H7) — first/last line hunks don't render extmark hints.
4. **Single-line selection bug** (H12) — visual-selecting 1 line doesn't trigger `selection_changed`. Need move cursor to trigger.
5. **Diagnostics trigger gap** (H11) — ~~IDE hook only pushes diagnostics for recognized project files. Arbitrary buffers skipped.~~ SSE dropped, diagnostics path may differ. Retest.

## Auxiliary notes

- `:ClideLog` — "btw this log doesnt store nothing much and all fkin debug u ask me for read noti good job" — stores little, mostly debug noise from notifications. "should make this toggle or? btw why can write in it even tho cant save is maybe is nvim feat alrdy" — buffer is modifiable but not saveable (nvim scratch buffer behavior)
- `:ClideToggle` — "no clue still in tmux" — toggle behavior in tmux unclear, `<Leader>mt` / `:ClideToggle` hides/shows pane but doesn't restart. While server runs, toggle is safe.
- `:ClideInstallHooks` — "yeah seems work but maybe can enhace more" — statusline reflects Claude state during reviews
- SSE failure drill — ~~nc occupying 42069: "btw i got this from nvim qa is this correct?" — `nc -l 127.0.0.1 42069` captured Claude Code GET /sse (User-Agent: claude-code/2.1.201, mcp-protocol-version: 2025-03-26). Got "timeout waiting for MCP server" notify. WS flow (H2, H4–H11) continues. Works as expected.~~ OBSOLETE: SSE/port 42069 removed at `b511f6c`. WS is sole transport.
- "btw is this ai running lua cmd here?" — user noticed `ide - executeCode (MCP)` calls in notifications panel and questioned whether AI was executing Lua commands in nvim