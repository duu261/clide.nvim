local tools = require("clide.tools")
local log = require("clide.util.log")

local M = {}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

--- send: function(text) writes one JSON-RPC message to the client.
function M.new(send)
  return setmetatable({ send = send }, Dispatcher)
end

function Dispatcher:respond(id, result, err)
  local msg = { jsonrpc = "2.0", id = id }
  if err then
    msg.error = err
  else
    msg.result = result
  end
  self.send(vim.json.encode(msg))
end

function Dispatcher:notify(method, params)
  self.send(vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  }))
end

function Dispatcher:handle(text)
  local ok, msg = pcall(vim.json.decode, text)
  if not ok or type(msg) ~= "table" then
    log.log("warn", "dropped malformed message")
    return
  end

  if msg.method == "initialize" then
    self:respond(msg.id, {
      protocolVersion = "2025-03-26",
      capabilities = { tools = { listChanged = true } },
      serverInfo = { name = "clide.nvim", version = "0.1.0" },
    })
  elseif msg.method == "tools/list" then
    self:respond(msg.id, { tools = tools.list() })
  elseif msg.method == "tools/call" then
    local params = msg.params or {}
    tools.call(params.name, params.arguments or {}, function(result, err)
      self:respond(msg.id, result, err)
    end)
  elseif msg.id then
    self:respond(msg.id, nil, { code = -32601, message = "Method not found: " .. tostring(msg.method) })
  end
  -- notifications (no id) for unknown methods: ignored per JSON-RPC 2.0
end

return M
