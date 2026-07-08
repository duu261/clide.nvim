--- Interactive setup wizard (:ClideSetup). Replaces VS Code walkthrough.
local M = {}

local STEPS = {
  {
    title = "Check prerequisites",
    run = function()
      local results = {}
      -- Claude CLI
      local claude = vim.fn.executable("claude") == 1
      results[#results + 1] = claude and "claude CLI: found"
        or "claude CLI: NOT FOUND (install from anthropic.com)"
      -- Plenary
      local plenary_ok, _ = pcall(require, "plenary")
      results[#results + 1] = plenary_ok and "plenary.nvim: OK"
        or "plenary.nvim: MISSING (required dependency)"
      -- Neovim version
      local has_uv = pcall(vim.loop.new_timer) or pcall(vim.uv.new_timer)
      results[#results + 1] = has_uv and "Neovim >= 0.10: OK"
        or "Neovim: too old (need >= 0.10 for vim.uv)"

      local all_ok = claude and plenary_ok and has_uv
      return all_ok, results
    end,
  },
  {
    title = "Configure terminal provider",
    run = function()
      local results = {}
      local in_tmux = vim.env.TMUX ~= nil
      local has_snacks = pcall(require, "snacks")
      local has_toggleterm = pcall(require, "toggleterm")

      results[#results + 1] = "Detected providers:"
      if in_tmux then
        results[#results + 1] = "  tmux (active in $TMUX) — recommended"
      end
      if has_snacks then
        results[#results + 1] = "  snacks.nvim — installed"
      end
      if has_toggleterm then
        results[#results + 1] = "  toggleterm.nvim — installed"
      end
      results[#results + 1] = "  native (always available)"
      results[#results + 1] = ""
      results[#results + 1] = "Default: 'auto' detects tmux > snacks > toggleterm > native"
      if in_tmux then
        results[#results + 1] = "tmux is active — provider will use tmux. Good choice."
      end

      return true, results
    end,
  },
  {
    title = "Set up keymaps",
    run = function()
      local results = {}
      results[#results + 1] = "Default keymaps (all <Leader>m prefix):"
      results[#results + 1] = "  <Leader>mt — :ClideToggle  (toggle Claude terminal)"
      results[#results + 1] = "  <Leader>ms — :ClideStart   (start server)"
      results[#results + 1] = "  <Leader>mq — :ClideStop    (stop server)"
      results[#results + 1] = "  <Leader>ml — :ClideLog     (view log)"
      results[#results + 1] = "  <Leader>me — :ClideSend    (send selection, visual mode)"
      results[#results + 1] = "  <Leader>mz — send + toggle (visual mode)"
      results[#results + 1] = ""
      results[#results + 1] = "Review keymaps (buffer-local, active during review):"
      results[#results + 1] = "  <Leader>ma — accept hunk"
      results[#results + 1] = "  <Leader>mr — reject hunk"
      results[#results + 1] = "  <Leader>mA — accept all hunks"
      results[#results + 1] = "  <Leader>mR — reject all hunks"
      results[#results + 1] = "  ]h / [h   — next/prev hunk"
      results[#results + 1] = ""
      results[#results + 1] =
        "Customize: require('clide').setup({ cmd_keymaps = {...}, review = { keymaps = {...} } })"
      return true, results
    end,
  },
  {
    title = "Start and test",
    run = function()
      local clide = require("clide")
      if clide.state.server then
        return true,
          {
            "Server already running on port " .. clide.state.server.port,
            "Run :ClideStop first to restart.",
          }
      end
      return true,
        {
          "Ready to start.",
          "Run :ClideStart to launch Claude in a terminal pane.",
          "Claude will connect via WebSocket on 127.0.0.1.",
          "Check :ClideLog for connection status.",
          "",
          "Tip: :checkhealth clide for a full diagnostic.",
        }
    end,
  },
}

function M.run()
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(30, vim.o.lines - 4)
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

  -- Run all steps
  local all_lines = {}
  table.insert(all_lines, "clide.nvim — Setup Wizard")
  table.insert(all_lines, string.rep("=", width - 2))
  table.insert(all_lines, "")

  for _, step in ipairs(STEPS) do
    table.insert(all_lines, "◆ " .. step.title)
    table.insert(all_lines, "")
    local ok, results = step.run()
    for _, line in ipairs(results) do
      table.insert(all_lines, "  " .. line)
    end
    table.insert(all_lines, "")
    table.insert(all_lines, ok and "  ✓ OK" or "  ✗ Issues found")
    table.insert(all_lines, "")
    table.insert(all_lines, "")
  end

  table.insert(all_lines, string.rep("─", width - 2))
  table.insert(all_lines, "Setup complete. Run :ClideStart to begin.")
  table.insert(all_lines, "Press q or <Esc> to close this window.")

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
