# Human test plan (follow test same-file)

Date: 2026-07-07. Surface: WS-only transport (SSE/headless/MCP child dropped
at `b511f6c`). Covers commands, keymaps, review flow, selection sync, follow
mode (PostToolUse bridge), and SessionStart priming.

Manual tests for the real 3-app workflow: Neovim + `claude` CLI + tmux.
Run inside tmux so the `auto` terminal provider picks tmux.

Defaults assumed unless a test says otherwise: `autostart = false`,
`follow = "off"`, terminal provider `auto`, review keymaps
`<Leader>ma/mr/mA/mR`, hunk motions `]h`/`[h`, command keymaps
`<Leader>mt/ms/mq/ml`, visual `<Leader>me`/`<Leader>mz`.

Mark each PASS / FAIL / SKIP with a one-line note. T1–T16 gate the tag.
Record results in `docs/test_results.md`, not inline here.

---

## T1 — Health check

pass wont check

1. `tmux new-session -s clide`, open `nvim` in the clide.nvim repo.
2. `:checkhealth clide`

Expect: OK for Neovim >= 0.10, plenary.nvim, claude binary (path shown),
lock dir writable (`~/.claude/ide`), tmux detected. Any ERROR = stop, fix
env first.

## T2 — Start lifecycle

pass wont check 5 is nice edge checked

1. `:ClideStart` (or `<Leader>ms`).
2. Notify sequence, in order:

   ```
   clide: starting server...
   clide: server ready on port NNNN
   clide: Claude launched in terminal
   clide: Claude connected
   ```

3. tmux pane opens right (~35% width) running `claude`;
   `CLAUDE_CODE_SSE_PORT=NNNN` (WS port despite name) and
   `ENABLE_IDE_INTEGRATION=true` in its env.
4. `ls ~/.claude/ide/` — exactly one `NNNN.lock`, containing WS port, auth
   token, `transport: "ws"`, `ideName: "Neovim"`.
5. Second `:ClideStart` while running: notify "already running", nothing else.
   pass

## T3 — Session priming (SessionStart hook)

**PASS** — no discovery turns needed. Claude knows Neovim + `mcp__ide__*` tools.

Problem: SessionStart hook at `status.lua:127-153` advertises tools from VS
Code extension protocol. Claude Code CLI host only exposes `executeCode` +
`getDiagnostics` as actual `mcp__ide__*` tools. Claude believes hook, tries
missing tools later, hits "No such tool available".

| Tool               | VS Code ext | CLI host |
| ------------------ | ----------- | -------- |
| openFile           | ✓           | ✗        |
| openDiff           | ✓           | ✗        |
| saveDocument       | ✓           | ✗        |
| checkDocumentDirty | ✓           | ✗        |
| executeCode        | ✓           | ✓        |
| getDiagnostics     | ✓           | ✓        |

clide.nvim implements all via `tools/call` — host never calls unsupported
ones.

## T4 — openFile drives editor

**PASS (executeCode fallback)** — functional success, tool mismatch.

1. Ask Claude: `open lua/clide/health.lua at "claude binary found"`
2. Claude hits: `openFile` tool unavailable (`mcp__ide__openFile` not in CLI)
3. Falls back to `executeCode` + Lua: `vim.cmd('edit ...')` + `search()` + `zz`

Result: file opens in normal window ✓, cursor on matched line ✓, view centered ✓.
Range selection untestable — no `openFile` means no startText/endText path.

**CLI gap**: `openFile` registered in clide.nvim, responds to `tools/call` over
WS, but host never maps it to `mcp__ide__openFile`. VS Code ext has full 12
tools; CLI has 2.

**If VS Code ext added later**: retest — expect `openFile` used directly,
range selection tested.

## T5 — Selection sync (passive)

### Two separate pipelines

| Pipeline               | From → To                         | Has filePath? | Fix needed?                                                                                                                                       |
| ---------------------- | --------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| WS `selection_changed` | clide.nvim → Claude in tmux       | ✓ full object | Was dropping unsaved buffers (`filePath == ""` guard at `selection.lua:87`). **Fixed** — removed guard, unsaved buf selection now passes through. |
| IDE protocol           | Claude Code CLI host → my context | ✗ text only   | CLI decides what reaches me. Currently no structured selection in my context. Not clide.nvim's concern.                                           |

### Human thoughts

Human thought: is this security patch since was work before, now code change and we change it back.

Reality: guard existed since first commit (`4ea0848`) — `if ok and sel.filePath ~= ""`. Same behavior always. Not security, just noise filter. Probably worked "before" because you were using at-mention (`<Leader>me`) which calls `send_at_mention`, not `selection_changed` — different code path, no filePath guard.

