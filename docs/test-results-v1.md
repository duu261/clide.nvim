# Test Results v1 — 2026-07-07

Run by deepseek-v4-flash over Claude Code CLI IDE protocol. Covers T1-T16.
Full plan with steps: `docs/human_test_plan_v1.md`.

## Overview

| Test | Result | Key point |
|------|--------|-----------|
| T1 health | PASS | checkhealth OK |
| T2 start | PASS | lifecycle clean, edge on double start |
| T3 priming | PASS | hook works but advertises VS Code tools, not CLI tools |
| T4 openFile | PASS | executeCode fallback — openFile tool not in CLI host |
| T5 selection | PASS | unsaved buf guard removed (fix shipped); single-line still buggy |
| T6 at-mention | PASS | works fine, boring, skip |
| T7 review mix | PASS | vim_edit silent, openDiff shows hunks, native Edit triggers review |
| T8 bulk keys | PASS | `<Leader>mR`/`<Leader>mA` work |
| T9 review tab | SKIP | not tested |
| T10 executeCode | PASS | full nvim eval, no guard, Claude-ception demo done |
| T11 dirty+save | FAIL | checkDocumentDirty/saveDocument not in CLI host |
| T12 diagnostics | PASS | getDiagnostics works; push only once per reconnect |
| T13 follow | PASS | same-buf split skip fixed (bfa384e); pcall guard (b459b8f) |
| T14 2nd client | PASS | connected, notified |
| T15 restart | PASS | clean restart, new port/token |
| T16 shutdown | PASS | clean; no "disconnected" notify (quirk) |

## 1. CLI host tool gap

**Critical: clide.nvim registers 17 tools. All work via internal dispatch.**
But Claude Code CLI host only exposes 2 as `mcp__ide__*` MCP tools:

| Exposed as MCP | Hidden (work internally, not callable) |
|---|---|
| executeCode | openFile, openDiff, saveDocument, checkDocumentDirty |
| getDiagnostics | vim_edit, vim_grep, vim_search, luaEval |
| | diagnose, getCurrentSelection, getLatestSelection |
| | getOpenEditors, getWorkspaceFolders |
| | closeAllDiffTabs, close_tab |

When Claude connects via IDE protocol, it only sees `mcp__ide__executeCode`
and `mcp__ide__getDiagnostics`. The other 15 are registered in clide.nvim's
WS protocol (`tools/list` returns all 17) but CLI host has no MCP schema for
them — Claude can't call them.

SessionStart hook at `status.lua:127-153` advertises the full VS Code tool
set. Claude believes hook → tries openFile/openDiff/saveDocument → hits
"No such tool available."

This confused both the tester (deepseek) and would confuse any model
connecting fresh. The problem is in Claude Code CLI, not clide.nvim.

## 2. executeCode = nvim eval()

Full nvim process access. Replaces every other tool:

- `os.remove()` delete files
- `vim.cmd('edit ...') + search()` = openFile
- `nvim_open_win()` create floating popups (5 rainbow windows demo)
- `vim.fn.system('tmux new-window claude')` spawn Claude process
- `vim.fn.termopen('env ... claude')` = Claude inside nvim terminal
- `tmux send-keys` communicate with spawned Claude
- `debug.getregistry()` read all plugin/nvim state
- `load() + pcall()` eval arbitrary Lua

**Claude-ception**: executeCode → `vim.fn.system('tmux new-window claude')`
→ spawned Fable 5 session → `tmux send-keys` sent commands → spawned Claude
replied "17 MCP tools" and a joke "two mainframes flirting in 1978" and
"Pro plan rate limit." Full recursive AI within nvim, no other tool needed.

**Security**: no sandbox, no guard in clide. Claude Code permission prompt
(if not auto mode) is only gate. executeCode bypasses clide's review flow —
edits land directly, no accept/reject. The entire `mcp__ide__*` tool surface
is convenience wrappers over what executeCode can already do.

