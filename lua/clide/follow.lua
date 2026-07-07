-- same-file follow skip: dirty test
local M = {}

local pending = nil
local pending_timer = nil
local signal_watcher = nil

local VALID_MODE = {
  off = true,
  jump = true,
  notify = true,
  both = true,
}

function M.signal_file()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "clide", "follow_signal")
end

function M.setup()
  local dir = vim.fs.dirname(M.signal_file())
  vim.fn.mkdir(dir, "p")
  signal_watcher = vim.uv.new_fs_event()
  signal_watcher:start(
    dir,
    {},
    vim.schedule_wrap(function(err, fname)
      if err or not fname then
        return
      end
      if fname ~= vim.fs.basename(M.signal_file()) then
        return
      end
      local ok, lines = pcall(vim.fn.readfile, M.signal_file())
      if not ok or not lines or #lines == 0 then
        return
      end
      local path = vim.trim(lines[1])
      if path ~= "" then
        -- ponytail: same-buf skip prevents useless split on self-follow
        -- Per-file tracking if burst coalescing measurably drops paths.
        M.queue(path)
      end
    end)
  )
end

function M.teardown()
  if signal_watcher then
    signal_watcher:stop()
    signal_watcher:close()
    signal_watcher = nil
  end
end

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
      local same_buf = path == vim.fn.expand("%:p")
      if modified and not same_buf then
        vim.cmd.split()
      end
      pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    end
  end)
end

return M