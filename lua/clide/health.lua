local M = {}

function M.check()
  local health = vim.health

  health.start("clide.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim 0.10+ required (vim.getregion, vim.base64)")
  end

  if pcall(require, "plenary.path") then
    health.ok("plenary.nvim found")
  else
    health.error("plenary.nvim not found", { "install nvim-lua/plenary.nvim" })
  end

  if vim.fn.executable("claude") == 1 then
    health.ok("claude binary found: " .. vim.fn.exepath("claude"))
  else
    health.error("claude binary not found in PATH", { "npm install -g @anthropic-ai/claude-code" })
  end

  local lock_dir = vim.fn.expand("~/.claude/ide")
  if vim.fn.isdirectory(lock_dir) == 1 or vim.fn.mkdir(lock_dir, "p") == 1 then
    health.ok("lock dir writable: " .. lock_dir)
  else
    health.error("cannot create lock dir: " .. lock_dir)
  end

  if vim.env.TMUX and vim.fn.executable("tmux") == 1 then
    health.ok("tmux detected — tmux provider available")
  else
    health.info("not inside tmux — native provider will be used for auto")
  end

  local state = require("clide").state
  if state.server then
    health.ok("server running on port " .. state.server.port)
  else
    health.warn("server not running — :ClideStart to launch")
  end
end

return M
