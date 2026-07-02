local tools = require("clide.tools")
local selection = require("clide.selection")

tools.register({
  name = "getCurrentSelection",
  description = "Get current text selection in active editor",
  inputSchema = { type = "object", properties = vim.empty_dict() },
  handler = function()
    return tools.json_result(selection.build())
  end,
})

tools.register({
  name = "getLatestSelection",
  description = "Get most recent text selection, even unfocused",
  inputSchema = { type = "object", properties = vim.empty_dict() },
  handler = function()
    local latest = selection.latest()
    if not latest then
      return tools.json_result({ success = false, message = "No selection available" })
    end
    return tools.json_result(latest)
  end,
})

return {}
