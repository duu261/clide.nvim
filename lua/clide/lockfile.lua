local M = {}

local Path = require("plenary.path")
local scandir = require("plenary.scandir")

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
  return Path:new(lock_dir(), port .. ".lock"):absolute()
end

function M.write(port, token)
  local lock_path = Path:new(lock_dir())
  lock_path:mkdir({ parents = true })
  local data = vim.json.encode({
    pid = vim.uv.os_getpid(),
    workspaceFolders = { vim.uv.cwd() },
    ideName = "Neovim",
    transport = "ws",
    authToken = token,
  })
  local path_obj = Path:new(lock_dir(), port .. ".lock")
  path_obj:write(data, "w", 384) -- 0600
  return path_obj:absolute()
end

function M.remove(port)
  Path:new(M.path(port)):rm()
end

function M.clean_stale()
  local lock_dir_path = lock_dir()
  local files = scandir.scan_dir(lock_dir_path, { depth = 1, search_pattern = "%.lock$" })
  if not files or #files == 0 then
    return
  end
  for _, path in ipairs(files) do
    local content = Path:new(path):read()
    local ok, data = pcall(vim.json.decode, content)
    if ok and type(data) == "table" and data.pid and vim.uv.kill(data.pid, 0) ~= 0 then
      Path:new(path):rm()
    end
  end
end

return M
