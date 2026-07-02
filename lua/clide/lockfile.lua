local M = {}

local dir_override

function M.set_dir(dir)
  dir_override = dir
end

local function lock_dir()
  return dir_override or vim.fs.joinpath(vim.uv.os_homedir(), ".claude", "ide")
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
  vim.fn.mkdir(lock_dir(), "p")
  local data = vim.json.encode({
    pid = vim.uv.os_getpid(),
    workspaceFolders = { vim.uv.cwd() },
    ideName = "Neovim",
    transport = "ws",
    authToken = token,
  })
  local path = M.path(port)
  local fd = assert(vim.uv.fs_open(path, "w", 384)) -- 0600
  vim.uv.fs_write(fd, data)
  vim.uv.fs_close(fd)
  return path
end

function M.remove(port)
  vim.uv.fs_unlink(M.path(port))
end

function M.clean_stale()
  local iter = vim.uv.fs_scandir(lock_dir())
  if not iter then
    return
  end
  while true do
    local name = vim.uv.fs_scandir_next(iter)
    if not name then
      break
    end
    if name:match("%.lock$") then
      local path = vim.fs.joinpath(lock_dir(), name)
      local content = table.concat(vim.fn.readfile(path), "\n")
      local ok, data = pcall(vim.json.decode, content)
      if ok and type(data) == "table" and data.pid and vim.uv.kill(data.pid, 0) ~= 0 then
        vim.uv.fs_unlink(path)
      end
    end
  end
end

return M
