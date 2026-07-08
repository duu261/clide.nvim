--- Interactive setup wizard (:ClideSetup). Matches VS Code walkthrough steps.
--- Content adapted from official Anthropic.claude-code extension walkthrough.
local M = {}

--- Step 1: Welcome (matches VS Code step1.md)
local function step_welcome(width)
  local lines = {}
  lines[#lines + 1] = "clide.nvim helps you write, edit, and understand"
  lines[#lines + 1] = "code right in Neovim."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Claude can read your files, make edits, run terminal"
  lines[#lines + 1] = "commands, and help you navigate complex codebases."
  lines[#lines + 1] = "It understands context and works alongside you like"
  lines[#lines + 1] = "a knowledgeable teammate."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "clide.nvim runs Claude in a terminal pane beside"
  lines[#lines + 1] = "nvim — tmux, snacks, toggleterm, or native."

  local claude = vim.fn.executable("claude") == 1
  local plenary_ok, _ = pcall(require, "plenary")
  local has_uv = pcall(vim.loop.new_timer) or pcall(vim.uv.new_timer)
  local all_ok = claude and plenary_ok and has_uv

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Prerequisites:"
  lines[#lines + 1] = "  " .. (claude and "✓" or "✗") .. " Claude CLI (claude)"
  lines[#lines + 1] = "  " .. (plenary_ok and "✓" or "✗") .. " plenary.nvim"
  lines[#lines + 1] = "  " .. (has_uv and "✓" or "✗") .. " Neovim >= 0.10"
  lines[#lines + 1] = ""
  lines[#lines + 1] = all_ok and "  ✓ Ready" or "  ✗ Install missing prerequisites first"

  return all_ok, lines
end

--- Step 2: Launch Claude (matches VS Code step2.md)
local function step_launch(width)
  local lines = {}
  lines[#lines + 1] = "Run :ClideStart or press <Leader>ms to launch"
  lines[#lines + 1] = "Claude in a terminal pane beside nvim."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Toggle Claude terminal: <Leader>mt (:ClideToggle)"
  lines[#lines + 1] = "Spawn another Claude pane: :ClideSpawn"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Terminal provider detected:"

  local in_tmux = vim.env.TMUX ~= nil
  local has_snacks = pcall(require, "snacks")
  local has_toggleterm = pcall(require, "toggleterm")

  if in_tmux then
    lines[#lines + 1] = "  tmux (active) — Claude opens in a new pane"
  elseif has_snacks then
    lines[#lines + 1] = "  snacks.nvim — Claude opens in snacks terminal"
  elseif has_toggleterm then
    lines[#lines + 1] = "  toggleterm.nvim — Claude opens in toggleterm"
  else
    lines[#lines + 1] = "  native — Claude opens in :terminal split"
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Prefer a different provider? Set it in setup():"
  lines[#lines + 1] = "  require('clide').setup({"
  lines[#lines + 1] = "    terminal = { provider = 'tmux' }"
  lines[#lines + 1] = "  })"

  return true, lines
end

--- Step 3: Send context (matches VS Code step3.md)
local function step_send(width)
  local lines = {}
  lines[#lines + 1] = "Ask questions, request changes, or get help"
  lines[#lines + 1] = "understanding your code. Claude can:"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  • Explain what code does"
  lines[#lines + 1] = "  • Fix bugs and errors"
  lines[#lines + 1] = "  • Write new features"
  lines[#lines + 1] = "  • Refactor existing code"
  lines[#lines + 1] = "  • Run terminal commands"
  lines[#lines + 1] = "  • Execute Lua in nvim (executeCode)"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Context you can send (no @-mention needed —"
  lines[#lines + 1] = "content arrives directly in Claude's context):"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Visual select → <Leader>me  (:ClideSend)"
  lines[#lines + 1] = "  Current file  → :ClideSendFile"
  lines[#lines + 1] = "  Any buffer    → :ClideSendBuffer <name>"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Advantage over VS Code: content lands directly —"
  lines[#lines + 1] = "no round-trip openFile call. Unsaved edits"
  lines[#lines + 1] = "are sent as-is."

  return true, lines
end

--- Step 4: Sessions (matches VS Code step4.md)
local function step_sessions(width)
  local lines = {}
  lines[#lines + 1] = "Access your chat history and start new"
  lines[#lines + 1] = "conversations anytime."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Conversations saved automatically."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Browse past sessions:  :ClideSessions"
  lines[#lines + 1] = "  Resume most recent:    :ClideContinue"
  lines[#lines + 1] = "  New conversation:      :ClideSpawn"
  lines[#lines + 1] = "  Create worktree:       :ClideWorktree"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Session data in ~/.claude/sessions/."
  lines[#lines + 1] = "Each session: timestamp, name, status, cwd."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Pro tip: review changes inline — per-hunk"
  lines[#lines + 1] = "accept/reject with <Leader>ma / <Leader>mr."
  lines[#lines + 1] = "VS Code can't do this at hunk granularity."

  return true, lines
end

local STEPS = {
  { title = "Welcome to clide.nvim", run = step_welcome },
  { title = "Launch Claude", run = step_launch },
  { title = "Send context and chat", run = step_send },
  { title = "Session management", run = step_sessions },
}

function M.run()
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(34, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " clide setup ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  local all_lines = {}
  local sep = string.rep("─", width - 2)

  table.insert(all_lines, "clide.nvim — Setup Wizard")
  table.insert(all_lines, sep)
  table.insert(all_lines, "")

  for _, step in ipairs(STEPS) do
    table.insert(all_lines, "◆ " .. step.title)
    table.insert(all_lines, "")
    local ok, results = step.run(width)
    for _, line in ipairs(results) do
      table.insert(all_lines, "  " .. line)
    end
    table.insert(all_lines, "")
    table.insert(all_lines, ok and "  ✓ OK" or "  ✗ Check above")
    table.insert(all_lines, "")
    table.insert(all_lines, "")
  end

  table.insert(all_lines, sep)
  table.insert(all_lines, "Run :ClideStart to begin. Press q or <Esc> to close.")
  table.insert(all_lines, "Full docs: :help clide  |  :checkhealth clide")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
  vim.bo[buf].modifiable = false

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

return M
