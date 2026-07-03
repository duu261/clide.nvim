local tools = require("clide.tools")

tools.register({
  name = "luaEval",
  description = "Evaluate Lua code in the Neovim instance",
  inputSchema = {
    type = "object",
    properties = { code = { type = "string" } },
    required = { "code" },
  },
  handler = function(args)
    local fn, err = loadstring("return " .. args.code)
    if not fn then
      fn, err = loadstring(args.code)
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