local M = {}

local Path = require("plenary.path")
local watcher = nil

-- ponytail: single state file — two Neovim instances sharing it will clash.
-- Per-port state files if multi-session lands in v2.
function M.state_file()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "clide", "status")
end

local function read_state()
  local ok, content = pcall(function()
    return Path:new(M.state_file()):read()
  end)
  if not ok or not content or content == "" then
    return "idle"
  end
  return vim.trim(vim.split(content, "\n")[1])
end

function M.setup()
  local dir = vim.fs.dirname(M.state_file())
  vim.fn.mkdir(dir, "p")
  watcher = vim.uv.new_fs_event()
  watcher:start(
    dir,
    {},
    vim.schedule_wrap(function()
      pcall(vim.cmd, "redrawstatus")
    end)
  )
end

function M.teardown()
  if watcher then
    watcher:stop()
    watcher:close()
    watcher = nil
  end
end

function M.get()
  local state = require("clide").state
  if not state.server then
    return "stopped"
  end
  if not state.connected then
    return "disconnected"
  end
  -- ponytail: sync read per render beats stale cache; avoids race between hook
  -- file write and fs_event delivery. Switch to cached if statusline profiling shows cost.
  return read_state()
end

local icons = {
  working = "󰚩 working",
  waiting = "󰋗 waiting",
  idle = "󰚩 idle",
  disconnected = "󰚩 ─",
}

--- lualine component: require("clide.status").lualine
function M.lualine()
  local s = M.get()
  if s == "stopped" then
    return ""
  end
  local review = require("clide.review.queue").statusline()
  local base = icons[s] or s
  if review ~= "" then
    return base .. " │ " .. review
  end
  return base
end

--- Hook config fragment merged into .claude/settings.local.json.
function M.hooks_config()
  local file = M.state_file()
  local function write_cmd(state)
    return "sh -c 'echo " .. state .. " > " .. vim.fn.shellescape(file) .. "'"
  end
  return {
    hooks = {
      PreToolUse = { { hooks = { { type = "command", command = write_cmd("working") } } } },
      Stop = { { hooks = { { type = "command", command = write_cmd("idle") } } } },
      Notification = { { hooks = { { type = "command", command = write_cmd("waiting") } } } },
    },
  }
end

--- Merge hooks into the project's .claude/settings.local.json.
function M.install_hooks()
  local path = vim.fs.joinpath(vim.fn.getcwd(), ".claude", "settings.local.json")
  local settings = {}
  local ok, content = pcall(function()
    return Path:new(path):read()
  end)
  if ok then
    local dok, decoded = pcall(vim.json.decode, content)
    if dok then
      settings = decoded
    end
  end

  settings.hooks = settings.hooks or {}
  local fragment = M.hooks_config().hooks
  for event, entries in pairs(fragment) do
    settings.hooks[event] = settings.hooks[event] or {}
    local already = false
    for _, entry in ipairs(settings.hooks[event]) do
      for _, hook in ipairs(entry.hooks or {}) do
        if (hook.command or ""):find("clide", 1, true) then
          already = true
        end
      end
    end
    if not already then
      vim.list_extend(settings.hooks[event], entries)
    end
  end

  local dir = Path:new(vim.fs.dirname(path))
  dir:mkdir({ parents = true })
  Path:new(path):write(vim.json.encode(settings), "w")
  vim.notify("clide: hooks installed to " .. path, vim.log.levels.INFO)
end

return M
