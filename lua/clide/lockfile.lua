local fs = require("clide.util.fs")

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
  local dir = lock_dir()
  fs.mkdir_p(dir, 448) -- 0700
  local data = vim.json.encode({
    pid = vim.uv.os_getpid(),
    workspaceFolders = { vim.uv.cwd() },
    ideName = "Neovim",
    transport = "ws",
    authToken = token,
  })
  local path = M.path(port)
  fs.write_file(path, data, 384) -- 0600
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
  for _, path in ipairs(fs.list_locks(dir)) do
    local content = fs.read_file(path)
    if content then
      local ok, data = pcall(vim.json.decode, content)
      if ok and type(data) == "table" and data.pid and vim.uv.kill(data.pid, 0) ~= 0 then
        pcall(vim.uv.fs_unlink, path)
      end
    end
  end
end

return M
