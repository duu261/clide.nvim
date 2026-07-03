local Path = require("plenary.path")

local M = {}

function M.install(port)
  -- Write MCP server config to .mcp.json (the standard project-level MCP config file).
  local path = Path:new(".mcp.json")

  local data = {}
  if path:exists() then
    local ok, decoded = pcall(vim.json.decode, path:read())
    if ok and type(decoded) == "table" then
      data = decoded
    end
  end

  data.mcpServers = data.mcpServers or {}
  data.mcpServers.clide = {
    type = "sse",
    url = "http://127.0.0.1:" .. port .. "/sse",
  }

  path:write(vim.json.encode(data), "w")

  -- Auto-approve the clide MCP server so users don't get a trust prompt.
  local settings_path = Path:new(".claude", "settings.local.json")
  local settings = {}
  if settings_path:exists() then
    local ok, decoded = pcall(vim.json.decode, settings_path:read())
    if ok and type(decoded) == "table" then
      settings = decoded
    end
  end
  settings.enabledMcpjsonServers = settings.enabledMcpjsonServers or {}
  local found = false
  for _, name in ipairs(settings.enabledMcpjsonServers) do
    if name == "clide" then
      found = true
      break
    end
  end
  if not found then
    table.insert(settings.enabledMcpjsonServers, "clide")
    settings_path:write(vim.json.encode(settings), "w")
  end
end

return M
