# Test results — TLDR

Date: 2026-07-07 (post WS-only change, run against current main)
Source: inline annotations in `docs/human_test_plan.md`. H3 removed (WS only, no MCP child).

## Gate table

| Test | Result | Notes |
|------|--------|-------|
| H1 — Health | PASS | |
| H2 — Start lifecycle | PASS | Notify order + "already running" guard OK |
| H4 — Selection sync | PASS (multi-line) / FAIL (single-line) | Single-line select still not sent; user leaning accept as known limit |
| H5 — ClideSend | PASS | Send works, but must switch to Claude pane + Enter to submit |
| H6 — openFile | PASS with workaround / UX FAIL | Claude did open the file — but via `mcp__ide__executeCode` Lua, not an openFile tool. Burned tokens figuring out it was even connected |
| H7 — Review mixed accept/reject | PASS core / render issue | `]h`/`[h`, per-hunk accept/reject, qf list work. First/last-line hunks: virtual text clipped. Claude edits 1-by-1, multi-hunk hard to trigger |
| H8 — Bulk keys | PASS | |
| H9 — ReviewTab escape hatch | PARTIAL | Guard works. Claude struggled to make a 2-hunk edit. **Claude can edit buffer via executeCode without review/permission — bypasses openDiff entirely** |
| H10 — Dirty buffer + save | PASS (clunky) | Works via executeCode, but each step = extra reasoning + MCP call. "Is this intended?" |
| H11 — Diagnostics | PASS (expensive) | Correct results, huge raw dump per call, token-heavy |
| H12 — Second client | PASS | Connect/disconnect clean. Same H6 tool-discovery confusion on client 2 |
| H13 — Restart | NO RESULT RECORDED | Open question: does restart also restart claude? |
| H14 — Clean shutdown | NO RESULT RECORDED | |

## Key issues (ranked)

1. **executeCode bypasses review** (H9) — IDE Claude modifies buffers with raw Lua, no openDiff, no accept/reject, no permission. Review flow only guards the openDiff path.
2. **Tool discovery / identity confusion** (H6, H10, H12) — Claude doesn't know it's connected to nvim or what it can do. Every session re-derives "how do I open a file" from scratch; inconsistent between sessions. openFile is a protocol tool the CLI calls, but IDE-connected Claude only sees `executeCode` + `getDiagnostics`.
3. **Virtual text clipped at file boundaries** (H7) — first/last line hunks lose hint line. Needs different render strategy.
4. **Single-line selection not sent** (H4) — timing gap; candidate: accept as limitation.
5. **Multi-hunk edits rare** (H7, H9) — Claude's Edit tool = 1 hunk per call; multi-hunk review paths under-exercised.
6. **Diagnostics + dirty/save UX heavy** (H10, H11) — verbose dumps, multi-step reasoning per simple query.

## Aux

- `:ClideToggle` when server not running: auto-starts and opens claude pane (behavior note, plan said "toggle does not restart anything" — only true while running).
- Selection annotations are ephemeral — sent as metadata, never touch file. Works on unsaved buffer content? User observed selection carried unsaved line; behavior unclear, worth one check.

## Follow mode

FAIL for IDE Claude, expected: its Edit/Write hit filesystem directly, bypass clide server, so `follow.queue()` never fires. Works for terminal Claude via vim_edit path. Steps 1–3 (config, edit, notify) verified ✅. Fix direction: PostToolUse hook bridge (approved 2026-07-06).

## UX wishlist (user notes)

- Interact with Claude from nvim without switching panes (H5).
- `<Leader>me` should optionally auto-submit, not just stage at-mention.
- Prime Claude with available IDE tools so it stops re-deriving connection.

## Tag gate

Blockers before tag: H13 + H14 need actual runs (no result recorded). Issue 1 (executeCode bypass) is a real gap — decide accept vs guard before tag.
