local log = require("clide.util.log")

local M = {}

--- Sentinel: handler will call respond() itself later (blocking tools).
M.DEFER = setmetatable({}, {
  __tostring = function()
    return "clide.tools.DEFER"
  end,
})

local registry = {}

--- def: { name, description, inputSchema, handler = function(args, respond) }
function M.register(def)
  registry[def.name] = def
end

function M.list()
  local out = {}
  for _, def in pairs(registry) do
    table.insert(out, {
      name = def.name,
      description = def.description,
      inputSchema = def.inputSchema,
    })
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

function M.text_result(text)
  return { content = { { type = "text", text = text } } }
end

function M.json_result(tbl)
  return M.text_result(vim.json.encode(tbl))
end

--- respond(result, err) sends the JSON-RPC response for this call.
function M.call(name, args, respond)
  local def = registry[name]
  if not def then
    respond(nil, { code = -32602, message = "Unknown tool: " .. name })
    return
  end
  local ok, result = pcall(def.handler, args, respond)
  if not ok then
    log.log("error", "tool " .. name .. " failed: " .. tostring(result))
    respond(nil, { code = -32603, message = tostring(result) })
    return
  end
  if result ~= M.DEFER then
    respond(result)
  end
end

--- Load every tool module (each self-registers at require time).
function M.setup()
  for _, mod in ipairs({
    "open_file",
    "open_diff",
    "selection_tools",
    "editors",
    "workspace",
    "diagnostics",
    "documents",
    "tabs",
    "execute_code",
  }) do
    require("clide.tools." .. mod)
  end
end

return M
