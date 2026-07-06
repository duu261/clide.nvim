local M = {}

local pending = nil
local pending_timer = nil
local VALID_MODE = {
  off = true,
  jump = true,
  notify = true,
  both = true,
}

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

local function snapshot(path, opts)
  opts = opts or {}
  local mode = current_mode(opts)
  if not VALID_MODE[mode] then
    error("invalid follow mode: " .. tostring(mode))
  end
  return {
    path = path,
    mode = mode,
    modified = current_modified(opts),
    notify_fn = opts.notify_fn,
    open_fn = opts.open_fn,
  }
end

function M.queue(path, opts)
  pending = snapshot(path, opts)
  if pending_timer then
    return
  end
  pending_timer = vim.defer_fn(function()
    pending_timer = nil
    local queued = pending
    pending = nil
    if queued then
      M.handle(queued.path, queued)
    end
  end, 10)
end

function M.handle(path, opts)
  opts = opts or {}

  local mode = current_mode(opts)
  if not VALID_MODE[mode] then
    error("invalid follow mode: " .. tostring(mode))
  end
  if mode == "off" then
    return
  end

  local notify = mode == "notify" or mode == "both"
  local open = mode == "jump" or mode == "both"
  local modified = current_modified(opts)

  if opts.notify_fn or opts.open_fn then
    if notify and opts.notify_fn then
      opts.notify_fn(path)
    end
    if open and opts.open_fn then
      opts.open_fn(path, modified)
    end
    return
  end

  vim.schedule(function()
    if notify then
      vim.notify(path, vim.log.levels.INFO)
    end
    if open then
      if modified then
        vim.cmd.split()
      end
      vim.cmd.edit(vim.fn.fnameescape(path))
    end
  end)
end

return M
