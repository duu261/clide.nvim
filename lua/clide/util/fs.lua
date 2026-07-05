--- Pure-uv file I/O utilities. No plenary dependency.
local M = {}

--- Write string data to file with explicit mode.
--- @param path string
--- @param data string
--- @param mode integer|nil file permission bits (e.g. 384 for 0600)
function M.write_file(path, data, mode)
  local fd = assert(vim.uv.fs_open(path, "w", mode or 384))
  assert(vim.uv.fs_write(fd, data, 0))
  assert(vim.uv.fs_close(fd))
end

--- Read full file content.
--- @param path string
--- @return string|nil data
--- @return string|nil err
function M.read_file(path)
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

--- Recursive mkdir with explicit mode. Stops at root or existing dir.
--- @param dir string
--- @param mode integer|nil 448 for 0700
function M.mkdir_p(dir, mode)
  if vim.fn.isdirectory(dir) == 1 then
    return true
  end
  local parent = vim.fn.fnamemodify(dir, ":h")
  if not (parent == dir or vim.fn.isdirectory(parent) == 1) then
    M.mkdir_p(parent, mode)
  end
  local ok, err = vim.uv.fs_mkdir(dir, mode or 448)
  if not ok and not err:find("EEXIST", 1, true) then
    error("mkdir " .. dir .. ": " .. err)
  end
  return true
end

--- List .lock files in dir via uv.fs_scandir.
--- @param dir string
--- @return string[]
function M.list_locks(dir)
  local result = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return result
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if typ == "file" and name:match("%.lock$") then
      table.insert(result, vim.fs.joinpath(dir, name))
    end
  end
  return result
end

return M
