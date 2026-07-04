local config = require("clide.config")
local log = require("clide.util.log")

local M = { name = "tmux" }

local pane_id = nil

function M.is_available()
  return vim.env.TMUX ~= nil and vim.fn.executable("tmux") == 1
end

local function pane_alive()
  if not pane_id then
    return false
  end
  local out = vim.system({ "tmux", "list-panes", "-F", "#{pane_id}" }):wait()
  return out.code == 0 and out.stdout:find(pane_id, 1, true) ~= nil
end

function M.open(cmd, env)
  if pane_alive() then
    vim.system({ "tmux", "select-pane", "-t", pane_id }):wait()
    return
  end

  local cfg = config.get().terminal
  local args = { "tmux", "split-window", "-P", "-F", "#{pane_id}", "-d", "-h" }
  if cfg.split_side == "left" then
    table.insert(args, "-b")
  end
  table.insert(args, "-l")
  table.insert(args, math.floor(cfg.split_width * 100) .. "%")
  for k, v in pairs(env or {}) do
    table.insert(args, "-e")
    table.insert(args, k .. "=" .. v)
  end
  table.insert(args, cmd)

  local out = vim.system(args):wait()
  if out.code ~= 0 then
    log.log("error", "tmux split-window failed: " .. (out.stderr or ""))
    return
  end
  pane_id = vim.trim(out.stdout)

  local project = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  vim.system({ "tmux", "select-pane", "-T", "clide:" .. project, "-t", pane_id }):wait()
end

function M.close()
  if pane_alive() then
    vim.system({ "tmux", "kill-pane", "-t", pane_id }):wait()
  end
  pane_id = nil
end

function M.toggle(cmd, env)
  -- ponytail: tmux has no hide/show for panes; toggle = focus or create.
  M.open(cmd, env)
end

return M
