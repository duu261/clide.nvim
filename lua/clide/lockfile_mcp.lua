local M = {}

function M.path()
  return vim.fs.joinpath(vim.uv.os_homedir(), ".claude", "ide", "clide.mcp.json")
end

--- Write string to file with explicit mode. Pure uv — no plenary.
local function write_file(path, data, mode)
  local fd = assert(vim.uv.fs_open(path, "w", mode or 384))
  assert(vim.uv.fs_write(fd, data, 0))
  assert(vim.uv.fs_close(fd))
end

--- Read full file content. Pure uv — no plenary.
local function read_file(path)
  local fd, err = vim.uv.fs_open(path, "r", 384)
  if not fd then
    return nil, err
  end
  local stat, err2 = vim.uv.fs_fstat(fd)
  if not stat then
    vim.uv.fs_close(fd)
    return nil, err2
  end
  local data, err3 = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  if not data then
    return nil, err3
  end
  return data
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
  local dir = vim.fn.fnamemodify(full_path, ":h")
  pcall(vim.uv.fs_mkdir, dir, 448) -- 0700; ok if exists
  local tmp = full_path .. ".tmp"
  write_file(tmp, data, 384) -- 0600
  vim.uv.fs_rename(tmp, full_path)
  vim.uv.fs_chmod(full_path, 384) -- 0600; rename preserves inode mode, but be explicit
end

function M.read()
  local path = M.path()
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local content = read_file(path)
  if not content then
    return nil
  end
  local ok, data = pcall(vim.json.decode, content)
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