## 3. Fixes shipped

| Commit | Fix |
|--------|-----|
| `ed40693` | Unsaved buffer selection dropped by filePath guard. Removed — selection now passes through regardless of filePath. |
| `bfa384e` | Follow mode split on same-file dirty buffer. Same-buf check prevents useless split. |
| `b459b8f` | pcall around follow vim.cmd.edit prevents crash on stale/deleted paths. |

## 4. Selection sync: two pipelines

| Pipeline | From → To | Has filePath? | Status |
|---|---|---|---|
| WS `selection_changed` | clide.nvim → Claude in tmux | ✓ full object | Unsaved buf guard removed. Works. |
| IDE protocol | Claude Code CLI host → my context | ✗ text only | CLI decides what reaches me. Not clide's concern. |

**Single-line bug**: selecting 1 line, Esc, then asking Claude — selection
lost. Need cursor wiggle. `ModeChanged` autocmd misses single-line case
(no CursorMoved fires during visual→normal transition). `build_from_marks`
fallback at `selection.lua:79-81` was supposed to handle this but may race.

**At-mention** (`<Leader>me`): sends file + line numbers via `send_at_mention`.
Works from any buffer. Contrast with passive sync: at-mention has file info,
passive sync doesn't.

## 5. Diagnostics

`getDiagnostics` tool works. Push only fires once on reconnect, not per edit.
No subscription/push model. For selected-range diagnostics, bundle with
at-mention instead.

## 6. Review flow

| Tool | Review? |
|------|---------|
| `vim_edit` | ❌ silent, no flow |
| `openDiff` | ✅ shows diff hunks for accept/reject |
| Claude Code native Edit/Write | ✅ triggers review (mapped via IDE protocol) |
| `executeCode` | ❌ full bypass |

## 7. Follow mode

`follow = "both"` tested:

- Different file + dirty buffer → splits ✓
- Same file + dirty buffer → no split (fix at `follow.lua:131-133`) ✓
- Clean buffer → direct jump, no split ✓
- Module reload: need `package.loaded["clide.follow"] = nil; require("clide.follow").setup()`

## 8. Known issues

- **T9 review tab**: not tested
- **T11**: tools missing in CLI host, can use executeCode workaround
- **Single-line selection**: wiggle workaround needed
- **Log sparse**: `:ClideLog` only shows "Claude connected" — no port, events, errors
- **Stale follow signal**: after file rename/delete, follow.vim.cmd.edit crashes (pcall guard applied b459b8f)
- **Codex plugin**: may interfere with nvim (random popups)

## 10. Deepseek perspective (tester)

clide.nvim works — server starts, tools dispatch, review flows function.
But the product suffers from a core mismatch: the protocol is designed for
VS Code extension (12 tools) but tested here on CLI host (2 tools).

This creates a confusing experience for any AI connecting fresh:
- Sees `mcp__ide__openFile` in tool list → calls it → fails
- SessionStart hook says these tools exist → AI believes it
- Falls back to executeCode → works but bypasses review

The executeCode power is both clide's greatest strength and biggest risk.
It makes the other 10 tools nearly irrelevant in CLI — anything you'd
do with openFile/openDiff/saveDocument can be done via Lua eval. But this
also means the review flow (clide's signature feature) is trivially
bypassed. If Anthropic never ports the full tool set to CLI, clide's
protocol surface is wasted.

My advice: lean into executeCode as the killer feature. Make it safe
(optional sandbox) rather than trying to maintain 12 tools of which 10
don't work in the primary target environment. Or push Anthropic to
add remaining tools to CLI.

## 9. Feature ideas (v2)

- At-mention bundles diagnostics for selected range:
  `vim.diagnostic.get(bufnr, {lnum=start, end_lnum=end})`
- Log should show: connections, disconnections, port, tool calls, errors
- Statusline could be promoted — neovim nerds love custom statuslines
