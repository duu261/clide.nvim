--- Session management: reopen, list, and resume Claude sessions.
--- Sessions are JSON files in ~/.claude/sessions/.
local terminal = require("clide.terminal")
local log = require("clide.util.log")

local M = {}

--- Read and parse all session files, sorted by startedAt descending.
function M.list_sessions()
  local dir = vim.fn.expand("~/.claude/sessions")
  local sessions = {}
  local files = vim.fn.readdir(dir)
  for _, fname in ipairs(files or {}) do
    if fname:match("%.json$") then
      local path = dir .. "/" .. fname
      local ok, data = pcall(vim.fn.readfile, path)
      if ok and data then
        local ok2, session = pcall(vim.json.decode, table.concat(data, ""))
        if ok2 and session and session.sessionId and session.startedAt then
          table.insert(sessions, session)
        end
      end
    end
  end
  table.sort(sessions, function(a, b)
    return a.startedAt > b.startedAt
  end)
  return sessions
end

--- Build env vars for IDE integration if clide server is running.
local function ide_env()
  local state = require("clide").state
  if not state.server then
    return {}
  end
  return {
    CLAUDE_CODE_SSE_PORT = tostring(state.server.port),
    ENABLE_IDE_INTEGRATION = "true",
  }
end

--- Format a session entry for display in the picker.
local function format_session(s)
  local dt = os.date("%Y-%m-%d %H:%M", math.floor(s.startedAt / 1000))
  local name = s.name or s.sessionId:sub(1, 8)
  local status = s.status or "?"
  local cwd = s.cwd and vim.fn.fnamemodify(s.cwd, ":~") or "?"
  return string.format("%s  %s  %s  %s", dt, status:sub(1, 1), name, cwd)
end

--- Open vim.ui.select picker over session list. On pick: resume that session.
function M.pick_session()
  local sessions = M.list_sessions()
  if #sessions == 0 then
    vim.notify("No Claude sessions found", vim.log.levels.WARN)
    return
  end
  local items = {}
  for _, s in ipairs(sessions) do
    table.insert(items, {
      label = format_session(s),
      session = s,
    })
  end
  vim.ui.select(items, {
    prompt = "Claude Sessions",
    kind = "clide",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      M.resume(choice.session.sessionId)
    end
  end)
end

--- Resume a specific session by ID.
function M.resume(session_id)
  local cmd = "claude --resume " .. session_id
  terminal.provider().spawn(cmd, ide_env())
  log.log("info", "resume session: " .. session_id)
  vim.notify("Resuming Claude session " .. session_id:sub(1, 8) .. "…")
end

--- Continue the most recent conversation (-c flag).
function M.continue()
  terminal.provider().spawn("claude --continue", ide_env())
  log.log("info", "continue most recent session")
  vim.notify("Continuing most recent Claude session…")
end

return M
