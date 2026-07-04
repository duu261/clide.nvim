local config = require("clide.config")

local M = {}

function M.provider()
  local name = config.get().terminal.provider
  if name == "auto" then
    if require("clide.terminal.tmux").is_available() then
      name = "tmux"
    elseif require("clide.terminal.snacks").is_available() then
      name = "snacks"
    elseif require("clide.terminal.toggleterm").is_available() then
      name = "toggleterm"
    else
      name = "native"
    end
  end
  return require("clide.terminal." .. name)
end

--- env: table of KEY=VAL passed to the claude process.
function M.open(env)
  M.provider().open(config.get().terminal.cmd, env)
end

function M.close()
  M.provider().close()
end

function M.toggle(env)
  M.provider().toggle(config.get().terminal.cmd, env)
end

return M
