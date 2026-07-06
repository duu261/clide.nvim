local M = {}

local pending_path
local pending_timer = nil

local function current_mode(opts)
  if opts.mode ~= nil then
    return opts.mode
  end
  return require("clide.config").get().follow
end

local function current_modified(opts)
  if opts.modified ~= nil then
    return opts.modified
  end
  return vim.bo.modified
end

function M.queue(path)
  pending_path = path
  if pending_timer then
    return
  end
  pending_timer = vim.defer_fn(function()
    pending_timer = nil
    local path_to_follow = pending_path
    pending_path = nil
    if path_to_follow then
      M.handle(path_to_follow)
    end
  end, 10)
end

function M.handle(path, opts)
  opts = opts or {}

  local mode = current_mode(opts)
  if mode == "off" then
    return
  end

  local notify = mode == "notify" or mode == "both"
  local open = mode == "jump" or mode == "both"
  local modified = current_modified(opts)

  if notify then
    if opts.notify_fn then
      opts.notify_fn(path)
    else
      vim.schedule(function()
        vim.notify(path, vim.log.levels.INFO)
      end)
    end
  end

  if not open then
    return
  end

  if opts.open_fn then
    opts.open_fn(path, modified)
    return
  end

  vim.schedule(function()
    if modified then
      vim.cmd.split()
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
  end)
end

return M
