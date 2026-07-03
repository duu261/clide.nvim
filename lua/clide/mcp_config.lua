local Path = require("plenary.path")

local M = {}

function M.install(port)
  local settings_dir = Path:new(".claude")
  settings_dir:mkdir({ parents = true })
  local settings_path = Path:new(".claude", "settings.local.json")

  local data = {}
  if settings_path:exists() then
    local ok, decoded = pcall(vim.json.decode, settings_path:read())
    if ok and type(decoded) == "table" then
      data = decoded
    end
  end

  data.mcpServers = data.mcpServers or {}
  data.mcpServers.clide = {
    type = "sse",
    url = "http://127.0.0.1:" .. port .. "/sse",
  }

  settings_path:write(vim.json.encode(data), "w")
end

return M
