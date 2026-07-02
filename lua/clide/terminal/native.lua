local config = require("clide.config")

local M = { name = "native" }

local state = { buf = nil, win = nil }

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function buf_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

function M.is_available()
  return true
end

function M.open(cmd, env)
  if win_valid() then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  local cfg = config.get().terminal
  local width = math.floor(vim.o.columns * cfg.split_width)
  vim.cmd(cfg.split_side == "left" and "topleft vsplit" or "botright vsplit")
  vim.api.nvim_win_set_width(0, width)
  state.win = vim.api.nvim_get_current_win()

  if buf_valid() then
    vim.api.nvim_win_set_buf(state.win, state.buf)
  else
    vim.cmd.enew()
    state.buf = vim.api.nvim_get_current_buf()
    vim.fn.termopen(cmd, { env = env })
  end
  vim.cmd.startinsert()
end

function M.close()
  if win_valid() then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

function M.toggle(cmd, env)
  if win_valid() then
    M.close()
  else
    M.open(cmd, env)
  end
end

return M
