local config = require("clide.config")

local M = { name = "snacks" }

function M.is_available()
  local ok = pcall(require, "snacks.terminal")
  return ok
end

function M.open(cmd, env)
  require("snacks.terminal").open(cmd, { env = env })
end

function M.close()
  local term = require("snacks.terminal").get(config.get().terminal.cmd)
  if term then
    term:close()
  end
end

function M.toggle(cmd, env)
  require("snacks.terminal").toggle(cmd, { env = env })
end

return M
