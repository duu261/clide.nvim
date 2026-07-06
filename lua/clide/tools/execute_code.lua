-- ponytail: executeCode bypasses review by design.
local tools = require("clide.tools")

-- Lua 5.1/JIT compat: loadstring deprecated in 5.4 but that's not our runtime
local load = loadstring or load

tools.register({
  name = "executeCode",
  description = "Evaluate Lua code in the Neovim instance",
  inputSchema = {
    type = "object",
    properties = { code = { type = "string" } },
    required = { "code" },
  },
  handler = function(args)
    local fn, err = load("return " .. args.code)
    if not fn then
      fn, err = load(args.code)
    end
    if not fn then
      return tools.json_result({ success = false, error = err })
    end

    local ok, result = pcall(fn)
    if not ok then
      return tools.json_result({ success = false, error = tostring(result) })
    end

    local ok2, encoded = pcall(vim.json.encode, result)
    if ok2 then
      return tools.text_result(encoded)
    end
    return tools.text_result(vim.inspect(result))
  end,
})

return {}
