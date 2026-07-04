local M = { name = "toggleterm" }

local terminals = {}

function M.is_available()
  local ok = pcall(require, "toggleterm.terminal")
  return ok
end

local function terminal_for(cmd, env)
  if not terminals[cmd] then
    local Terminal = require("toggleterm.terminal").Terminal
    terminals[cmd] =
      Terminal:new({ cmd = cmd, direction = "vertical", env = env, close_on_exit = true })
  end
  return terminals[cmd]
end

function M.open(cmd, env)
  local t = terminal_for(cmd, env)
  if not t:is_open() then
    t:open()
  end
end

function M.close()
  for _, t in pairs(terminals) do
    if t:is_open() then
      t:close()
    end
  end
end

function M.toggle(cmd, env)
  local t = terminal_for(cmd, env)
  t:toggle()
end

return M