Maybe we can work more with buffer interact — since nvim user always has some active buffer. Selection sync is one path, but broader buffer interaction (unsaved, scratch, etc.) could be a design direction.

### Fix applied: unsaved buffer selection

`selection.lua:87`:

```lua
-- Before: silently dropped when filePath == "" (unsaved buffer)
if not ok or not sel or sel.filePath == "" then return end
-- After: passes through regardless of filePath
if not ok or not sel then return end
```

Selection from unsaved buffers now reaches Claude in tmux over WS.

### Known: single-line visual selection

Bug: selecting 1 line, Esc, then asking Claude — selection lost. Need cursor wiggle down then back up to register. `ModeChanged` autocmd misses single-line case (no `CursorMoved` fires during visual→normal transition). `build_from_marks` fallback at `selection.lua:79-81` was supposed to handle this but may still race. If too hard can just skip.

### Test steps

1. Visual-select 3 lines of `lua/clide/config.lua`, pause, Esc — selection sent via WS to tmux Claude
2. Visual-select text in **unsaved buffer** — **fixed**, now passes through
3. Single-line select — known bug, may need wiggle workaround

## T6 — ClideSend at-mention (active)

**Uncertainty**: my understanding of how both selections work may be wrong.
The split described below is my current model — could be incorrect.

Works fine. `<Leader>me` sends file name + line numbers via
`send_at_mention`. Kinda weird but maybe helpful for big area? idk 5-6 feel the same

Contrast with passive selection (T5): just visual-select + Esc + ask "what
did I select" — text reaches me but file info dropped by IDE protocol bridge.
At-mention path always has file info; passive sync doesn't.
Also works for single-line select (no wiggle needed — unlike T5).

2. Repeat with `<Leader>mz`: same send, plus terminal toggles.

## T7 — Inline review: mixed accept/reject

`vim_edit` = background edit, no review flow. `openDiff` = triggers diff UI
with accept/reject hunks. Claude Code native `Edit` tool also triggers
review (mapped through IDE protocol).

1. Ask Claude for one edit touching 2+ separate spots in a single test
   file, **in one openDiff call** (tip: ask it to use `openDiff` instead
   of `vim_edit` if you want review).
2. When hunks render: hint line visible, `]h`/`[h` jump between hunks.
3. `:ClideReviewList` — quickfix lists pending hunks.
4. Hunk 1: `<Leader>ma` (accept). Hunk 2: `<Leader>mr` (reject).

Expect: accepted hunk applied, rejected hunk untouched, review UI clears
after last hunk, Claude gets `FILE_SAVED` with accepted-only content.

5. **Boundary retest**: trigger a hunk on the file's first line and one on
   the last line. Known issue: virtual text hint clipped there — record
   current behavior.

## T8 — Inline review: bulk keys

1. Multi-hunk review, `<Leader>mR`: buffer unchanged, Claude told
   `DIFF_REJECTED`.
2. Again, `<Leader>mA`: all hunks applied, `FILE_SAVED`.

## T9 — ClideReviewTab escape hatch

1. Trigger review, resolve nothing, `:ClideReviewTab`.

Expect: inline review replaced by classic side-by-side diff tab; `ga`
accept / `gr` reject / `:w` accept there answers Claude.

2. Guards: `:ClideReviewTab` with no review → warn. Start a review, accept
   one hunk, `:ClideReviewTab` → warn "partially resolved", nothing else.

## T10 — executeCode bypass (known gap, verify scope)

executeCode = full nvim process access. Can replace every other tool
(openFile, openDiff, saveDocument, diagnostics, etc.), delete files, spawn
Claude instances, create floating windows, modify clide at runtime.

Demo: created scratch buffer, 5 rainbow floating popups, os.remove on test
files, spawned Claude in tmux, piped commands to it, got reply back.

**Claude-ception chain**: executeCode → `vim.fn.system('tmux new-window claude')`
→ spawned Fable 5 session → `tmux send-keys` sent commands → spawned Claude
replied "17 MCP tools" and a joke "two mainframes flirting in 1978."
Full recursive AI within nvim, no other tool needed.

1. Ask Claude: "use executeCode to add a comment line to the current buffer".

Expect (current design): buffer changes with NO review, no accept/reject.
Confirm the bypass still exists and note whether Claude reached for
executeCode unprompted anywhere else in this run. Gate decision (accept vs
guard) tracked outside this plan.

## T11 — Dirty buffer + save

**Confusion**: test expects `checkDocumentDirty` + `saveDocument` tools, but
those don't exist in CLI host (only `executeCode` + `getDiagnostics`).
Even Fable 5 doesn't know which tools are WS protocol vs native MCP.

