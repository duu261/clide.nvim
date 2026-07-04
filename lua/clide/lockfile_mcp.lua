local M = {}
local Path = require("plenary.path")

function M.path()
  return vim.fs.joinpath(vim.uv.os_homedir(), ".claude", "ide", "clide.mcp.json")
end

function M.write_child(port, child_pid)
  local session_bytes = assert(vim.uv.random(8))
  local session_id = session_bytes:gsub(".", function(c)
    return string.format("%02x", string.byte(c))
  end)
  local data = vim.json.encode({
    pid = child_pid,
    ssePort = port,
    sessionId = session_id,
  })
  local full_path = M.path()
  local tmp = full_path .. ".tmp"
  Path:new(tmp):write(data, "w", 384) -- 0600
  vim.uv.fs_rename(tmp, full_path)
end

function M.read()
  local path = M.path()
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, Path:new(path):read())
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

function M.remove()
  local full_path = M.path()
  local tmp = full_path .. ".tmp"
  if vim.fn.filereadable(tmp) == 1 then
    vim.uv.fs_unlink(tmp)
  end
  if vim.fn.filereadable(full_path) == 1 then
    vim.uv.fs_unlink(full_path)
  end
end

return M
