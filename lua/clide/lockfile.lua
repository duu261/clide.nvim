local M = {}

local dir_override

function M.set_dir(dir)
  dir_override = dir
end

local function lock_dir()
  return dir_override or vim.fs.joinpath(vim.uv.os_homedir(), ".claude", "ide")
end

--- Write string data to file with explicit mode. Pure uv — no plenary.
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

--- Recursive mkdir with explicit mode. Stops at root or existing dir.
local function mkdir_p(dir, mode)
  if vim.fn.isdirectory(dir) == 1 then
    return true
  end
  local parent = vim.fn.fnamemodify(dir, ":h")
  if not (parent == dir or vim.fn.isdirectory(parent) == 1) then
    mkdir_p(parent, mode)
  end
  local ok, err = vim.uv.fs_mkdir(dir, mode or 448)
  if not ok and err ~= "EEXIST" then
    error("mkdir " .. dir .. ": " .. err)
  end
  return true
end

--- List .lock files in dir via uv.fs_scandir. No plenary dependency.
local function list_locks(dir)
  local result = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return result
  end
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "file" and name:match("%.lock$") then
      table.insert(result, vim.fs.joinpath(dir, name))
    end
  end
  return result
end

---@return string token 32-char lowercase hex from OS CSPRNG
function M.generate_token()
  local bytes = assert(vim.uv.random(16))
  return (bytes:gsub(".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

function M.path(port)
  return vim.fs.joinpath(lock_dir(), port .. ".lock")
end

function M.write(port, token)
  local dir = lock_dir()
  mkdir_p(dir, 448) -- 0700
  local data = vim.json.encode({
    pid = vim.uv.os_getpid(),
    workspaceFolders = { vim.uv.cwd() },
    ideName = "Neovim",
    transport = "ws",
    authToken = token,
  })
  local path = M.path(port)
  write_file(path, data, 384) -- 0600
  return path
end

function M.remove(port)
  local path = M.path(port)
  pcall(vim.uv.fs_unlink, path)
end

function M.clean_stale()
  local dir = lock_dir()
  if vim.fn.isdirectory(dir) ~= 1 then
    return
  end
  for _, path in ipairs(list_locks(dir)) do
    local content = read_file(path)
    if content then
      local ok, data = pcall(vim.json.decode, content)
      if ok and type(data) == "table" and data.pid and vim.uv.kill(data.pid, 0) ~= 0 then
        pcall(vim.uv.fs_unlink, path)
      end
    end
  end
end

return M