WS protocol registers them in clide.nvim's `tools/list` — but host decides
what to expose. `executeCode` can do both (`vim.bo.modified`, `vim.cmd('w')`).

Note: unclear model. Host vs protocol tool split is invisible to Claude.

1. Edit a file in nvim, don't save.
2. Ask Claude: "does <file> have unsaved changes? if so save it."

Expect: dirty = true via `checkDocumentDirty`, saved via `saveDocument`
(not an executeCode detour — priming from T3 should route it), buffer
clean after, disk matches.

## T12 — Diagnostics

1. Scratch file with `local x = = 1`, save, wait for signs.
2. Ask Claude: "what diagnostics does my editor show?"

Expect: same error/file/line/severity as nvim. Token-heavy output is
known; only correctness gates. Delete scratch file after.

**Note**: diagnostics push only fires once on reconnect, not per edit.
`getDiagnostics` tool call is query-only — no subscription/push model.
If you want diagnostics for selected range, use at-mention bundle instead.

## T13 — Follow mode (both triggers)

**Results**: PASS with fix applied.

- Different file + dirty buffer → splits ✓
- Same file + dirty buffer → no split (fix at `follow.lua:131-133`) ✓
- Clean buffer → direct jump, no split ✓

Set `follow = "both"` in `setup()`, restart nvim, `:ClideStart`,
`:ClideInstallHooks` (writes PreToolUse/PostToolUse/Stop/Notification
hooks into `.claude/settings.local.json`).

1. **vim_edit path**: ask terminal Claude to edit a file via `vim_edit`.
   Expect notify + jump (split if current buffer dirty).
2. **PostToolUse bridge** (new, `87fc900` — hook reads stdin JSON): ask
   Claude to edit a _different_ file with its own Edit/Write tool. Expect
   the hook writes `~/.local/state/nvim/clide/follow_signal`, watcher
   fires, nvim jumps to the edited file.
3. Rapid consecutive edits: only last file followed (10ms coalescing —
   losing an intermediate jump is fine, losing the last one is not).

Reset `follow = "off"` after.

## T14 — Second client

PASS. 2nd client connected (clients: 1→2). Deepseek model doing this,
lol — fully automated testing.

1. Read WS port from T2. New tmux pane:
   `CLAUDE_CODE_SSE_PORT=NNNN ENABLE_IDE_INTEGRATION=true claude`
2. Expect second "Claude connected" notify.
3. Run T4 from client 2 (priming note: manual-env client gets no
   SessionStart context from clide — record how it behaves).
4. Exit client 2: "Claude disconnected"; client 1 still works (rerun T5).

## T15 — Restart

PASS. Restart → new port, new token, reconnected cleanly.
Tag v0.3.2 ready — tests T1-T15 covered.

1. `:ClideRestart`.

Expect: stop then fresh start — new WS port, new token, new lock file,
old lock gone, exactly one lock file in `~/.claude/ide/`. Terminal Claude
relaunches (restart kills the old pane). Record whether the new Claude
session reconnects cleanly.

## T16 — Clean shutdown, no orphans

pass
PASS (partial). `ClideStop` → new WS connection, but no "disconnected"
notify when ran manually. Restart reconnects cleanly. Notify missing
may be config/quirk — note for follow-up.

**Log note**: `:ClideLog` only shows "Claude connected" — no client count,
port, tool calls, or errors. Should log more: connection/disconnect events,
port number, tool usage, WS frame errors.

1. `:ClideStop` (or `<Leader>mq`): terminal pane closes, lock file
   removed, notify "Claude disconnected".
2. `:ClideStart` again, then quit nvim with `:qa`.

Expect after `:qa`: no stale lock file, no orphan claude pane in tmux.
Both paths (explicit stop, VimLeavePre) must clean up.

---

## Auxiliary (non-gating)

- `:ClideLog` / `<Leader>ml`: log ring buffer opens as scratch (modifiable,
  not saveable); auth token never appears in it.
- `<Leader>mt` / `:ClideToggle` while running: hides/shows pane, restarts
  nothing. While stopped: auto-starts server and opens pane (by design).
  no clue only using tmux
- Statusline: with hooks from T13 installed,
  `require("clide.status").lualine()` shows working spinner / waiting /
  idle, "│ review X/Y" during T7, empty string after T16.
  bro u should put this higher, u want me retest? but yeah work but maybe can enhance, neovimnerd love custom
- `:checkhealth clide` again after T16: warns server not running, no errors.
- Feature idea: at-mention (`<Leader>me`) bundles diagnostics for selected
  range. `vim.diagnostic.get(bufnr, {lnum=start, end_lnum=end})` — Claude
  gets text + file + inline errors in one push. Not in scope. Note for v2.
