-- ponytail: executeCode bypasses review by design.
local tools = require("clide.tools")
local log = require("clide.util.log")

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
    local code = args.code or ""
    local first_line = code:match("^([^\n]*)")
    -- ponytail: truncate first line to 120 chars, keeps log readable
    local preview = #first_line > 120 and first_line:sub(1, 117) .. "..." or first_line
    log.log("info", "executeCode: " .. #code .. " bytes, " .. preview)

    local fn, err = load("return " .. args.code)
    if not fn then
      fn, err = load(args.code)
    end
    if not fn then
      log.log("warn", "executeCode compile error: " .. tostring(err))
      return tools.json_result({ success = false, error = err })
    end

    local ok, result = pcall(fn)
    if not ok then
      log.log("warn", "executeCode runtime error: " .. tostring(result))
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
