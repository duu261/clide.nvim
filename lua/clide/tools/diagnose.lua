local tools = require("clide.tools")

tools.register({
  name = "diagnose",
  description = "Check clide setup: Neovim version, claude binary, dependencies",
  inputSchema = { type = "object", properties = vim.empty_dict() },
  handler = function()
    local checks = {}

    if vim.fn.has("nvim-0.10") == 1 then
      table.insert(checks, { name = "Neovim >= 0.10", status = "ok" })
    else
      table.insert(checks, { name = "Neovim >= 0.10", status = "error" })
    end

    if vim.fn.executable("claude") == 1 then
      table.insert(
        checks,
        { name = "claude binary", status = "ok", detail = vim.fn.exepath("claude") }
      )
    else
      table.insert(
        checks,
        { name = "claude binary", status = "error", detail = "not found in PATH" }
      )
    end

    if pcall(require, "plenary.path") then
      table.insert(checks, { name = "plenary.nvim", status = "ok" })
    else
      table.insert(
        checks,
        { name = "plenary.nvim", status = "error", detail = "install nvim-lua/plenary.nvim" }
      )
    end

    local lock_dir = vim.fn.expand("~/.claude/ide")
    if vim.fn.isdirectory(lock_dir) == 1 then
      table.insert(checks, { name = "lock directory", status = "ok", detail = lock_dir })
    else
      table.insert(checks, {
        name = "lock directory",
        status = "warn",
        detail = "not yet created (ClideStart creates it)",
      })
    end

    return tools.json_result(checks)
  end,
})

return {}
