local M = {}

local Path = require("plenary.path")
local watcher = nil
local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local spinner_idx = 0
local spinner_timer = nil

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
  if not spinner_timer then
    spinner_timer = vim.uv.new_timer()
    spinner_timer:start(
      200,
      200,
      vim.schedule_wrap(function()
        spinner_idx = (spinner_idx % #spinner_frames) + 1
        pcall(vim.cmd, "redrawstatus")
      end)
    )
  end
end

function M.teardown()
  if watcher then
    watcher:stop()
    watcher:close()
    watcher = nil
  end
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
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
  working = " working",
  waiting = " waiting",
  idle = " idle",
  disconnected = " disconnected",
}

--- lualine component: require("clide.status").lualine
--- lualine: connected client count. Returns empty when stopped or zero clients.
function M.client_count()
  local state = require("clide").state
  if not state.server then
    return ""
  end
  local count = state.client_count or 0
  if count < 2 then
    return ""
  end
  return count .. " clients"
end

--- lualine: IDE selection indicator. Mirrors CLI's IdeStatusIndicator.
--- Returns "⧉ N lines" when selection active, "⧉ In {file}" when file open.
function M.selection()
  local state = require("clide").state
  if not state.server or not state.connected then
    return ""
  end
  local sel = require("clide.selection").latest()
  if not sel then
    return ""
  end
  local line_count = sel.selection
    and not sel.selection.isEmpty
    and sel.selection.start
    and (sel.selection["end"].line - sel.selection.start.line + 1)
  if line_count and line_count > 0 then
    return "⧉ " .. line_count .. " lines"
  end
  if sel.filePath and sel.filePath ~= "" then
    return "⧉ " .. vim.fn.fnamemodify(sel.filePath, ":t")
  end
  return ""
end

--- lualine: last tool Claude called. Returns empty when nothing dispatched yet.
function M.last_tool()
  local state = require("clide").state
  if not state.server then
    return ""
  end
  local name = require("clide.tools")._last_tool
  if not name then
    return ""
  end
  return " " .. name
end

function M.lualine()
  local s = M.get()
  if s == "stopped" then
    return ""
  end
  local review = require("clide.review.queue").statusline()
  local base = s == "working" and (spinner_frames[spinner_idx] .. " working") or icons[s] or s
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
  local signal_file = require("clide.follow").signal_file()
  return {
    hooks = {
      PreToolUse = { { hooks = { { type = "command", command = write_cmd("working") } } } },
      Stop = { { hooks = { { type = "command", command = write_cmd("idle") } } } },
      Notification = { { hooks = { { type = "command", command = write_cmd("waiting") } } } },
      PostToolUse = {
        {
          hooks = {
            {
              type = "command",
              command = 'sh -c \'d=$(cat) && tool=$(printf "%s" "$d"'
                .. ' | sed -n "s/.*\\"tool_name\\"[[:space:]]*:[[:space:]]*'
                .. '\\"\\([^\\"]*\\)\\".*/\\1/p")'
                .. ' && fp=$(printf "%s" "$d"'
                .. ' | sed -n "s/.*\\"file_path\\"[[:space:]]*:[[:space:]]*'
                .. '\\"\\([^\\"]*\\)\\".*/\\1/p")'
                .. ' && case "$tool" in Edit|Write)'
                .. ' [ -n "$fp" ] && printf "%s\\n" "$fp" > '
                .. vim.fn.shellescape(signal_file)
                .. ";; esac'",
            },
          },
        },
      },
      SessionStart = {
        {
          hooks = {
            {
              type = "command",
              -- no apostrophes in the snippet: it lives inside a
              -- single-quoted sh string
              command = 'sh -c \'[ -n "$CLAUDE_CODE_SSE_PORT" ]'
                .. ' && printf "%s\\n"'
                .. ' "You are connected to a live Neovim editor'
                .. " via clide.nvim (WebSocket IDE protocol). IDE tools"
                .. ' are available under the mcp__ide__ prefix:"'
                .. ' "- executeCode: run Lua inside nvim process'
                .. ' (full nvim eval: open files, run commands, read buffers)"'
                .. ' "- getDiagnostics: query diagnostics from current buffer"'
                .. ' "Visual selections made by the user are pushed to'
                .. ' you automatically (at_mentioned) - no polling needed."'
                .. "; exit 0'",
            },
          },
        },
      },
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
